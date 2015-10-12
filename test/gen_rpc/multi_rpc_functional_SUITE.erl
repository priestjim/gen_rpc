%%% -*-mode:erlang;coding:utf-8;tab-width:4;c-basic-offset:4;indent-tabs-mode:()-*-
%%% ex: set ft=erlang fenc=utf-8 sts=4 ts=4 sw=4 et:
%%%
%%% Copyright 2015 Panagiotis Papadomitsos. All Rights Reserved.
%%%

-module(multi_rpc_functional_SUITE).
-author("Panagiotis Papadomitsos <pj@ezgr.net>").

%%% CT Macros
-include_lib("test/gen_rpc/include/ct.hrl").

%%% Common Test callbacks
-export([all/0, init_per_suite/1, end_per_suite/1, init_per_testcase/2, end_per_testcase/2]).

%%% Testing functions
-export([supervisor_black_box/1,
        eval_everywhere_mfa/1,
        eval_everywhere_mfa_on_nodes/1,
        eval_everywhere_mfa_exit_on_nodes/1,
        eval_everywhere_mfa_throw_on_nodes/1,
        eval_everywhere_mfa_timeout_on_nodes/1,
        client_inactivity_timeout/1,
        server_inactivity_timeout/1]).

-define(TESTSRV, test_app_server).

%%% ===================================================
%%% CT callback functions
%%% ===================================================
all() ->
    {exports, Functions} = lists:keyfind(exports, 1, ?MODULE:module_info()),
    [FName || {FName, _} <- lists:filter(
                               fun ({module_info,_}) -> false;
                                   ({all,_}) -> false;
                                   ({init_per_suite,1}) -> false;
                                   ({end_per_suite,1}) -> false;

                                   ({_,1}) -> true;
                                   ({_,_}) -> false
                               end, Functions)].

init_per_suite(Config) ->
    %% Starting Distributed Erlang on local node
    {ok, _Pid} = gen_rpc_test_helper:start_target(?NODE),
    %% Setup application logging
    ?set_application_environment(),
    %% Starting the application locally
    {ok, _MasterApps} = application:ensure_all_started(?APP),
    ok = ct:pal("Started [functional] suite with master node [~s]", [node()]),
    Config.

end_per_suite(_Config) ->
    ok.

init_per_testcase(client_inactivity_timeout, Config) ->
    ok = start_slaves(),
    ok = ?restart_application(),
    ok = application:set_env(?APP, client_inactivity_timeout, infinity),
    Config;
init_per_testcase(server_inactivity_timeout, Config) ->
    ok = start_slaves(),
    ok = ?restart_application(),
    ok = application:set_env(?APP, server_inactivity_timeout, infinity),
    Config;
init_per_testcase(_OtherTest, Config) ->
    ok = start_slaves(),
    Config.

end_per_testcase(client_inactivity_timeout, Config) ->
    ok = stop_slaves(),
    ok = ?restart_application(),
    Config;
end_per_testcase(server_inactivity_timeout, Config) ->
    ok = stop_slaves(),
    ok = ?restart_application(),
    Config;

end_per_testcase(_OtherTest, Config) ->
    ok = stop_slaves(),
    Config.


%%% ===================================================
%%% Test cases
%%% ===================================================
%% Test supervisor's status
supervisor_black_box(_Config) ->
    ok = ct:pal("Testing [supervisor_black_box]"),
    true = erlang:is_process_alive(whereis(gen_rpc_server_sup)),
    true = erlang:is_process_alive(whereis(gen_rpc_acceptor_sup)),
    true = erlang:is_process_alive(whereis(gen_rpc_client_sup)),
    ok.

%% Test main functions

eval_everywhere_mfa(_Config) ->
    ok = ct:pal("Testing [eval_everywhere_mfa]"),
    ConnectedNodes = [node() | nodes()],
    {_,_,Seed} = Now = os:timestamp(),
    Data = [{'from', node()},
     {'sent_time', Now},
     {'data', crypto:random_seed(Seed)}],
    abcast = gen_rpc:eval_everywhere('test_app_server', 'set', [Data]), 
    rpc:call(ConnectedNodes, 'test_app_server', 'get', []).

eval_everywhere_mfa_on_nodes(_Config) ->
    ok = ct:pal("Testing [eval_everywhere_mfa_on_nodes]"),
    ConnectedNodes = [nodes()],
    abcast = gen_rpc:eval_everywhere(ConnectedNodes, application, set_env, [mfa, 'x']),
    rpc:call(ConnectedNodes, 'test_app_server', 'get', []).

eval_everywhere_mfa_exit_on_nodes(_Config) ->
    ok = ct:pal("Testing [eval_everywhere_mfa_exit_on_nodes]"),
    ConnectedNodes = [nodes()],
    abcast = gen_rpc:eval_everywhere(ConnectedNodes, erlang, exit, ['fatal']),
    rpc:call(ConnectedNodes, 'test_app_server', 'get', []).

eval_everywhere_mfa_throw_on_nodes(_Config) ->
    ok = ct:pal("Testing [eval_everywhere_mfa_throw_on_nodes]"),
    ConnectedNodes = [node() | nodes()],
    abcast = gen_rpc:eval_everywhere(ConnectedNodes, erlang, throw, ['throwXup']),
    rpc:call(ConnectedNodes, 'test_app_server', 'get', []).

eval_everywhere_mfa_timeout_on_nodes(_Config) ->
    ok = ct:pal("Testing [eval_everywhere_mfa_timeout_on_nodes]"),
    ConnectedNodes = [node() | nodes()],
    abcast = gen_rpc:eval_everywhere(ConnectedNodes, erlang, throw, ['throwXup']),
    rpc:call(ConnectedNodes, 'test_app_server', 'get', []).


client_inactivity_timeout(_Config) ->
    ok = ct:pal("Testing [client_inactivity_timeout]"),
    {_Mega, _Sec, _Micro} = gen_rpc:call(?SLAVE, os, timestamp),
    ok = timer:sleep(600),
    %% Lookup the client named process, shouldn't be undefined. Rewrite/Remove test?
    undefined =:= whereis(?SLAVE).

server_inactivity_timeout(_Config) ->
    ok = ct:pal("Testing [server_inactivity_timeout]"),
    {_Mega, _Sec, _Micro} = gen_rpc:call(?SLAVE, os, timestamp),
    ok = timer:sleep(600),
    %% Lookup the client named process, shouldn't be there
    [] = supervisor:which_children(gen_rpc_acceptor_sup),
    %% The server supervisor should have no children
    [] = supervisor:which_children(gen_rpc_server_sup).

%%% ===================================================
%%% Auxiliary functions for test cases
%%% ===================================================
start_slaves() ->
    Pid = start_slave(?SLAVE_NAME, ?SLAVE),
    Pid1 = start_slave(?SLAVE_NAME1, ?SLAVE1),
    ok = ct:pal("Start Slave Pid=\"~p\", Pid1=\"~p \"", [Pid, Pid1]),
    [Pid, Pid1].

start_slave(Name, Node) ->
    %% Starting a slave node with Distributed Erlang
    {ok, _Slave} = slave:start(?SLAVE_IP, Name, "+K true"),
    ok = rpc:call(Node, code, add_pathsz, [code:get_path()]),
    %% Start the application remotely
    {ok, _SlaveApps} = rpc:call(Node, application, ensure_all_started, [gen_rpc]),
    {module, ?TESTSRV} = rpc:call(Node, code, ensure_loaded, [?TESTSRV]),
    rpc:call(Name, ?TESTSRV, start_link, []).

stop_slaves() ->
    ok = slave:stop(?SLAVE_NAME),
    ok = slave:stop(?SLAVE_NAME1),
    ok = ct:pal("Slaves stopped", []).

