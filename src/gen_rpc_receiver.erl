%%% -*-mode:erlang;coding:utf-8;tab-width:4;c-basic-offset:4;indent-tabs-mode:()-*-
%%% ex: set ft=erlang fenc=utf-8 sts=4 ts=4 sw=4 et:
%%%
%%% Copyright 2015 Panagiotis Papadomitsos, Inc. All Rights Reserved.
%%%
%%% Original concept inspired and some code copied from
%%% https://erlangcentral.org/wiki/index.php?title=Building_a_Non-blocking_TCP_server_using_OTP_principles

-module(gen_rpc_receiver).
-author("Panagiotis Papadomitsos <pj@ezgr.net>").

%%% Behaviour
-behaviour(gen_server).

%%% Local state
-record(state, {supervisor :: pid(),
                node :: atom(),
                listener :: port(),
                acceptor :: port()}).

%%% Default TCP options
-define(DEFAULT_TCP_OPTS, [binary, {packet, 4}, {reuseaddr, true},
        {keepalive, true}, {backlog, 1024}, {active, false}]).

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
start_link(Node) when is_atom(Node), Node =/= node() ->
    gen_server:start_link(?MODULE, {Node}, []).

stop(Pid) ->
    gen_server:call(Pid, stop).

%%% ===================================================
%%% Server functions
%%% ===================================================
get_port(Pid) when is_pid(Pid) ->
    gen_server:call(Pid, get_port).

%%% ===================================================
%%% Behaviour callbacks
%%% ===================================================
init({Node}) ->
    process_flag(trap_exit, true),
    {ok, SupPid} = gen_rpc_acceptor_sup:start_link(),
    case gen_tcp:listen(0, ?DEFAULT_TCP_OPTS) of
        {ok, Socket} ->
            {ok, Ref} = prim_inet:async_accept(Socket, -1),
            {ok, #state{supervisor = SupPid,
                        node = Node,
                        listener = Socket,
                        acceptor = Ref}};
        {error, Reason} ->
            {stop, Reason}
    end.

%% Returns the dynamic port the current TCP server listens to
handle_call(get_port, _From, #state{listener = Socket} = State) ->
    {ok, Port} = inet:port(Socket),
    {reply, {ok, Port}, State};

%% Gracefully stop
handle_call(stop, _From, State) ->
    {stop, ok, State};

%% Stop on uknown message
handle_call(Request, _From, State) ->
    {stop, {unknown_call, Request}, State}.

%% Catch-all for cast messages
handle_cast(_Msg, State) ->
    {noreply, State}.

%% Acceptor handler
handle_info({inet_async, ListSock, Ref, {ok, CliSocket}},
            #state{node=Node, listener=ListSock, acceptor=Ref} = State) ->
    try
        case set_sockopt(ListSock, CliSocket) of
            ok              -> ok;
            {error, Reason} -> exit({set_sockopt, Reason})
        end,

        %% New client connected - spawn a new process using the simple_one_for_one
        %% supervisor.
        {ok, Pid} = gen_rpc_acceptor_sup:start_child(Node),
        ok = gen_tcp:controlling_process(CliSocket, Pid),
        %% Instruct the new FSM that it owns the socket.
        gen_rpc_acceptor:set_socket(Pid, CliSocket),

        %% Signal the network driver that we are ready to accept another connection
        NewRef = case prim_inet:async_accept(ListSock, -1) of
            {ok,    _NewRef} -> _NewRef;
            {error, _NewRef} -> exit({async_accept, inet:format_error(_NewRef)})
        end,
        {noreply, State#state{acceptor=NewRef}}
    catch exit:Why ->
        error_logger:error_msg("Error in async accept: ~p.\n", [Why]),
        {stop, Why, State}
    end;

handle_info({inet_async, ListSock, Ref, Error}, #state{listener=ListSock, acceptor=Ref} = State) ->
    error_logger:error_msg("Error in socket acceptor: ~p.\n", [Error]),
    {stop, Error, State};

handle_info(_Info, State) ->
    {noreply, State}.

%% Terminate cleanly by closing the listening socket
terminate(_Reason, #state{listener=Listener}) ->
    ok = gen_tcp:close(Listener).

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%%% ===================================================
%%% Private functions
%%% ===================================================
%% Taken from prim_inet.  We are merely copying some socket options from the
%% listening socket to the new client socket.
set_sockopt(ListSock, CliSocket) ->
    true = inet_db:register_socket(CliSocket, inet_tcp),
    case prim_inet:getopts(ListSock, [active, nodelay, keepalive, delay_send, priority, tos]) of
    {ok, Opts} ->
        case prim_inet:setopts(CliSocket, Opts) of
        ok    -> ok;
        Error -> gen_tcp:close(CliSocket), Error
        end;
    Error ->
        gen_tcp:close(CliSocket), Error
    end.
