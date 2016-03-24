%%% -*-mode:erlang;coding:utf-8;tab-width:4;c-basic-offset:4;indent-tabs-mode:()-*-
%%% ex: set ft=erlang fenc=utf-8 sts=4 ts=4 sw=4 et:
%%%
%%% Copyright 2015 Panagiotis Papadomitsos. All Rights Reserved.
%%%
%%% Original concept inspired and some code copied from
%%% https://erlangcentral.org/wiki/index.php?title=Building_a_Non-blocking_TCP_server_using_OTP_principles

-module(gen_rpc_server).
-author("Panagiotis Papadomitsos <pj@ezgr.net>").

%%% Behaviour
-behaviour(gen_server).

%%% Include this library's name macro
-include("app.hrl").

%%% Local state
-record(state, {socket :: port(),
        peer :: tuple(),
        acceptor_pid :: pid(),
        acceptor :: prim_inet:insock()}).

%%% Supervisor functions
-export([start_link/1, stop/1]).

%%% Server functions
-export([get_port/1]).

%%% Behaviour callbacks
-export([init/1, handle_call/3, handle_cast/2,
        handle_info/2, terminate/2, code_change/3]).

%%% ===================================================
%%% Supervisor functions
%%% ===================================================
-spec start_link({inet:ip4_address(), inet:port_number()}) -> gen_sever:startlink_ret().
start_link(Peer) when is_tuple(Peer) ->
    Name = gen_rpc_helper:make_process_name("server", Peer),
    gen_server:start_link({local,Name}, ?MODULE, {Peer}, [{spawn_opt, [{priority, high}]}]).

-spec stop(pid()) -> ok.
stop(Pid) when is_pid(Pid) ->
    gen_server:call(Pid, stop).

%%% ===================================================
%%% Server functions
%%% ===================================================
-spec get_port(pid()) -> {ok, inet:port_number()} | {error, term()} | term(). %dialyzer complains without term().
get_port(Pid) when is_pid(Pid) ->
    gen_server:call(Pid, get_port).

%%% ===================================================
%%% Behaviour callbacks
%%% ===================================================
init({Peer}) ->
    _OldVal = erlang:process_flag(trap_exit, true),
    case gen_tcp:listen(0, gen_rpc_helper:default_tcp_opts(?DEFAULT_TCP_OPTS)) of
        {ok, Socket} ->
            ok = lager:info("event=listener_started_successfully peer=\"~s\"",
                            [gen_rpc_helper:peer_to_string(Peer)]),
            {ok, Ref} = prim_inet:async_accept(Socket, -1),
            {ok, #state{peer=Peer, socket=Socket, acceptor=Ref}};
        {error, Reason} ->
            ok = lager:critical("event=failed_to_start_listener peer=\"~s\" reason=\"~p\"",
                                [gen_rpc_helper:peer_to_string(Peer), Reason]),
            {stop, Reason}
    end.

%% Returns the dynamic port the current TCP server listens to
handle_call(get_port, _From, #state{socket=Socket} = State) ->
    {ok, Port} = inet:port(Socket),
    ok = lager:debug("message=get_port socket=\"~p\" port=~B", [Socket,Port]),
    {reply, {ok, Port}, State};

%% Gracefully stop
handle_call(stop, _From, State) ->
    ok = lager:debug("message=stop event=stopping_server socket=\"~p\"", [State#state.socket]),
    {stop, normal, ok, State};

%% Catch-all for calls - die if we get a message we don't expect
handle_call(Msg, _From, State) ->
    ok = lager:critical("event=unknown_call_received socket=\"~p\" message=\"~p\" action=stopping", [State#state.socket, Msg]),
    {stop, {unknown_call, Msg}, {unknown_call, Msg}, State}.

%% Catch-all for casts - die if we get a message we don't expect
handle_cast(Msg, State) ->
    ok = lager:critical("event=unknown_cast_received socket=\"~p\" message=\"~p\" action=stopping", [State#state.socket, Msg]),
    {stop, {unknown_cast, Msg}, State}.

handle_info({inet_async, ListSock, Ref, {ok, AccSocket}},
            #state{peer=Peer, socket=ListSock, acceptor=Ref} = State) ->
    try
        ok = lager:info("event=client_connection_received peer=\"~s\" socket=\"~p\" action=starting_acceptor",
                          [gen_rpc_helper:peer_to_string(Peer), ListSock]),
        %% Start an acceptor process. We need to provide the acceptor
        %% process with our designated node IP and name so enforcement
        %% of those attributes can be made for security reasons.
        {ok, AccPid} = gen_rpc_acceptor_sup:start_child(Peer),
        %% Link to acceptor, if they die so should we, since we are single-receiver
        %% to single-acceptor service
        case gen_rpc_helper:set_sock_opt(ListSock, AccSocket) of
            ok -> ok;
            {error, Reason} -> exit({set_sock_opt, Reason})
        end,
        ok = gen_tcp:controlling_process(AccSocket, AccPid),
        ok = gen_rpc_acceptor:set_socket(AccPid, AccSocket),
        {stop, normal, State}
    catch
        exit:ExitReason ->
            ok = lager:error("message=inet_async event=unknown_error socket=\"~p\" error=\"~p\" action=stopping",
                            [ListSock, ExitReason]),
            {stop, ExitReason, State}
    end;

%% Handle async socket errors gracefully
handle_info({inet_async, ListSock, Ref, Error}, #state{socket=ListSock,acceptor=Ref} = State) ->
    ok = lager:error("message=inet_async event=listener_error socket=\"~p\" error=\"~p\" action=stopping",
                    [ListSock, Error]),
    {stop, Error, State};

%% Catch-all for info - our protocol is strict so die!
handle_info(Msg, State) ->
    ok = lager:critical("event=uknown_message_received socket=\"~p\" message=\"~p\" action=stopping", [State#state.socket, Msg]),
    {stop, {unknown_message, Msg}, State}.

terminate(_Reason, _State) ->
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.
