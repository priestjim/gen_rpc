%%% -*-mode:erlang;coding:utf-8;tab-width:4;c-basic-offset:4;indent-tabs-mode:()-*-
%%% ex: set ft=erlang fenc=utf-8 sts=4 ts=4 sw=4 et:
%%%
%%% Copyright 2015 Panagiotis Papadomitsos. All Rights Reserved.
%%%
%%% Original concept inspired and some code copied from
%%% https://erlangcentral.org/wiki/index.php?title=Building_a_Non-blocking_TCP_server_using_OTP_principles

-module(gen_rpc_tcp_server).
-author("Panagiotis Papadomitsos <pj@ezgr.net>").

%%% Behaviour
-behaviour(gen_server).

%%% Include this library's name macro
-include("app.hrl").

%%% Local state
-record(state, {socket :: port(),
        acceptor :: prim_inet:insock()}).

%%% Supervisor functions
-export([start_link/0, stop/0]).

%%% Behaviour callbacks
-export([init/1, handle_call/3, handle_cast/2,
        handle_info/2, terminate/2, code_change/3]).

%%% ===================================================
%%% Supervisor functions
%%% ===================================================
-spec start_link() -> gen_sever:startlink_ret().
start_link() ->
    gen_server:start_link({local,?MODULE}, ?MODULE, {}, []).

-spec stop() -> ok.
stop() ->
    gen_server:call(?MODULE, stop).

%%% ===================================================
%%% Behaviour callbacks
%%% ===================================================
init({}) ->
    {ok, Port} = application:get_env(?APP, tcp_server_port),
    case gen_tcp:listen(Port, gen_rpc_helper:default_tcp_opts(?DEFAULT_TCP_OPTS)) of
        {ok, Socket} ->
            ok = lager:info("event=listener_started_successfully port=\"~B\"", [Port]),
            {ok, Ref} = prim_inet:async_accept(Socket, -1),
            {ok, #state{socket=Socket, acceptor=Ref}};
        {error, Reason} ->
            ok = lager:critical("event=failed_to_start_listener reason=\"~p\"", [Reason]),
            {stop, Reason}
    end.

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

handle_info({inet_async, ListSock, Ref, {ok, AccSocket}}, #state{socket=ListSock, acceptor=Ref} = State) ->
    try
        {ok, Peer} = inet:peername(AccSocket),
        ok = lager:info("event=client_connection_received client_ip=\"~s\" socket=\"~p\" action=starting_acceptor",
                          [gen_rpc_helper:peer_to_string(Peer), ListSock]),
        %% Start an acceptor process. We need to provide the acceptor
        %% process with our designated client IP and so enforcement
        %% of this attribute can be made for security reasons.
        {ok, AccPid} = gen_rpc_tcp_acceptor_sup:start_child(Peer),
        case gen_rpc_helper:set_sock_opt(ListSock, AccSocket) of
            ok -> ok;
            {error, Reason} -> exit({set_sock_opt, Reason})
        end,
        ok = gen_tcp:controlling_process(AccSocket, AccPid),
        ok = gen_rpc_acceptor:set_socket(AccPid, AccSocket),
        case prim_inet:async_accept(ListSock, -1) of
            {ok, NewRef} -> {noreply, State#state{acceptor=NewRef}, hibernate};
            {error, NewRef} -> exit({async_accept, inet:format_error(NewRef)})
        end
    catch
        exit:ExitReason ->
            ok = lager:error("message=inet_async event=unknown_error socket=\"~p\" error=\"~p\" action=stopping",
                            [ListSock, ExitReason]),
            {stop, ExitReason, State}
    end;

%% Handle async socket errors gracefully
handle_info({inet_async, Socket, _Ref, Error}, #state{socket=Socket} = State) ->
    ok = lager:error("message=inet_async event=listener_error socket=\"~p\" error=\"~p\" action=stopping",
                    [Socket, Error]),
    {stop, Error, State};

%% Catch-all for info - our protocol is strict so die!
handle_info(Msg, State) ->
    ok = lager:critical("event=uknown_message_received socket=\"~p\" message=\"~p\" action=stopping", [State#state.socket, Msg]),
    {stop, {unknown_message, Msg}, State}.

%% Terminate cleanly by closing the listening socket
terminate(_Reason, _Socket) ->
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.
