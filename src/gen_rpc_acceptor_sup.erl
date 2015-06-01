%%% -*-mode:erlang;coding:utf-8;tab-width:4;c-basic-offset:4;indent-tabs-mode:()-*-
%%% ex: set ft=erlang fenc=utf-8 sts=4 ts=4 sw=4 et:
%%%
%%% Copyright 2015 Panagiotis Papadomitsos, Inc. All Rights Reserved.
%%%

-module(gen_rpc_acceptor_sup).
-author("Panagiotis Papadomitsos <pj@ezgr.net>").

%%% Behaviour
-behaviour(supervisor).

%%% Used for debug printing messages when in test
-include("include/debug.hrl").

%%% Supervisor functions
-export([start_link/0, start_child/2]).

%%% Supervisor callbacks
-export([init/1]).

%%% ===================================================
%%% Supervisor functions
%%% ===================================================
start_link() ->
    supervisor:start_link({local, ?MODULE}, ?MODULE, []).

start_child(ClientIp, Node) when is_tuple(ClientIp), is_atom(Node) ->
    ?debug("Starting new acceptor for remote node [~s] with IP [~w]", [Node, ClientIp]),
    supervisor:start_child(?MODULE, [ClientIp,Node]).

%%% ===================================================
%%% Supervisor callbacks
%%% ===================================================
init([]) ->
    {ok, {{simple_one_for_one, 100, 1}, [
        {gen_rpc_acceptor, {gen_rpc_acceptor,start_link,[]}, permanent, 5000, worker, [gen_rpc_acceptor]}
    ]}}.
