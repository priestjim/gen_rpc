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
        peer :: {inet:ip4_address(), inet:port_number()}}).

%%% Server functions
-export([start_link/1, set_socket/2, stop/1]).

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
-spec start_link({inet:ip4_address(), inet:port_number()}) -> gen_fsm:startlink_ret().
start_link(Peer) when is_tuple(Peer) ->
    Name = gen_rpc_helper:make_process_name("acceptor", Peer),
    gen_fsm:start_link({local,Name}, ?MODULE, {Peer}, [{spawn_opt, [{priority, high}]}]).

-spec stop(pid()) -> ok.
stop(Pid) when is_pid(Pid) ->
     gen_fsm:sync_send_all_state_event(Pid, stop).

%%% ===================================================
%%% Server functions
%%% ===================================================
-spec set_socket(pid(), gen_tcp:socket()) -> ok.
set_socket(Pid, Socket) when is_pid(Pid), is_port(Socket) ->
    gen_fsm:send_event(Pid, {socket_ready, Socket}).

%%% ===================================================
%%% Behaviour callbacks
%%% ===================================================
init({Peer}) ->
    _OldVal = erlang:process_flag(trap_exit, true),
    ok = lager:info("event=start peer=\"~s\"", [gen_rpc_helper:peer_to_string(Peer)]),
    %% Store the client's IP and the node in our state
    {ok, waiting_for_socket, #state{peer=Peer}}.

waiting_for_socket({socket_ready, Socket}, #state{peer=Peer} = State) ->
    % Now we own the socket
    ok = lager:debug("event=acquiring_socket_ownership socket=\"~p\" peer=\"~p\"",
                     [Socket, gen_rpc_helper:peer_to_string(Peer)]),
    ok = inet:setopts(Socket, [{send_timeout, gen_rpc_helper:get_send_timeout(undefined)}|
                      gen_rpc_helper:default_tcp_opts(?ACCEPTOR_DEFAULT_TCP_OPTS)]),
    {next_state, waiting_for_data, State#state{socket=Socket}}.

%% Notification event coming from client
waiting_for_data({data, Data}, #state{socket=Socket,peer=Peer} = State) ->
    %% The meat of the whole project: process a function call and return
    %% the data
    try erlang:binary_to_term(Data) of
        {{CallType,M,F,A}, Caller} when CallType =:= call; CallType =:= async_call ->
            WorkerPid = erlang:spawn(?MODULE, call_worker, [self(), CallType, M, F, A, Caller]),
            ok = lager:debug("event=call_received socket=\"~p\" peer=\"~s\" caller=\"~p\" worker_pid=\"~p\"",
                             [Socket, gen_rpc_helper:peer_to_string(Peer), Caller, WorkerPid]),
            ok = inet:setopts(Socket, [{active, once}]),
            {next_state, waiting_for_data, State, gen_rpc_helper:get_inactivity_timeout(?MODULE)};
        {cast, M, F, A} ->
            ok = lager:debug("event=cast_received socket=\"~p\" peer=\"~s\" module=~s function=~s args=\"~p\"",
                             [Socket, Peer, M, F, A]),
            _Pid = erlang:spawn(M, F, A),
            ok = inet:setopts(Socket, [{active, once}]),
            {next_state, waiting_for_data, State, gen_rpc_helper:get_inactivity_timeout(?MODULE)};
        OtherData ->
            ok = lager:debug("event=erroneous_data_received socket=\"~p\" peer=\"~s\" data=\"~p\"",
                             [Socket, gen_rpc_helper:peer_to_string(Peer), OtherData]),
            {stop, {badrpc, erroneous_data}, State}
    catch
        error:badarg ->
            {stop, {badtcp, corrupt_data}, State}
    end;
%% Handle the inactivity timeout gracefully
waiting_for_data(timeout, State) ->
    ok = lager:info("message=timeout event=server_inactivity_timeout socket=\"~p\" action=stopping", [State#state.socket]),
    {stop, normal, State}.

handle_event(Event, StateName, State) ->
    ok = lager:critical("socket=\"~p\" event=uknown_event payload=\"~p\" action=stopping", [State#state.socket, Event]),
    {stop, {StateName, undefined_event, Event}, State}.

%% Gracefully terminate
handle_sync_event(stop, _From, _StateName, State) ->
    ok = lager:debug("message=stop event=stopping_acceptor socket=\"~p\"", [State#state.socket]),
    {stop, normal, ok, State};

handle_sync_event(Event, _From, StateName, State) ->
    ok = lager:critical("event=uknown_event socket=\"~p\" payload=\"~p\" action=stopping", [State#state.socket, Event]),
    {stop, {StateName, undefined_event, Event}, State}.

%% Incoming data handlers
handle_info({tcp, Socket, Data}, waiting_for_data, #state{socket=Socket} = State) when Socket =/= undefined ->
    waiting_for_data({data, Data}, State);

%% Handle a call worker message
handle_info({CallReply, _Caller, _Reply} = Payload, waiting_for_data, #state{socket=Socket} = State) when Socket =/= undefined, CallReply =:= call;
                                                                                                          Socket =/= undefined, CallReply =:= async_call ->
    Packet = erlang:term_to_binary(Payload),
    ok = lager:debug("message=call_reply event=call_reply_received socket=\"~p\"", [Socket]),
    case gen_tcp:send(Socket, Packet) of
        ok ->
            ok = lager:debug("message=call_reply event=call_reply_sent socket=\"~p\"", [Socket]),
            {next_state, waiting_for_data, State, gen_rpc_helper:get_inactivity_timeout(?MODULE)};
        {error, Reason} ->
            ok = lager:error("message=call_reply event=failed_to_send_call_reply socket=\"~p\" reason=\"~p\"", [Socket, Reason]),
            {stop, {badtcp, Reason}, State}
    end;

handle_info({tcp_closed, Socket}, _StateName, #state{socket=Socket,peer=Peer} = State) ->
    ok = lager:notice("message=tcp_closed event=tcp_socket_closed socket=\"~p\" peer=\"~s\" action=stopping",
                      [Socket, gen_rpc_helper:peer_to_string(Peer)]),
    {stop, normal, State};

handle_info({tcp_error, Socket, Reason}, _StateName, #state{socket=Socket,peer=Peer} = State) ->
    ok = lager:notice("message=tcp_error event=tcp_socket_error socket=\"~p\" peer=\"~s\" reason=\"~p\" action=stopping",
                      [Socket, gen_rpc_helper:peer_to_string(Peer), Reason]),
    {stop, normal, State};

%% Catch-all for info - our protocol is strict so die!
handle_info(Msg, StateName, State) ->
    ok = lager:critical("socket=\"~p\" event=uknown_event action=stopping", [State#state.socket]),
    {stop, {StateName, unknown_message, Msg}, State}.

terminate(_Reason, _StateName, _State) ->
    ok.

code_change(_OldVsn, StateName, State, _Extra) ->
    {ok, StateName, State}.

%%% ===================================================
%%% Private functions
%%% ===================================================
%% Process an RPC call request outside of the FSM
call_worker(Server, CallType, M, F, A, Caller) ->
    ok = lager:debug("event=call_received caller=\"~p\" module=~s function=~s args=\"~p\"", [Caller, M, F, A]),
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
    Server ! {CallType, Caller, Ret}.
