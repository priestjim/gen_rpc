%%% -*-mode:erlang;coding:utf-8;tab-width:4;c-basic-offset:4;indent-tabs-mode:()-*-
%%% ex: set ft=erlang fenc=utf-8 sts=4 ts=4 sw=4 et:
%%%
%%% Copyright 2015 Panagiotis Papadomitsos. All Rights Reserved.
%%%
%%% Mock module that transparently responds to ExRPC requests from an Elixir node

-module('Elixir.ExRPC.Supervisor.Server').
-author("Panagiotis Papadomitsos <pj@ezgr.net>").

%%% RPC functions
-export([start_child/1]).

%%% ===================================================
%%% RPC functiona
%%% ===================================================

start_child(Node) when is_atom(Node) ->
    gen_rpc_server_sup:start_child(Node).
