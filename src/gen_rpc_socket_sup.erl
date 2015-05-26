%%% -*-mode:erlang;coding:utf-8;tab-width:4;c-basic-offset:4;indent-tabs-mode:()-*-
%%% ex: set ft=erlang fenc=utf-8 sts=4 ts=4 sw=4 et:
%%%
%%% Copyright 2015 Panagiotis Papadomitsos, Inc. All Rights Reserved.
%%%

-module(gen_rpc_socket_sup).
-author("Panagiotis Papadomitsos <pj@ezgr.net>").

%%% Behaviour
-behaviour(supervisor).

%%% Supervisor functions
-export([start_link/0, start_socket/0]).

%%% Supervisor callbacks
-export([init/1]).

%%% ===================================================
%%% Supervisor functions
%%% ===================================================
start_link() ->
    supervisor:start_link({local, ?MODULE}, ?MODULE, []).

start_socket() ->
    ok.

%%% ===================================================
%%% Behaviour callbacks
%%% ===================================================
init([]) ->
    {ok, {{simple_one_for_one,1,1}, [
        {gen_rpc_socket, {gen_rpc_socket,start_link,[]}, permanent, 5000, worker, [gen_rpc_socket]}
    ]}}.
