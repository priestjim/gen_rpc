%%% -*-mode:erlang;coding:utf-8;tab-width:4;c-basic-offset:4;indent-tabs-mode:()-*-
%%% ex: set ft=erlang fenc=utf-8 sts=4 ts=4 sw=4 et:
%%%
%%% Copyright 2015 Panagiotis Papadomitsos. All Rights Reserved.
%%%

-module(gen_rpc).
-author("Panagiotis Papadomitsos <pj@ezgr.net>").

%%% Behaviour
-behaviour(application).

%%% Used for debug printing messages when in test
-include("include/debug.hrl").

%%% Application callbacks
-export([start/2, stop/1]).

%%% Library interface
-export([call/3, call/4, call/5, call/6, cast/3, cast/4, cast/5]).

%%% ===================================================
%%% Application callbacks
%%% ===================================================
start(_StartType, _StartArgs) ->
    gen_rpc_sup:start_link().

stop(_State) ->
    ok.

%%% ===================================================
%%% Library interface
%%% ===================================================
%% All functions are GUARD-ed in the sender module, no
%% need for the overhead here
call(Node, M, F) ->
    gen_rpc_client:call(Node, M, F).

call(Node, M, F, A) ->
    gen_rpc_client:call(Node, M, F, A).

call(Node, M, F, A, RecvTO) ->
    gen_rpc_client:call(Node, M, F, A, RecvTO).

call(Node, M, F, A, RecvTO, SendTO) ->
    gen_rpc_client:call(Node, M, F, A, RecvTO, SendTO).

cast(Node, M, F) ->
    gen_rpc_client:cast(Node, M, F).

cast(Node, M, F, A) ->
    gen_rpc_client:cast(Node, M, F, A).

cast(Node, M, F, A, SendTO) ->
    gen_rpc_client:cast(Node, M, F, A, SendTO).
