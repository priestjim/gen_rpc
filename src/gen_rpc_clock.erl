%%% -*-mode:erlang;coding:utf-8;tab-width:4;c-basic-offset:4;indent-tabs-mode:()-*-
%%% ex: set ft=erlang fenc=utf-8 sts=4 ts=4 sw=4 et:
%%%
%%% Copyright 2015 Panagiotis Papadomitsos, Inc. All Rights Reserved.
%%%

-module(gen_rpc_clock).
-author("Panagiotis Papadomitsos <pj@ezgr.net>").

%%% Behaviour
-behaviour(gen_server).

%%% Supervisor functions
-export([start_link/0, stop/0]).

%%% Server functions
-export([connect/1]).

%%% Behaviour callbacks
-export([init/1, handle_call/3, handle_cast/2,
        handle_info/2, terminate/2, code_change/3]).

%%% ===================================================
%%% Supervisor functions
%%% ===================================================
start_link() ->
    gen_server:start_link({local,?MODULE}, ?MODULE, {}, []).

stop() ->
    gen_server:call(?MODULE, stop).

%%% ===================================================
%%% Server functions
%%% ===================================================
connect(Node) when is_atom(Node) ->
    ok.

%%% ===================================================
%%% Behaviour callbacks
%%% ===================================================
%% TODO:
%% Implement gen_server timeout like a socket timeout
init({}) ->
    process_flag(trap_exit, true),
    {ok, no_state}.

%% Gracefully terminate
handle_call(stop, _From, no_state) ->
    {stop, normal, ok, no_state};

%% Catch-all for calls
handle_call(_Mesage, _Caller, no_state) ->
    {reply, ok, no_state}.

%% Catch-all for casts
handle_cast(_Message, no_state) ->
    {noreply, no_state}.

%% Catch-all for info
handle_info(_Message, no_state) ->
    {noreply, no_state}.

%% Stub functions
code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

terminate(_Reason, no_state) ->
    ok.
