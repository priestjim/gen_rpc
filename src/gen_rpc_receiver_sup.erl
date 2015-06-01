%%% -*-mode:erlang;coding:utf-8;tab-width:4;c-basic-offset:4;indent-tabs-mode:()-*-
%%% ex: set ft=erlang fenc=utf-8 sts=4 ts=4 sw=4 et:
%%%
%%% Copyright 2015 Panagiotis Papadomitsos, Inc. All Rights Reserved.
%%%

-module(gen_rpc_receiver_sup).
-author("Panagiotis Papadomitsos <pj@ezgr.net>").

%%% Behaviour
-behaviour(supervisor).

%%% Used for debug printing messages when in test
-include("include/debug.hrl").

%%% Supervisor functions
-export([start_link/0, start_child/1]).

%%% Supervisor callbacks
-export([init/1]).

%%% ===================================================
%%% Supervisor functions
%%% ===================================================
start_link() ->
    supervisor:start_link({local, ?MODULE}, ?MODULE, []).

%% Launch a local receiver and return the port
start_child(Node) ->
    {ok, Pid} = supervisor:start_child(?MODULE, [Node]),
    {ok, Port} = gen_rpc_receiver:get_port(Pid),
    {ok, Port}.

%%% ===================================================
%%% Supervisor callbacks
%%% ===================================================
init([]) ->
    {ok, {{simple_one_for_one, 100, 1}, [
        {gen_rpc_receiver, {gen_rpc_receiver,start_link,[]}, transient, 5000, worker, [gen_rpc_receiver]}
    ]}}.
