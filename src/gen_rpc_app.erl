%%% -*-mode:erlang;coding:utf-8;tab-width:4;c-basic-offset:4;indent-tabs-mode:()-*-
%%% ex: set ft=erlang fenc=utf-8 sts=4 ts=4 sw=4 et:
%%%
%%% Copyright 2015 Panagiotis Papadomitsos. All Rights Reserved.
%%%

-module(gen_rpc_app).
-author("Panagiotis Papadomitsos <pj@ezgr.net>").

%%% Behaviour
-behaviour(application).

%%% Include this library's name macro
-include("include/app.hrl").

%%% Application callbacks
-export([start/2, stop/1]).

%%% Development start/stop functions
-export([start/0, stop/0]).

%%% ===================================================
%%% Application callbacks
%%% ===================================================
start(_StartType, _StartArgs) ->
    gen_rpc_sup:start_link().

stop(_State) ->
    ok.

%%% ===================================================
%%% Application callbacks
%%% ===================================================
start() ->
    application:start(?APP).

stop() ->
    application:stop(?APP).
