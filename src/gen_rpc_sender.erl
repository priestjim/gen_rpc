%%% -*-mode:erlang;coding:utf-8;tab-width:4;c-basic-offset:4;indent-tabs-mode:()-*-
%%% ex: set ft=erlang fenc=utf-8 sts=4 ts=4 sw=4 et:
%%%
%%% Copyright 2015 Panagiotis Papadomitsos, Inc. All Rights Reserved.
%%%
%%% Original concept inspired and some code copied from
%%% https://erlangcentral.org/wiki/index.php?title=Building_a_Non-blocking_TCP_server_using_OTP_principles

-module(gen_rpc_sender).
-author("Panagiotis Papadomitsos <pj@ezgr.net>").

%%% Behaviour
-behaviour(gen_server).

%%% Used for debug printing messages when in test
-include("include/debug.hrl").

%%% Local state
-record(state, {socket :: port()}).

%%% Default TCP options
-define(DEFAULT_TCP_OPTS, [inet, binary, {packet, 4}, {nodelay, true}, {reuseaddr, true}, {keepalive, true}, {tos, 4}, {active, false}]).

%%% Supervisor functions
-export([start_link/1, stop/1]).

%%% FSM functions
-export([call/3, call/4, cast/3, cast/4]).

%%% Behaviour callbacks
-export([init/1, handle_call/3, handle_cast/2,
        handle_info/2, terminate/2, code_change/3]).

%%% ===================================================
%%% Supervisor functions
%%% ===================================================
start_link(Node) when is_atom(Node) ->
    gen_server:start_link({local,Node}, ?MODULE, {Node}, []).

stop(Node) when is_atom(Node) ->
    gen_server:call(Node, stop).

%%% ===================================================
%%% Server functions
%%% ===================================================
call(Node, M, F) when is_atom(Node), is_atom(M), is_atom(F) ->
    call(Node, M, F, []).

call(Node, M, F, A) when is_atom(Node), is_atom(M), is_atom(F), is_list(A) ->
    %% Naming our gen_server as the node we're calling - this will probably
    %% change in the future
    case whereis(Node) of
        undefined ->
            ?debug("No sender process for CALL to node [~s] was found alive. Starting one.", [Node]),
            case gen_rpc_sender_sup:start_child(Node) of
                {ok, NewPid} ->
                    gen_server:call(NewPid, {call, M, F, A}, infinity);
                {error, Reason} ->
                    Reason
            end;
        Pid ->
            ?debug("Sender process for CALL to node [~s] is [~p].", [Node, Pid]),
            gen_server:call(Pid, {call, M, F, A}, infinity)
    end.

cast(Node, M, F) when is_atom(Node), is_atom(M), is_atom(F) ->
    cast(Node, M, F, []).

cast(Node, M, F, A) when is_atom(Node), is_atom(M), is_atom(F), is_list(A) ->
    %% Naming our gen_server as the node we're calling - this will probably
    %% change in the future
    case whereis(Node) of
        undefined ->
            ?debug("No sender process for CAST to node [~s] was found alive. Starting one.", [Node]),
            case gen_rpc_sender_sup:start_child(Node) of
                {ok, NewPid} ->
                    gen_server:cast(NewPid, {call, M, F, A});
                {error, Reason} ->
                    Reason
            end;
        Pid ->
            ?debug("Sender process for CAST to node [~s] is [~p].", [Node, Pid]),
            gen_server:cast(Pid, {cast, M, F, A})
    end.

%%% ===================================================
%%% Behaviour callbacks
%%% ===================================================
%% TODO:
%% Implement gen_server timeout like a socket timeout
init({Node}) ->
    process_flag(trap_exit, true),
    %% Perform an in-band RPC call to the remote node
    %% asking it to launch a listener for us and return us
    %% the port that has been allocated for us
    ?debug("Initializing connection to node [~s]", [Node]),
    case rpc:call(Node, gen_rpc_receiver_sup, start_child, [node()]) of
        {ok, Port} ->
            ?debug("Remote listener started successfully in port ~B", [Port]),
            %% Fetching the IP ourselves, since the remote node
            %% does not have a straightforward way of returning
            %% the proper remote IP
            Address = get_remote_node_ip(Node),
            case gen_tcp:connect(Address, Port, ?DEFAULT_TCP_OPTS, 5000) of %% TODO: Make timeout dynamic
                {ok, Socket} ->
                    ?debug("Successfully connected to [~p:~B]", [Address, Port]),
                    {ok, #state{socket=Socket}};
                {error, Reason} ->
                    ?debug("Connection to [~p] failed with reason [~p]", [Address, Reason]),
                    {stop, {badtcp, Reason}}
            end;
        {badrpc, Reason} ->
            {stop, {badrpc, Reason}}
    end.

handle_call({call, _M, _F, _A} = PacketTuple, _From, #state{socket=Socket} = State) ->
    Ref = erlang:make_ref(),
    Packet = erlang:term_to_binary({node(), Ref, PacketTuple}),
    ?debug("Constructing CALL term to transmit to socket [~p] with reference [~p]", [Socket, Ref]),
    %% If we fail, let it crash!
    ok = inet:setopts(Socket, [{active, once}, {send_timeout, 5000}]), %% TODO: Make timeout dynamic
    ?debug("Transmitting CALL term to socket [~p]", [Socket]),
    case gen_tcp:send(Socket, Packet) of
        {error, timeout} ->
            %% Terminate will handle closing the socket
            ?debug("Transmitting CALL term to socket [~p] failed with reason [timeout]", [Socket]),
            {stop, {badtcp,send_timeout}, {badtcp,send_timeout}, State};
        {error, OtherError} ->
            ?debug("Transmitting CALL term to socket [~p] failed with reason [~p]", [Socket, OtherError]),
            {stop, {badtcp,OtherError}, {badtcp,OtherError}, State};
        ok ->
            ?debug("CALL sent successfully for socket [~p]", [Socket]),
            %% TODO: Make receive timeout dynamic since
            %% this is essentially the same as the gen_server timeout
            case wait_for_reply(Socket, Ref, 5000) of
                {ok, Response} ->
                    ?debug("CALL with reference [~p] received successfully via socket [~p]", [Ref, Socket]),
                    {reply, Response, State};
                {error, Reason} ->
                    ?debug("CALL with reference [~p] failed in socket [~p] with reason [~p]", [Ref, Socket, Reason]),
                    {reply, {badtcp,Reason}, State}
            end
    end;

%% Gracefully terminate
handle_call(stop, _From, State) ->
    {stop, normal, ok, State};

%% Catch-all for calls - die if we get a message we don't expect
handle_call(_Message, _Caller, State) ->
    {stop, {error, unknown_message}, State}.

%% Catch-all for casts
handle_cast({cast,_M,_F,_A} = PacketTuple, #state{socket=Socket} = State) ->
    %% Cast requests do not need a reference
    Packet = erlang:term_to_binary({node(), PacketTuple}),
    ?debug("Constructing CAST term to transmit to socket [~p].", [Socket]),
    %% If we fail, let it crash!
    case gen_tcp:send(Socket, Packet) of
        {error, timeout} ->
            %% Terminate will handle closing the socket
            ?debug("Transmitting CAST term to socket [~p] failed with reason [timeout].", [Socket]),
            {stop, {badtcp,send_timeout}, State};
        {error, OtherError} ->
            ?debug("Transmitting CAST term to socket [~p] failed with reason [~p].", [Socket, OtherError]),
            {stop, {badtcp,OtherError}, State};
        ok ->
            ?debug("CAST sent successfully for socket [~p].", [Socket]),
            {noreply, State}
    end;

%% Catch-all for casts - die if we get a message we don't expect
handle_cast(_Message, State) ->
    {stop, State}.

%% We've received a message from an RPC call that has timed out but
%% still produced a result. Just drop the data for now.
handle_info({tcp,Socket,_Data}, #state{socket=Socket} = State) ->
    ?debug("Received unexpected data [~w] from socket [~p].", [_Data, Socket]),
    {noreply, State};
handle_info({tcp_closed, Socket}, #state{socket=Socket} = State) ->
    ?debug("Socket [~p] closed the TCP channel. Stopping.", [Socket]),
    {stop, normal, State};
handle_info({tcp_error, Socket, _Reason}, #state{socket=Socket} = State) ->
    ?debug("Socket [~p] caused error [~p] in the TCP channel. Stopping.", [Socket, _Reason]),
    {stop, normal, State};

%% Catch-all for info - ignore any message we don't care about
handle_info(_Message, State) ->
    {noreply, State}.

%% Stub functions
code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

terminate(_Reason, #state{socket=Socket}) ->
    (catch gen_tcp:close(Socket)),
    ok.

%%% ===================================================
%%% Private functions
%%% ===================================================
%% For loopback communication and performance testing
get_remote_node_ip(Node) when Node =:= node() ->
    {127,0,0,1};
get_remote_node_ip(Node) ->
    {ok, NodeInfo} = net_kernel:node_info(Node),
    {address, AddressInfo} = lists:keyfind(address, 1, NodeInfo),
    {net_address, {Ip, _Port}, _Name, _Proto, _Channel} = AddressInfo,
    ?debug("Remote node address discovered to be [~p]", [Ip]),
    Ip.

%% Wait for a reply
%% TODO: Make this resilient enough so that
%% timeout when a node is dead closes the connection
%% and contains logic on how to handle messages that come
%% after a timeout has occurred
wait_for_reply(Socket, Ref, Timeout) ->
    receive
        {tcp, Socket, Data} ->
            %% Process the request. If the response is a response
            %% for a previous request that we timed out but eventually
            %% came back while we were waiting for a different response
            %% drop it an loop back
            try erlang:binary_to_term(Data) of
                {Ref, Result} ->
                    ?debug("Received proper reply to CALL request with reference [~p] from socket [~p]", [Ref, Socket]),
                    {ok, Result};
                {_OtherRef, _Result} ->
                    ?debug("Received stale reply to CALL request with reference [~p] from socket [~p]. Ignoring.", [_OtherRef, Socket]),
                    ok = inet:setopts(Socket, [{active, once}]),
                    wait_for_reply(Socket, Ref, Timeout);
                _OtherData ->
                    ?debug("Received erroneous reply from socket [~p] with payload [~p]. Ignoring.", [Socket, _OtherData]),
                    ok = inet:setopts(Socket, [{active, once}]),
                    wait_for_reply(Socket, Ref, Timeout)
            catch
                error:badarg ->
                    {error, corrupt_data}
            end
    after
        Timeout ->
            {error, receive_timeout}
    end.