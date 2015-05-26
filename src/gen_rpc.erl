%%% -*-mode:erlang;coding:utf-8;tab-width:4;c-basic-offset:4;indent-tabs-mode:()-*-
%%% ex: set ft=erlang fenc=utf-8 sts=4 ts=4 sw=4 et:
%%%
%%% Copyright 2015 Panagiotis Papadomitsos, Inc. All Rights Reserved.
%%%

-module(gen_rpc).
-author("Panagiotis Papadomitsos <pj@ezgr.net>").

%%% Behaviour
-behaviour(application).

%%% Application callbacks
-export([start/2, stop/1]).

%%% ===================================================
%%% Application callbacks
%%% ===================================================
start(_StartType, _StartArgs) ->
    gen_rpc_sup:start_link().

stop(_State) ->
    ok.
