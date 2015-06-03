%%% -*-mode:erlang;coding:utf-8;tab-width:4;c-basic-offset:4;indent-tabs-mode:()-*-
%%% ex: set ft=erlang fenc=utf-8 sts=4 ts=4 sw=4 et:
%%%
%%% Copyright 2015 Panagiotis Papadomitsos. All Rights Reserved.
%%%
%%% Original concept inspired and some code copied from
%%% https://erlangcentral.org/wiki/index.php?title=Building_a_Non-blocking_TCP_server_using_OTP_principles

-module(gen_rpc_client).
-author("Panagiotis Papadomitsos <pj@ezgr.net>").

%%% Behaviour
-behaviour(gen_server).

%%% Include this library's name macro
-include("include/app.hrl").

%%% Local state
-record(state, {socket :: port(),
        send_timeout :: non_neg_integer(),
        receive_timeout :: non_neg_integer(),
        inactivity_timeout :: non_neg_integer() | infinity}).

%%% Default TCP options
-define(DEFAULT_TCP_OPTS, [binary, {packet,4}, {nodelay,true}, {send_timeout_close,true},
                           {reuseaddr,true}, {keepalive,true}, {tos,4}, {active,false}]).

%%% Supervisor functions
-export([start_link/1, stop/1]).

%%% FSM functions
-export([call/3, call/4, call/5, call/6, cast/3, cast/4, cast/5]).

%%% Behaviour callbacks
-export([init/1, handle_call/3, handle_cast/2,
        handle_info/2, terminate/2, code_change/3]).

%%% ===================================================
%%% Supervisor functions
%%% ===================================================
start_link(Node) when is_atom(Node) ->
    %% Naming our gen_server as the node we're calling as it is extremely efficent:
    %% We'll never deplete atoms because all connected node names are already atoms in this VM
    gen_server:start_link({local,Node}, ?MODULE, {Node}, []).

stop(Node) when is_atom(Node) ->
    gen_server:call(Node, stop).

%%% ===================================================
%%% Server functions
%%% ===================================================
%% Simple server call with no args and default timeout values
call(Node, M, F) when is_atom(Node), is_atom(M), is_atom(F) ->
    call(Node, M, F, [], undefined, undefined).

%% Simple server call with args and default timeout values
call(Node, M, F, A) when is_atom(Node), is_atom(M), is_atom(F), is_list(A) ->
    call(Node, M, F, A, undefined, undefined).

%% Simple server call with custom receive timeout value
call(Node, M, F, A, RecvTO) when is_atom(Node), is_atom(M), is_atom(F), is_list(A),
                                 is_integer(RecvTO) orelse RecvTO =:= infinity ->
    call(Node, M, F, A, RecvTO, undefined).

%% Simple server call with custom receive and send timeout values
%% This is the function that all of the above call
call(Node, M, F, A, RecvTO, SendTO) when is_atom(Node), is_atom(M), is_atom(F), is_list(A),
                                         RecvTO =:= undefined orelse is_integer(RecvTO) orelse RecvTO =:= infinity,
                                         SendTO =:= undefined orelse is_integer(SendTO) orelse SendTO =:= infinity ->
    case whereis(Node) of
        undefined ->
            ok = lager:info("function=call event=client_process_not_found server_node=\"~s\" action=spawning_client", [Node]),
            case gen_rpc_client_sup:start_child(Node) of
                {ok, NewPid} ->
                    %% We take care of CALL inside the gen_server
                    %% This is not resilient enough if the caller's mailbox is full
                    %% but it's good enough for now
                    gen_server:call(NewPid, {{call,M,F,A},RecvTO,SendTO}, infinity);
                {error, Reason} ->
                    Reason
            end;
        Pid ->
            ok = lager:debug("function=call event=client_process_found pid=\"~p\" server_node=\"~s\"", [Pid, Node]),
            gen_server:call(Pid, {{call,M,F,A},RecvTO,SendTO}, infinity)
    end.

%% Simple server cast with no args and default timeout values
cast(Node, M, F) when is_atom(Node), is_atom(M), is_atom(F) ->
    cast(Node, M, F, [], undefined).

%% Simple server cast with args and default timeout values
cast(Node, M, F, A) when is_atom(Node), is_atom(M), is_atom(F), is_list(A) ->
    cast(Node, M, F, A, undefined).

%% Simple server cast with custom send timeout value
%% This is the function that all of the above casts call
cast(Node, M, F, A, SendTO) when is_atom(Node), is_atom(M), is_atom(F), is_list(A),
                                 SendTO =:= undefined orelse is_integer(SendTO) orelse SendTO =:= infinity ->
    %% Naming our gen_server as the node we're calling as it is extremely efficent:
    %% We'll never deplete atoms because all connected node names are already atoms in this VM
    case whereis(Node) of
        undefined ->
            ok = lager:info("function=cast event=client_process_not_found server_node=\"~s\" action=spawning_client", [Node]),
            case gen_rpc_client_sup:start_child(Node) of
                {ok, NewPid} ->
                    %% We take care of CALL inside the gen_server
                    %% This is not resilient enough if the caller's mailbox is full
                    %% but it's good enough for now
                    gen_server:cast(NewPid, {{cast,M,F,A},SendTO});
                {error, Reason} ->
                    Reason
            end;
        Pid ->
            ok = lager:debug("function=cast event=client_process_found pid=\"~p\" server_node=\"~s\"", [Pid, Node]),
            gen_server:cast(Pid, {{cast,M,F,A},SendTO})
    end.


%%% ===================================================
%%% Behaviour callbacks
%%% ===================================================
%% TODO:
%% Implement gen_server timeout like a socket timeout
init({Node}) ->
    process_flag(trap_exit, true),
    %% Extract application-specific settings
    Settings = application:get_all_env(?APP),
    {connect_timeout, ConnTO} = lists:keyfind(connect_timeout, 1, Settings),
    {send_timeout, SendTO} = lists:keyfind(send_timeout, 1, Settings),
    {receive_timeout, RecvTO} = lists:keyfind(receive_timeout, 1, Settings),
    {client_inactivity_timeout, TTL} = lists:keyfind(client_inactivity_timeout, 1, Settings),
    %% Perform an in-band RPC call to the remote node
    %% asking it to launch a listener for us and return us
    %% the port that has been allocated for us
    ok = lager:info("function=init event=initializing_client server_node=\"~s\" connect_timeout=~B send_timeout=~B receive_timeout=~B inactivity_timeout=~p",
                    [Node, ConnTO, SendTO, RecvTO, TTL]),
    case rpc:call(Node, gen_rpc_server_sup, start_child, [node()], ConnTO) of
        {ok, Port} ->
            %% Fetching the IP ourselves, since the remote node
            %% does not have a straightforward way of returning
            %% the proper remote IP
            Address = get_remote_node_ip(Node),
            ok = lager:debug("function=init event=remote_server_started_successfully server_node=\"~s\" server_ip=\"~p:~B\"",
                             [Node, Address, Port]),
            case gen_tcp:connect(Address, Port, ?DEFAULT_TCP_OPTS, ConnTO) of
                {ok, Socket} ->
                    ok = lager:debug("function=init event=connecting_to_server server_node=\"~s\" server_ip=\"~s:~B\" result=success",
                                     [Node, Address, Port]),
                    {ok, #state{socket=Socket,send_timeout=SendTO,receive_timeout=RecvTO,inactivity_timeout=TTL}, TTL};
                {error, Reason} ->
                    ok = lager:error("function=init event=connecting_to_server server_node=\"~s\" server_ip=\"~s:~B\" result=failure reason=\"~p\"",
                                     [Node, Address, Port, Reason]),
                    {stop, {badtcp,Reason}}
            end;
        {badrpc, Reason} ->
            {stop, {badrpc, Reason}}
    end.

%% This is the actual CALL handler
handle_call({{call,_M,_F,_A} = PacketTuple, URecvTO, USendTO}, _From, #state{socket=Socket} = State) ->
    {RecvTO, SendTO} = merge_timeout_values(State#state.receive_timeout, URecvTO, State#state.send_timeout, USendTO),
    Ref = erlang:make_ref(),
    Packet = erlang:term_to_binary({node(), Ref, PacketTuple}),
    ok = lager:debug("function=handle_call message=call event=constructing_call_term socket=\"~p\" call_reference=\"~p\"",
                     [Socket, Ref]),
    ok = inet:setopts(Socket, [{active, once}, {send_timeout, SendTO}]),
    case gen_tcp:send(Socket, Packet) of
        {error, timeout} ->
            %% Terminate will handle closing the socket
            ok = lager:error("function=handle_call message=call event=transmission_failed socket=\"~p\" call_reference=\"~p\" reason=\"timeout\"",
                             [Socket, Ref]),
            {stop, {badtcp,send_timeout}, {badtcp,send_timeout}, State};
        {error, Reason} ->
            ok = lager:error("function=handle_call message=call event=transmission_failed socket=\"~p\" call_reference=\"~p\" reason=\"~p\"",
                             [Socket, Ref, Reason]),
            {stop, {badtcp,Reason}, {badtcp,Reason}, State};
        ok ->
            ok = lager:debug("function=handle_call message=call event=transmission_succeeded socket=\"~p\" call_reference=\"~p\"",
                             [Socket, Ref]),
            case wait_for_reply(Socket, Ref, RecvTO) of
                {ok, Response} ->
                    ok = lager:debug("function=handle_call message=call event=reply_received_successfully socket=\"~p\" call_reference=\"~p\" response=\"~p\"",
                                     [Socket, Ref, Response]),
                    {reply, Response, State, State#state.inactivity_timeout};
                {error, ReplyReason} ->
                    ok = lager:notice("function=handle_call message=call event=failed_to_receive_reply socket=\"~p\" call_reference=\"~p\" reason=\"~p\"",
                                      [Socket, Ref, ReplyReason]),
                    {reply, {badrpc,ReplyReason}, State, State#state.inactivity_timeout}
            end
    end;

%% Gracefully terminate
handle_call(stop, _From, State) ->
    ok = lager:debug("function=handle_call event=stopping_client socket=\"~p\"", [State#state.socket]),
    {stop, normal, ok, State};

%% Catch-all for calls - die if we get a message we don't expect
handle_call(Msg, _Caller, State) ->
    ok = lager:critical("function=handle_call event=uknown_call_received socket=\"~p\" message=\"~p\" action=stopping", [State#state.socket, Msg]),
    {stop, {unknown_call, Msg}, State}.

%% Catch-all for casts
handle_cast({{cast,_M,_F,_A} = PacketTuple, USendTO}, #state{socket=Socket} = State) ->
    {_RecvTO, SendTO} = merge_timeout_values(undefined, undefined, State#state.send_timeout, USendTO),
    %% Cast requests do not need a reference
    Packet = erlang:term_to_binary({node(), PacketTuple}),
    ok = lager:debug("function=handle_cast message=cast event=constructing_cast_term socket=\"~p\"", [Socket]),
    %% Set the send timeout and do not run in active mode - we're a cast!
    ok = inet:setopts(Socket, [{active, false}, {send_timeout, SendTO}]),
    case gen_tcp:send(Socket, Packet) of
        {error, timeout} ->
            %% Terminate will handle closing the socket
            ok = lager:error("function=handle_cast message=cast event=transmission_failed socket=\"~p\" reason=\"timeout\"", [Socket]),
            {stop, {badtcp,send_timeout}, State};
        {error, Reason} ->
            ok = lager:error("function=handle_cast message=cast event=transmission_failed socket=\"~p\" reason=\"~p\"", [Socket, Reason]),
            {stop, {badtcp,Reason}, State};
        ok ->
            ok = lager:debug("function=handle_cast message=cast event=transmission_succeeded socket=\"~p\"", [Socket]),
            {noreply, State, State#state.inactivity_timeout}
    end;

%% Catch-all for casts - die if we get a message we don't expect
handle_cast(Msg, State) ->
    ok = lager:critical("function=handle_call event=uknown_cast_received socket=\"~p\" message=\"~p\" action=stopping", [State#state.socket, Msg]),
    {stop, {unknown_cast, Msg}, State}.

%% We've received a message from an RPC call that has timed out but
%% still produced a result. Just drop the data for now.
handle_info({tcp,Socket,Data}, #state{socket=Socket} = State) ->
    ok = lager:notice("function=handle_info message=tcp event=stale_data_received socket=\"~p\" data=\"~p\"", [Socket, Data]),
    {noreply, State, State#state.inactivity_timeout};

handle_info({tcp_closed, Socket}, #state{socket=Socket} = State) ->
    ok = lager:notice("function=handle_info message=tcp_closed event=tcp_socket_closed socket=\"~p\" action=stopping", [Socket]),
    {stop, normal, State};

handle_info({tcp_error, Socket, Reason}, #state{socket=Socket} = State) ->
    ok = lager:notice("function=handle_info message=tcp_error event=tcp_socket_error socket=\"~p\" reason=\"~p\" action=stopping", [Socket, Reason]),
    {stop, normal, State};

%% Handle the inactivity timeout gracefully
handle_info(timeout, State) ->
    ok = lager:info("function=handle_info message=timeout event=client_inactivity_timeout socket=\"~p\" action=stopping", [State#state.socket]),
    {stop, normal, State};

%% Catch-all for info - our protocol is strict so die!
handle_info(Msg, State) ->
    ok = lager:critical("function=handle_info event=uknown_message_received socket=\"~p\" message=\"~p\" action=stopping", [State#state.socket, Msg]),
    {stop, {unknown_info, Msg}, State}.

%% Stub functions
code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

terminate(_Reason, #state{socket=Socket}) ->
    ok = lager:debug("function=terminate socket=\"~p\"", [Socket]),
    (catch gen_tcp:close(Socket)),
    _Pid = erlang:spawn(gen_rpc_client_sup, stop_child, [self()]),
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
    ok = lager:debug("function=get_remote_node_ip node=\"~s\" ip_address=\"~p\"", [Node, Ip]),
    Ip.

%% Wait for a reply
wait_for_reply(Socket, Ref, Timeout) ->
    receive
        {tcp, Socket, Data} ->
            %% Process the request. If the response is a response
            %% for a previous request that we timed out but eventually
            %% came back while we were waiting for a different response
            %% drop it an loop back
            try erlang:binary_to_term(Data) of
                {Ref, Result} ->
                    ok = lager:debug("function=wait_for_reply event=reply_received socket=\"~p\" call_reference=\"~p\" reply=\"~p\"",
                                     [Socket, Ref, Result]),
                    {ok, Result};
                {OtherRef, OtherResult} ->
                    ok = lager:debug("function=wait_for_reply event=stale_reply_received socket=\"~p\" call_reference=\"~p\" received_reference=\"~p\" reply=\"~p\" action=ignoring",
                                     [Socket, Ref, OtherRef, OtherResult]),
                    ok = inet:setopts(Socket, [{active, once}]),
                    wait_for_reply(Socket, Ref, Timeout);
                OtherData ->
                    ok = lager:error("function=wait_for_reply event=erroneous_reply_received socket=\"~p\" call_reference=\"~p\" data=\"~p\" action=ignoring",
                                     [Socket, Ref, OtherData]),
                    ok = inet:setopts(Socket, [{active, once}]),
                    wait_for_reply(Socket, Ref, Timeout)
            catch
                error:badarg ->
                    ok = lager:error("function=wait_for_reply event=corrupt_data_received socket=\"~p\" call_reference=\"~p\" action=returning_error", [Socket, Ref]),
                    {error, corrupt_data}
            end
    after
        Timeout ->
            {error, timeout}
    end.

%% Merging user-define timeout values with state timeout values
merge_timeout_values(SRecvTO, undefined, SSendTO, undefined) ->
    {SRecvTO, SSendTO};
merge_timeout_values(_SRecvTO, URecvTO, SSendTO, undefined) ->
    {URecvTO, SSendTO};
merge_timeout_values(SRecvTO, undefined, _SSendTO, USendTO) ->
    {SRecvTO, USendTO};
merge_timeout_values(_SRecvTO, URecvTO, _SSendTO, USendTO) ->
    {URecvTO, USendTO}.
