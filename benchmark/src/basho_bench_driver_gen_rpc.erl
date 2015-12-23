%%% -*-mode:erlang;coding:utf-8;tab-width:4;c-basic-offset:4;indent-tabs-mode:()-*-
%%% ex: set ft=erlang fenc=utf-8 sts=4 ts=4 sw=4 et:
%%%
%%% Copyright 2015 <Your Name>. All Rights Reserved.
%%%
%%% http://www.apache.org/licenses/LICENSE-2.0
%%%
%%% * Brief: 
%%%   Bench test gen_rpc server using one or many gen_rpc clients from multiple erlang nodes.
%%%   Each Erlang nodes can run one or more test processes.
%%% * More Info:

-module(basho_bench_driver_gen_rpc).
-author("edwardt <Your Email>").

%%% Behaviour
-behaviour(basho_bench_driver_behaviour).
-export([new/1,
         run/4]).

-include("basho_bench.hrl").
-include("basho_bench_driver_gen_rpc.hrl").

%%% Test State
-record(state, { target, %% Id of current test client
                 port, %% connection port
                 workerId, %% Id of test worker same as test Id
                 replies %% Number of Successful Rpc call
               }).

%%% ===================================================
%%% Library interface
%%% ===================================================
new(Id) ->
    ?DEBUG("module=\"~p\" function=new event=test_target_started", [?MODULE]),
    {ok, {?APP, loaded}} = basho_bench_driver_gen_rpc_helper:ensure_deps_present(?APP),
    {ok, _Ign} = application:ensure_all_started(?APP),
    {ok, all_process_alive} = basho_bench_driver_gen_rpc_helper:ensure_core_process_alive(),
    {ok, {Targets, connected}} = basho_bench_driver_gen_rpc_helper:ensure_target_nodes(),
    Port = basho_bench_config:get('gen_rpc_port', undefined),
    Target = basho_bench_driver_gen_rpc_helper:choose_test_target(Targets, Port, Id),
    ?DEBUG("module=\"~p\" function=new event=test_target_started target_nide=\"~p\"", [?MODULE, Target]),
    {ok, #state{target=Target, port=Port, workerId=Id, replies=0}}.

run(call, _KeyGen, _ValueGen, State) ->
    TargetNode = State#state.target,
    ?DEBUG("Testing [call] target_node=\"~p\"", [TargetNode]),
    {ok, all_process_alive} = basho_bench_driver_gen_rpc_helper:ensure_core_process_alive(),
    case gen_rpc:call(TargetNode , erlang, node) of
        {'error', Reason} -> {error, Reason, State}; 
        {'EXIT', Reason} -> {error, Reason, State};
        {'badrpc', Reason} -> {error, Reason, State};
        {'badtcp', Reason} -> {error, Reason, State};
        _Ign -> Replies = State#state.replies,
                {ok, State#state{replies=Replies+1}}
    end;

run(call_lamda, _KeyGen, _ValueGen, State) ->
    TargetNode = State#state.target,
    ?DEBUG("Testing [call_anonymous] target_node=\"~p\"", [TargetNode]),
    {ok, all_process_alive} = basho_bench_driver_gen_rpc_helper:ensure_core_process_alive(),
    case gen_rpc:call(TargetNode , erlang, apply, [fun() -> os:timestamp() end], []) of
        {'error', Reason} -> {error, Reason, State}; 
        {'EXIT', Reason} -> {error, Reason, State};
        {'badrpc', Reason} -> {error, Reason, State};
        {'badtcp', Reason} -> {error, Reason, State};
        _Ign -> Replies = State#state.replies,
                {ok, State#state{replies=Replies+1}}
    end;

 
run(cast, _KeyGen, _ValueGen, State) ->
    TargetNode = State#state.target,
    ?DEBUG("Testing [cast] target_node=\"~p\"", [TargetNode]),
    {ok, all_process_alive} = basho_bench_driver_gen_rpc_helper:ensure_core_process_alive(),
    case gen_rpc:cast(TargetNode, erlang, node) of
        {'error', Reason} -> {error, Reason, State}; 
        {'EXIT', Reason} -> {error, Reason, State};
        {'badrpc', Reason} -> {error, Reason, State};
        {'badtcp', Reason} -> {error, Reason, State};
        true -> Replies = State#state.replies,
                {ok, State#state{replies=Replies+1}}
    end;

run(safe_cast, _KeyGen, _ValueGen, State) ->
    TargetNode = State#state.target,
    ?DEBUG("Testing [safe_cast] target_node=\"~p\"", [TargetNode]),
    {ok, all_process_alive} = basho_bench_driver_gen_rpc_helper:ensure_core_process_alive(),
    case gen_rpc:safe_cast(TargetNode, erlang, node) of
        {'error', Reason} -> {error, Reason, State}; 
        {'EXIT', Reason} -> {error, Reason, State};
        {'badrpc', Reason} -> {error, Reason, State};
        {'badtcp', Reason} -> {error, Reason, State};
        _Ign -> Replies = State#state.replies,
                {ok, State#state{replies=Replies+1}}
    end.
