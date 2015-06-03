%%% -*-mode:erlang;coding:utf-8;tab-width:4;c-basic-offset:4;indent-tabs-mode:()-*-
%%% ex: set ft=erlang fenc=utf-8 sts=4 ts=4 sw=4 et:
%%%
%%% Copyright 2015 Panagiotis Papadomitsos. All Rights Reserved.
%%%
%%% Original concept inspired and some code copied from
%%% https://erlangcentral.org/wiki/index.php?title=Building_a_Non-blocking_TCP_server_using_OTP_principles

-module(gen_rpc_acceptor).
-author("Panagiotis Papadomitsos <pj@ezgr.net>").

%%% Behaviour
-behaviour(gen_fsm).

%%% Include this library's name macro
-include("include/app.hrl").
%%% Used for debug printing messages when in test
-include("include/debug.hrl").

%% Local state
-record(state, {socket = undefined :: port() | undefined,
        send_timeout :: non_neg_integer(),
        inactivity_timeout :: non_neg_integer() | infinity,
        client_ip :: tuple(),
        client_node :: atom()}).

%%% Server functions
-export([start_link/2, set_socket/2, stop/1]).

%% gen_fsm callbacks
-export([init/1, handle_event/3, handle_sync_event/4,
        handle_info/3, terminate/3, code_change/4]).

%% FSM States
-export([waiting_for_socket/2, waiting_for_data/2]).

%%% ===================================================
%%% Supervisor functions
%%% ===================================================
start_link(ClientIp, Node) when is_tuple(ClientIp), is_atom(Node) ->
    gen_fsm:start_link(?MODULE, {ClientIp, Node}, []).

stop(Pid) when is_pid(Pid) ->
     gen_fsm:sync_send_all_state_event(Pid, stop).

%%% ===================================================
%%% Server functions
%%% ===================================================
set_socket(Pid, Socket) when is_pid(Pid), is_port(Socket) ->
    gen_fsm:send_event(Pid, {socket_ready, Socket}).

%%% ===================================================
%%% Behaviour callbacks
%%% ===================================================
init({ClientIp, Node}) ->
    process_flag(trap_exit, true),
    ?debug("Initializing acceptor for node [~s] with IP [~w]", [Node, ClientIp]),
    {ok, SendTO} = application:get_env(?APP, send_timeout),
    {ok, TTL} = application:get_env(?APP, server_inactivity_timeout),
    %% Store the client's IP and the node in our state
    {ok, waiting_for_socket, #state{client_ip=ClientIp,client_node=Node,send_timeout=SendTO,inactivity_timeout=TTL}}.

waiting_for_socket({socket_ready, Socket},
                #state{client_ip = ClientIp} = State) when is_port(Socket) ->
    %% Filter the ports we're willing to accept connections from
    {ok, {Ip, _Port}} = inet:peername(Socket),
    if
        ClientIp =/= Ip ->
            ?debug("Rejecting connection from client IP [~w] as it is different from [~w]", [Ip, ClientIp]),
            {stop, {badtcp,invalid_client_ip}, State};
        true ->
            % Now we own the socket
            ?debug("Acquiring ownership for socket [~p] from client IP [~w]", [Socket, ClientIp]),
            ok = inet:setopts(Socket, [{active, once}, {packet, 4}, binary, {send_timeout, State#state.send_timeout}]),
            {next_state, waiting_for_data, State#state{socket=Socket}}
    end.

%% Notification event coming from client
waiting_for_data({data, Data}, #state{socket=Socket,client_node=Node} = State) ->
    %% The meat of the whole project: process a function call and return
    %% the data
    ?debug("Received request from node [~s]. Processing!", [Node]),
    try erlang:binary_to_term(Data) of
        {Node, Ref, {call, M, F, A}} ->
            ?debug("Received CALL request from node [~s] with [M:~s][F:~s][A:~p].", [Node, M, F, A]),
            %% Abomination
            Result = erlang:apply(M, F, A),
            Packet = {Ref, Result},
            PacketBin = erlang:term_to_binary(Packet),
            case gen_tcp:send(Socket, PacketBin) of
                ok ->
                    ?debug("Replied to CALL request from node [~s] with [M:~s][F:~s][A:~p].", [Node, M, F, A]),
                    ok = inet:setopts(Socket, [{active, once}]),
                    {next_state, waiting_for_data, State, State#state.inactivity_timeout};
                {error, Reason} ->
                    ?debug("Failed to reply to CALL request from node [~s] with [M:~s][F:~s][A:~p] with reason [~w]", [Node, M, F, A, Reason]),
                    {stop, {badtcp, Reason}, State}
            end;
        {Node, {cast, M, F, A}} ->
            ?debug("Received CAST request from node [~s] with [M:~s][F:~s][A:~p].", [Node, M, F, A]),
            _Pid = erlang:spawn(M, F, A),
            ok = inet:setopts(Socket, [{active, once}]),
            {next_state, waiting_for_data, State, State#state.inactivity_timeout};
        _OtherData ->
            ?debug("Received erroneous request from node [~s] with payload [~p]", [Node, _OtherData]),
            ok = inet:setopts(Socket, [{active, once}]),
            {next_state, waiting_for_data, State, State#state.inactivity_timeout}
    catch
        error:badarg ->
            {stop, {badtcp, corrupt_data}, State}
    end;
%% Handle the inactivity timeout gracefully
waiting_for_data(timeout, State) ->
    ?debug("Acceptor timed-out because of inactivity. Exiting!"),
    _Pid = erlang:spawn(gen_rpc_acceptor_sup, stop_child, [self()]),
    {stop, normal, State}.

handle_event(Event, StateName, State) ->
    {stop, {StateName, undefined_event, Event}, State}.

%% Gracefully terminate
handle_sync_event(stop, _From, _StateName, State) ->
    {stop, normal, ok, State};

handle_sync_event(Event, _From, StateName, State) ->
    {stop, {StateName, undefined_event, Event}, State}.

%% Incoming data handlers
handle_info({tcp, Socket, Data}, waiting_for_data, #state{socket=Socket} = State) when Socket =/= undefined ->
    waiting_for_data({data, Data}, State);

handle_info({tcp_closed, Socket}, _StateName,
            #state{client_ip=_ClientIp,client_node=_Node,socket=Socket} = State) ->
    ?debug("Node [~s] with IP [~w] closed the TCP channel. Stopping.", [_Node, _ClientIp]),
    {stop, normal, State};
handle_info({tcp_error, Socket, _Reason}, _StateName,
            #state{client_ip=_ClientIp,client_node=_Node,socket=Socket} = State) ->
    ?debug("Node [~s] with IP [~w] caused error [~p] in the TCP channel. Stopping.", [_Node, _ClientIp, _Reason]),
    {stop, normal, State};
%% Catch-all for info - ignore any message we don't care about
handle_info(_Info, StateName, State) ->
    {next_state, StateName, StateName, State, State#state.inactivity_timeout}.

code_change(_OldVsn, StateName, State, _Extra) ->
    {ok, StateName, State}.

%% Terminate normally if we haven't received the socket yet
terminate(_Reason, _StateName, #state{socket=undefined}) ->
    ok;
%% Terminate by closing the socket
terminate(_Reason, _StateName, #state{socket=Socket}) ->
    ?debug("Acceptor process for socket [~p] is exiting. Closing socket!", [Socket]),
    (catch gen_tcp:close(Socket)),
    ok.
