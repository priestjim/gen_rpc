%%% -*-mode:erlang;coding:utf-8;tab-width:4;c-basic-offset:4;indent-tabs-mode:()-*-
%%% ex: set ft=erlang fenc=utf-8 sts=4 ts=4 sw=4 et:
%%%
%%% Copyright 2015 Panagiotis Papadomitsos. All Rights Reserved.
%%%
%%% Original concept inspired and some code copied from
%%% https://erlangcentral.org/wiki/index.php?title=Building_a_Non-blocking_TCP_server_using_OTP_principles

-module(gen_rpc_tcp_acceptor).
-author("Panagiotis Papadomitsos <pj@ezgr.net>").

%%% Behaviour
-behaviour(gen_statem).

%%% Include this library's name macro
-include("app.hrl").

%%% Receive timeout for lingering clients
-define(RECEIVE_TIMEOUT, 5000).
%%% Reply timeout
-define(SEND_TIMEOUT, 5000).

%%% Local state
-record(state, {socket = undefined :: port() | undefined,
        peer :: {inet:ip4_address(), inet:port_number()}}).

%%% Server functions
-export([start_link/1, set_socket/2, stop/1]).

%% gen_statem callbacks
-export([init/1, handle_event/4, terminate/3, code_change/4]).

%% FSM States
-export([waiting_for_socket/3, waiting_for_data/3]).

%%% ===================================================
%%% Supervisor functions
%%% ===================================================
-spec start_link({inet:ip4_address(), inet:port_number()}) -> gen_statem:startlink_ret().
start_link(Peer) when is_tuple(Peer) ->
    Name = gen_rpc_helper:make_process_name("tcp_acceptor", Peer),
    gen_statem:start_link({local,Name}, ?MODULE, {Peer}, []).

-spec stop(pid()) -> ok.
stop(Pid) when is_pid(Pid) ->
     gen_statem:stop(Pid, normal, infinity).

%%% ===================================================
%%% Server functions
%%% ===================================================
-spec set_socket(pid(), gen_tcp:socket()) -> ok.
set_socket(Pid, Socket) when is_pid(Pid), is_port(Socket) ->
    gen_statem:call(Pid, {socket_ready, Socket}).

%%% ===================================================
%%% Behaviour callbacks
%%% ===================================================
init({Peer}) ->
    _OldVal = erlang:process_flag(trap_exit, true),
    ok = lager:debug("event=start peer=\"~s\"", [gen_rpc_helper:peer_to_string(Peer)]),
    %% Store the client's IP in our state
    {state_functions, waiting_for_socket, #state{peer=Peer}}.

waiting_for_socket({call, From}, {socket_ready, Socket}, #state{peer=Peer} = State) ->
    % Now we own the socket
    ok = lager:debug("event=acquiring_socket_ownership socket=\"~p\" peer=\"~s\"", [Socket, gen_rpc_helper:peer_to_string(Peer)]),
    ok = inet:setopts(Socket, [{send_timeout, ?SEND_TIMEOUT}|?ACCEPTOR_DEFAULT_TCP_OPTS]),
    ok = gen_statem:reply(From, ok),
    {next_state, waiting_for_data, State#state{socket=Socket}}.

%% Notification event coming from client
waiting_for_data(info, {tcp, Socket, Data}, #state{socket=Socket,peer=Peer} = State) when Socket =/= undefined ->
    Cookie = erlang:get_cookie(),
    try erlang:binary_to_term(Data) of
        {start_gen_rpc_server, ClientCookie} when ClientCookie =:= Cookie ->
            {ok, Pid} = gen_rpc_server_sup:start_child(Peer),
            {ok, Port} = gen_rpc_server:get_port(Pid),
            Packet = erlang:term_to_binary({gen_rpc_server_started, Port}),
            Result = case gen_tcp:send(Socket, Packet) of
                {error, Reason} ->
                    ok = lager:error("event=transmission_failed socket=\"~p\" peer=\"~s\" reason=\"~p\"",
                                     [Socket, gen_rpc_helper:peer_to_string(Peer), Reason]),
                    {stop, {badtcp,Reason}, State};
                ok ->
                    ok = lager:debug("event=transmission_succeeded socket=\"~p\" peer=\"~s\"",
                                     [Socket, gen_rpc_helper:peer_to_string(Peer)]),
                    {stop, normal, State}
            end,
            Result;
        {start_gen_rpc_server, _IncorrectClientCookie} ->
            ok = lager:error("event=invalid_cookie_received socket=\"~p\" peer=\"~s\"",
                             [Socket, gen_rpc_helper:peer_to_string(Peer)]),
            Packet = erlang:term_to_binary({connection_rejected, invalid_cookie}),
            ok = case gen_tcp:send(Socket, Packet) of
                {error, Reason} ->
                    ok = lager:error("event=transmission_failed socket=\"~p\" peer=\"~s\" reason=\"~p\"",
                                     [Socket, gen_rpc_helper:peer_to_string(Peer), Reason]);
                ok ->
                    ok = lager:debug("event=transmission_succeeded socket=\"~p\" peer=\"~s\"",
                                     [Socket, gen_rpc_helper:peer_to_string(Peer)])
            end,
            {stop, {badrpc,invalid_cookie}, State};
        OtherData ->
            ok = lager:debug("event=erroneous_data_received socket=\"~p\" peer=\"~s\" data=\"~p\"",
                             [Socket, gen_rpc_helper:peer_to_string(Peer), OtherData]),
            {stop, {badrpc, erroneous_data}, State}
    catch
        error:badarg ->
            {stop, {badtcp, corrupt_data}, State}
    end;

%% Handle the inactivity timeout gracefully
waiting_for_data(timeout, _Undefined, State) ->
    ok = lager:info("message=timeout event=receive_timeout socket=\"~p\" action=stopping", [State#state.socket]),
    {stop, normal, State}.

handle_event(info, {tcp_closed, Socket}, _StateName, #state{socket=Socket, peer=Peer} = State) ->
    ok = lager:info("message=tcp_closed event=tcp_socket_closed socket=\"~p\" peer=\"~s\" action=stopping",
                      [Socket, gen_rpc_helper:peer_to_string(Peer)]),
    {stop, normal, State};

handle_event(info, {tcp_error, Socket, Reason}, _StateName, #state{socket=Socket,peer=Peer} = State) ->
    ok = lager:notice("message=tcp_error event=tcp_socket_error socket=\"~p\" peer=\"~s\" reason=\"~p\" action=stopping",
                      [Socket, gen_rpc_helper:peer_to_string(Peer), Reason]),
    {stop, normal, State};

handle_event(EventType, Event, StateName, State) ->
    ok = lager:critical("socket=\"~p\" event=uknown_event event_type=\"~p\" payload=\"~p\" action=stopping",
                        [State#state.socket, EventType, Event]),
    {stop, {StateName, undefined_event, Event}, State}.

code_change(_OldVsn, StateName, State, _Extra) ->
    {state_functions, StateName, State}.

terminate(_Reason, _StateName, _State) ->
    ok.
