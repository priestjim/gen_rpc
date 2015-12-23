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
-include("app.hrl").

%%% Local state
-record(state, {socket = undefined :: port() | undefined,
        send_timeout :: non_neg_integer(),
        inactivity_timeout :: non_neg_integer() | infinity,
        client_ip :: tuple(),
        client_node :: atom()}).

%%% Default TCP options
-define(ACCEPTOR_DEFAULT_TCP_OPTS, [binary, {packet,4},
        {active,once}]). % Retrieve data from socket upon request

%%% Server functions
-export([start_link/2, set_socket/2, stop/1]).

%% gen_fsm callbacks
-export([init/1, handle_event/3, handle_sync_event/4,
        handle_info/3, terminate/3, code_change/4]).

%% FSM States
-export([waiting_for_socket/2, waiting_for_data/2]).

%%% Process exports
-export([call_worker/6]).

%%% ===================================================
%%% Supervisor functions
%%% ===================================================
start_link(ClientIp, Node) when is_tuple(ClientIp), is_atom(Node) ->
    Name = gen_rpc_helper:make_process_name(acceptor, Node),
    gen_fsm:start_link({local,Name}, ?MODULE, {ClientIp, Node}, [{spawn_opt, [{priority, high}]}]).

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
    _OldVal = process_flag(trap_exit, true),
    ok = net_kernel:monitor_nodes(true, [nodedown_reason]),
    ok = lager:info("function=init client_node=\"~s\" client_ip=\"~p\"", [Node, ClientIp]),
    {ok, SendTO} = application:get_env(?APP, send_timeout),
    {ok, TTL} = application:get_env(?APP, server_inactivity_timeout),
    %% Store the client's IP and the node in our state
    {ok, waiting_for_socket, #state{client_ip=ClientIp,client_node=Node,send_timeout=SendTO,inactivity_timeout=TTL}}.

waiting_for_socket({socket_ready, Socket}, #state{client_ip=ClientIp} = State) ->
    %% Filter the ports we're willing to accept connections from
    {ok, {Ip, _Port}} = inet:peername(Socket),
    if
        ClientIp =/= Ip ->
            ok = lager:notice("function=waiting_for_socket event=rejecting_unauthorized_connection socket=\"~p\" client_ip=\"~p\" connected_ip=\"~p\"",
                              [Socket, ClientIp, Ip]),
            {stop, {badtcp,invalid_client_ip}, State};
        true ->
            % Now we own the socket
            ok = lager:debug("function=waiting_for_socket event=acquiring_socket_ownership socket=\"~p\" client_ip=\"~p\" connected_ip=\"~p\"",
                             [Socket, ClientIp, Ip]),
            ok = inet:setopts(Socket, [{send_timeout, State#state.send_timeout}|gen_rpc_helper:default_tcp_opts(?ACCEPTOR_DEFAULT_TCP_OPTS)]),
            {next_state, waiting_for_data, State#state{socket=Socket}}
    end.

%% Notification event coming from client
waiting_for_data({data, Data}, #state{socket=Socket,client_node=Node} = State) ->
    %% The meat of the whole project: process a function call and return
    %% the data
    try erlang:binary_to_term(Data) of
        {Node, ClientPid, Ref, {call, M, F, A}} ->
            WorkerPid = erlang:spawn(?MODULE, call_worker, [self(), ClientPid, Ref, M, F, A]),
            ok = lager:debug("function=waiting_for_data event=call_received socket=\"~p\" node=\"~s\" call_reference=\"~p\" client_pid=\"~p\" worker_pid=\"~p\"",
                             [Socket, Node, Ref, ClientPid, WorkerPid]),
            ok = inet:setopts(Socket, [{active, once}]),
            {next_state, waiting_for_data, State, State#state.inactivity_timeout};
        {Node, {cast, M, F, A}} ->
            ok = lager:debug("function=waiting_for_data event=cast_received socket=\"~p\" node=\"~s\" module=~s function=~s args=\"~p\"",
                             [Socket, Node, M, F, A]),
            _Pid = erlang:spawn(M, F, A),
            ok = inet:setopts(Socket, [{active, once}]),
            {next_state, waiting_for_data, State, State#state.inactivity_timeout};
        OtherData ->
            ok = lager:debug("function=waiting_for_data event=erroneous_data_received socket=\"~p\" node=\"~s\" data=\"~p\"",
                             [Socket, Node, OtherData]),
            {stop, {badrpc, erroneous_data}, State}
    catch
        error:badarg ->
            {stop, {badtcp, corrupt_data}, State}
    end;
%% Handle the inactivity timeout gracefully
waiting_for_data(timeout, State) ->
    ok = lager:info("function=handle_info message=timeout event=server_inactivity_timeout socket=\"~p\" action=stopping", [State#state.socket]),
    _Pid = erlang:spawn(gen_rpc_acceptor_sup, stop_child, [self()]),
    {stop, normal, State}.

handle_event(Event, StateName, State) ->
    ok = lager:critical("function=handle_event socket=\"~p\" event=uknown_event payload=\"~p\" action=stopping", [State#state.socket, Event]),
    {stop, {StateName, undefined_event, Event}, State}.

%% Gracefully terminate
handle_sync_event(stop, _From, _StateName, State) ->
    ok = lager:debug("function=handle_sync_event message=stop event=stopping_acceptor socket=\"~p\"", [State#state.socket]),
    {stop, normal, ok, State};

handle_sync_event(Event, _From, StateName, State) ->
    ok = lager:critical("function=handle_sync_event event=uknown_event socket=\"~p\" payload=\"~p\" action=stopping", [State#state.socket, Event]),
    {stop, {StateName, undefined_event, Event}, State}.

%% Incoming data handlers
handle_info({tcp, Socket, Data}, waiting_for_data, #state{socket=Socket} = State) when Socket =/= undefined ->
    waiting_for_data({data, Data}, State);

%% Handle a call worker message
handle_info({call_reply, PacketBin}, waiting_for_data, #state{socket=Socket} = State) when Socket =/= undefined ->
    ok = lager:debug("function=handle_info message=call_reply event=call_reply_received socket=\"~p\"", [Socket]),
    case gen_tcp:send(Socket, PacketBin) of
        ok ->
            ok = lager:debug("function=handle_info message=call_reply event=call_reply_sent socket=\"~p\"", [Socket]),
            {next_state, waiting_for_data, State, State#state.inactivity_timeout};
        {error, Reason} ->
            ok = lager:error("function=handle_info message=call_reply event=failed_to_send_call_reply socket=\"~p\" reason=\"~p\"", [Socket, Reason]),
            {stop, {badtcp, Reason}, State}
    end;

handle_info({tcp_closed, Socket}, _StateName, #state{socket=Socket,client_node=Node} = State) ->
    ok = lager:notice("function=handle_info message=tcp_closed event=tcp_socket_closed socket=\"~p\" client_node=\"~s\" action=stopping",
                      [Socket, Node]),
    {stop, normal, State};

handle_info({tcp_error, Socket, Reason}, _StateName, #state{socket=Socket,client_node=Node} = State) ->
    ok = lager:notice("function=handle_info message=tcp_error event=tcp_socket_error socket=\"~p\" client_node=\"~s\" reason=\"~p\" action=stopping",
                      [Socket, Node, Reason]),
    {stop, normal, State};

%% Handle VM node down information
handle_info({nodedown, Node, [{nodedown_reason,Reason}]}, _StateName, #state{socket=Socket,client_node=Node} = State) ->
    ok = lager:warning("function=handle_info message=nodedown event=node_down socket=\"~p\" node=~s reason=\"~p\" action=stopping", [Socket, Node, Reason]),
    {stop, normal, State};

%% Stub for other node information
handle_info({NodeEvent, _Node, _InfoList}, StateName, State) when NodeEvent =:= nodeup; NodeEvent =:= nodedown ->
    {next_state, StateName, State, State#state.inactivity_timeout};

%% Catch-all for info - our protocol is strict so die!
handle_info(Msg, StateName, State) ->
    ok = lager:critical("function=handle_info socket=\"~p\" event=uknown_event action=stopping", [State#state.socket]),
    {stop, {StateName, unknown_message, Msg}, State}.

code_change(_OldVsn, StateName, State, _Extra) ->
    {ok, StateName, State}.

%% Terminate normally if we haven't received the socket yet
terminate(_Reason, _StateName, #state{socket=undefined}) ->
    _Pid = erlang:spawn(gen_rpc_acceptor_sup, stop_child, [self()]),
    ok;
%% Terminate by closing the socket
terminate(_Reason, _StateName, #state{socket=Socket}) ->
    ok = lager:debug("function=terminate socket=\"~p\"", [Socket]),
    _Pid = erlang:spawn(gen_rpc_acceptor_sup, stop_child, [self()]),
    ok.

%%% ===================================================
%%% Private functions
%%% ===================================================

%% Process an RPC call request outside of the FSM
call_worker(Parent, WorkerPid, Ref, M, F, A) ->
    ok = lager:debug("function=call_worker event=call_received call_reference=\"~p\" module=~s function=~s args=\"~p\"", [Ref, M, F, A]),
    % If called MFA return exception, not of type term().
    % This fails term_to_binary coversion, crashes process
    % and manifest as timeout. Wrap inside anonymous function with catch
    % will crash the worker quickly not manifest as a timeout.
    % See call_MFA_undef test.
    Ret = try erlang:apply(M, F, A)
          catch
               throw:Term -> Term;
               exit:Reason -> {badrpc, {'EXIT', Reason}};
               error:Reason -> {badrpc, {'EXIT', {Reason, erlang:get_stacktrace()}}}
          end,
    PacketBin = erlang:term_to_binary({WorkerPid, Ref, Ret}),
    Parent ! {call_reply, PacketBin},
    ok.
