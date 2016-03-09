%%% -*-mode:erlang;coding:utf-8;tab-width:4;c-basic-offset:4;indent-tabs-mode:()-*-
%%% ex: set ft=erlang fenc=utf-8 sts=4 ts=4 sw=4 et:
%%%
%%% Copyright 2015 Panagiotis Papadomitsos. All Rights Reserved.
%%%
%%% Dispatcher is a serialization trick to prevent starting up
%%% multiple children for one connection

-module(gen_rpc_dispatcher).

%%% Behaviour
-behaviour(gen_server).

%%% Include this library's name macro
-include("app.hrl").

%%% Supervisor functions
-export([start_link/0, stop/0]).

%%% Server functions
-export([start_client/1]).

%%% Behaviour callbacks
-export([init/1, handle_call/3, handle_cast/2,
        handle_info/2, terminate/2, code_change/3]).

%%% ===================================================
%%% Public API
%%% ===================================================
-spec start_link() -> gen_server:startlink_ret().
start_link() ->
    gen_server:start_link({local,?MODULE}, ?MODULE, [], []).

-spec stop() -> ok.
stop() ->
    gen_server:call(?MODULE, stop, infinity).

-spec start_client(node()) -> {ok, pid()} | {error, any()}.
start_client(Node) when is_atom(Node) ->
    gen_server:call(?MODULE, {start_client,Node}, infinity).

%%% ===================================================
%%% Behaviour callbacks
%%% ===================================================
init([]) ->
    ok = lager:info("event=start"),
    _OldVal = process_flag(trap_exit, true),
    {ok, undefined}.

%% Simply launch a connection to a node through the appropriate
%% supervisor. This is a serialization interface so that
handle_call({start_client, Node}, _Caller, undefined) ->
    PidName = gen_rpc_helper:make_process_name("client", Node),
    Reply = case whereis(PidName) of
        undefined ->
            ok = lager:debug("message=start_client event=starting_client_server server_node=\"~s\"", [Node]),
            gen_rpc_client_sup:start_child(Node);
        Pid ->
            ok = lager:debug("message=start_client event=node_already_started server_node=\"~s\"", [Node]),
            {ok, Pid}
    end,
    {reply, Reply, undefined};

%% Gracefully terminate
handle_call(stop, _Caller, undefined) ->
    {stop, normal, ok, undefined};

%% Catch-all for calls - die if we get a message we don't expect
handle_call(Msg, _Caller, undefined) ->
    ok = lager:critical("event=uknown_call_received message=\"~p\" action=stopping", [Msg]),
    {stop, {unknown_call, Msg}, undefined}.

%% Catch-all for casts - die if we get a message we don't expect
handle_cast(Msg, undefined) ->
    ok = lager:critical("event=uknown_cast_received message=\"~p\" action=stopping", [Msg]),
    {stop, {unknown_cast, Msg}, undefined}.

%% Catch-all for info - our protocol is strict so die!
handle_info(Msg, undefined) ->
    ok = lager:critical("event=uknown_message_received message=\"~p\" action=stopping", [Msg]),
    {stop, {unknown_info, Msg}, undefined}.

code_change(_OldVersion, undefined, _Extra) ->
    {ok, undefined}.

terminate(Reason, undefined) ->
    ok = lager:debug("reason=\"~512tp\"", [Reason]),
    ok.
