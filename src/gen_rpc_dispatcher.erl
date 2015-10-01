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

start_link() ->
    gen_server:start_link({local,?MODULE}, ?MODULE, [], []).

stop() ->
    gen_server:call(?MODULE, stop, infinity).

start_client(Node) when is_atom(Node) ->
    gen_server:call(?MODULE, {start_client,Node}, infinity).

%%% ===================================================
%%% Behaviour callbacks
%%% ===================================================
init([]) ->
    ok = lager:info("function=init"),
    process_flag(trap_exit, true),
    {ok, no_state}.

%% Simply launch a connection to a node through the appropriate
%% supervisor. This is a serialization interface so that
handle_call({start_client, Node}, _Caller, no_state) ->
    Reply = case whereis(Node) of
        undefined ->
            ok = lager:debug("function=handle_call message=start_client event=starting_client_server server_node=\"~s\"", [Node]),
            gen_rpc_client_sup:start_child(Node);
        Pid ->
            ok = lager:debug("function=handle_call message=start_client event=node_already_started server_node=\"~s\"", [Node]),
            {ok, Pid}
    end,
    {reply, Reply, no_state};

%% Gracefully terminate
handle_call(stop, _Caller, no_state) ->
    {stop, normal, ok, no_state};

%% Catch-all for calls - die if we get a message we don't expect
handle_call(Msg, _Caller, no_state) ->
    ok = lager:critical("function=handle_call event=uknown_call_received message=\"~p\" action=stopping", [Msg]),
    {stop, {unknown_call, Msg}, no_state}.

%% Catch-all for casts - die if we get a message we don't expect
handle_cast(Msg, no_state) ->
    ok = lager:critical("function=handle_call event=uknown_cast_received message=\"~p\" action=stopping", [Msg]),
    {stop, {unknown_cast, Msg}, no_state}.

%% Catch-all for info - our protocol is strict so die!
handle_info(Msg, no_state) ->
    ok = lager:critical("function=handle_info event=uknown_message_received message=\"~p\" action=stopping", [Msg]),
    {stop, {unknown_info, Msg}, no_state}.

code_change(_OldVersion, no_state, _Extra) ->
    {ok, no_state}.

terminate(Reason, no_state) ->
    ok = lager:debug("function=terminate reason=\"~512tp\"", [Reason]),
    ok.
