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
         eval_everywhere_mfa_no_node/1,
         eval_everywhere_mfa_one_node/1,
         eval_everywhere_mfa_multiple_nodes/1,
         eval_everywhere_mfa_multiple_nodes_timeout/1,
         eval_everywhere_mfa_exit_multiple_nodes/1,
         eval_everywhere_mfa_throw_multiple_nodes/1,
         eval_everywhere_mfa_timeout_multiple_nodes/1,
         safe_eval_everywhere_mfa_no_node/1,
         safe_eval_everywhere_mfa_one_node/1,
         safe_eval_everywhere_mfa_multiple_nodes/1,
         safe_eval_everywhere_mfa_multiple_nodes_timeout/1,
         safe_eval_everywhere_mfa_exit_multiple_nodes/1,
         safe_eval_everywhere_mfa_throw_multiple_nodes/1,
         safe_eval_everywhere_mfa_timeout_multiple_nodes/1]).

-export([start_slaves/0, stop_slaves/0]).

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

init_per_testcase(_Test, Config) ->
    ok = start_slaves(),
    Config.

end_per_testcase(_Test, Config) ->
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
eval_everywhere_mfa_no_node(_Config) ->
    ok = ct:pal("Testing [eval_everywhere_mfa_no_node]"),
    ConnectedNodes = [],
    abcast = gen_rpc:eval_everywhere(ConnectedNodes, erlang, whereis, [node()]),  
    % Nothing catastrophically on sender side after sending call to the ether.
    true = erlang:is_process_alive(whereis(gen_rpc_server_sup)),
    true = erlang:is_process_alive(whereis(gen_rpc_acceptor_sup)),
    true = erlang:is_process_alive(whereis(gen_rpc_client_sup)).

%% Ping the target node with tagged msg. Target Node reply back with 
%% tagged msg and its own identity. 
eval_everywhere_mfa_one_node(_Config) ->
    ok = ct:pal("Testing [eval_everywhere_mfa_one_node]"),
    ConnectedNodes = [?SLAVE1],
    Msg = Name = 'evalmfa1', 
    ok = clean_process(Name, 'normal'),
    TestPid = self(),
    Pid = spawn_listener(?SLAVE1, Name, TestPid, 1),
    true = register(Name, Pid),
    ok = ct:pal("Testing [eval_everywhere_mfa_one_node] Registered Listening Node"),
    abcast = gen_rpc:eval_everywhere(ConnectedNodes, 'gen_rpc_test_helper', ping, [{?NODE, Name, Msg}]),
    {ok, ?SLAVE1, passed} = wait_for_reply(?SLAVE1),
    ok.

eval_everywhere_mfa_multiple_nodes(_Config) ->
    ok = ct:pal("Testing [eval_everywhere_mfa_multiple_nodes]"),
    ConnectedNodes = [?SLAVE1, ?SLAVE2],
    Msg = Name = 'evalmfamul', 
    TestPid = self(),
    ok = clean_process(Name, 'normal'),
    Pid = spawn_listener2(?SLAVE1, ?SLAVE2, Name, TestPid, 2),
    true = register(Name, Pid),
    abcast = gen_rpc:eval_everywhere(ConnectedNodes, 'gen_rpc_test_helper', ping, [{?NODE, Name, Msg}]),
    {ok, passed} = wait_for_reply(?SLAVE1, ?SLAVE2),
    ok.

eval_everywhere_mfa_multiple_nodes_timeout(_Config) ->
    ok = ct:pal("Testing [eval_everywhere_mfa_multiple_nodes_timeout]"),
    ConnectedNodes = [?SLAVE1, ?SLAVE2],
    Msg = Name = 'evalmfamultiTO', 
    TestPid = self(),
    ok = clean_process(Name, 'normal'),
    Pid = spawn_listener2(?SLAVE1, ?SLAVE2, Name, TestPid, 2),
    true = register(Name, Pid),
    SendTO = 10,
    abcast = gen_rpc:eval_everywhere(ConnectedNodes, 'gen_rpc_test_helper', ping, [{?NODE, Name, Msg}], SendTO),
    {ok, passed} = wait_for_reply(?SLAVE1, ?SLAVE2),
    ok.

eval_everywhere_mfa_exit_multiple_nodes(_Config) ->
    ok = ct:pal("Testing [eval_everywhere_mfa_exit_multiple_nodes]"),
    ConnectedNodes = [?SLAVE1, ?SLAVE2],
    abcast = gen_rpc:eval_everywhere(ConnectedNodes, erlang, exit, ['fatal']),
    % Nothing blows up on sender side after sending call to nothing
    true = erlang:is_process_alive(whereis(gen_rpc_server_sup)),
    true = erlang:is_process_alive(whereis(gen_rpc_acceptor_sup)),
    true = erlang:is_process_alive(whereis(gen_rpc_client_sup)).

eval_everywhere_mfa_throw_multiple_nodes(_Config) ->
    ok = ct:pal("Testing [eval_everywhere_mfa_throw_multiple_nodes]"),
    ConnectedNodes = [?SLAVE1, ?SLAVE2],
    abcast = gen_rpc:eval_everywhere(ConnectedNodes, erlang, throw, ['throwXup']),
    ok = ct:pal("[erlang:throw only]. Verify the crash log from ct. You should see {{nocatch,throwXup}, ....} on the target node").

eval_everywhere_mfa_timeout_multiple_nodes(_Config) ->
    ok = ct:pal("Testing [eval_everywhere_mfa_timeout_multiple_nodes]"),
    ConnectedNodes = [?SLAVE1, ?SLAVE2],
    abcast = gen_rpc:eval_everywhere(ConnectedNodes, erlang, throw, ['throwXup']),
    ok = ct:pal("[erlang:throw only]. Verify the crash log from ct. You should see {{nocatch,throwXup}, ....} on the target node").

safe_eval_everywhere_mfa_no_node(_Config) ->
    ok = ct:pal("Testing [safe_eval_everywhere_mfa_no_node]"),
    ConnectedNodes = [],
    [] = gen_rpc:safe_eval_everywhere(ConnectedNodes, erlang, whereis, [node()]),  
    % Nothing catastrophically blows up  on sender side after sending call to the ether.
    true = erlang:is_process_alive(whereis(gen_rpc_server_sup)),
    true = erlang:is_process_alive(whereis(gen_rpc_acceptor_sup)),
    true = erlang:is_process_alive(whereis(gen_rpc_client_sup)).

safe_eval_everywhere_mfa_one_node(_Config) ->
    ok = ct:pal("Testing [safe_eval_everywhere_mfa_one_node]"),
    ConnectedNodes = [?SLAVE1],
    Msg = Name = 'safeevalmfa1', 
    ok = clean_process(Name, 'normal'),
    TestPid = self(),
    Pid = spawn_listener(?SLAVE1, Name, TestPid, 1),
    true = register(Name, Pid),
    ok = ct:pal("Testing [safe_eval_everywhere_mfa_one_node] Registered Listening Node"),
    [true, []] = gen_rpc:safe_eval_everywhere(ConnectedNodes, 'gen_rpc_test_helper', ping, [{?NODE, Name, Msg}]),
    {ok, ?SLAVE1, passed} = wait_for_reply(?SLAVE1),
    ok.

safe_eval_everywhere_mfa_multiple_nodes(_Config) ->
    ok = ct:pal("Testing [safe_eval_everywhere_mfa_multiple_nodes]"),
    ConnectedNodes = [?SLAVE1, ?SLAVE2, ?FAKE_NODE],
    Msg = Name = 'safeevalmfamulti', 
    TestPid = self(),
    ok = clean_process(Name, 'normal'),
    Pid = spawn_listener2(?SLAVE1, ?SLAVE2, Name, TestPid, 2),
    true = register(Name, Pid),
    [true, [?FAKE_NODE]] = gen_rpc:safe_eval_everywhere(ConnectedNodes, 'gen_rpc_test_helper', ping, [{?NODE, Name, Msg}]),
    {ok, passed} = wait_for_reply(?SLAVE1, ?SLAVE2),
    ok.

safe_eval_everywhere_mfa_multiple_nodes_timeout(_Config) ->
    ok = ct:pal("Testing [safe_eval_everywhere_mfa_multiple_nodes_timeout]"),
    ConnectedNodes = [?SLAVE1, ?SLAVE2],
    Msg = Name = 'safeevalmfamultiTO', 
    TestPid = self(),
    ok = clean_process(Name, 'normal'),
    Pid = spawn_listener2(?SLAVE1, ?SLAVE2, Name, TestPid, 2),
    true = register(Name, Pid),
    SendTO = 10,
    [true,[]] = gen_rpc:safe_eval_everywhere(ConnectedNodes, 'gen_rpc_test_helper', ping, [{?NODE, Name, Msg}], SendTO),
    {ok, passed} = wait_for_reply(?SLAVE1, ?SLAVE2),
    ok.

safe_eval_everywhere_mfa_exit_multiple_nodes(_Config) ->
    ok = ct:pal("Testing [safe_eval_everywhere_mfa_exit_multiple_nodes]"),
    ConnectedNodes = [?SLAVE1, ?SLAVE2],
    [true, []] = gen_rpc:safe_eval_everywhere(ConnectedNodes, erlang, exit, ['fatal']),
    % Nothing blows up on sender side after sending call to the ether
    true = erlang:is_process_alive(whereis(gen_rpc_server_sup)),
    true = erlang:is_process_alive(whereis(gen_rpc_acceptor_sup)),
    true = erlang:is_process_alive(whereis(gen_rpc_client_sup)).

safe_eval_everywhere_mfa_throw_multiple_nodes(_Config) ->
    ok = ct:pal("Testing [safe_eval_everywhere_mfa_throw_multiple_nodes]"),
    ConnectedNodes = [?SLAVE1, ?SLAVE2],
    [true, []] = gen_rpc:safe_eval_everywhere(ConnectedNodes, erlang, throw, ['throwXup']),
    ok = ct:pal("[erlang:throw only]. Verify the crash log from ct. You should see {{nocatch,throwXup}, ....} on the target node").

safe_eval_everywhere_mfa_timeout_multiple_nodes(_Config) ->
    ok = ct:pal("Testing [eval_everywhere_mfa_timeout_multiple_nodes]"),
    ConnectedNodes = [?SLAVE1, ?SLAVE2],
    [true, []] = gen_rpc:safe_eval_everywhere(ConnectedNodes, erlang, throw, ['throwXup']),
    ok = ct:pal("erlang:throw only]. Verify the crash log from ct. You should see {{nocatch,throwXup}, ....} on the target node").

%%% ===================================================
%%% Auxiliary functions for test cases
%%% ===================================================
start_slaves() ->
    ok = start_slave(?SLAVE_NAME1, ?SLAVE1),
    ok = start_slave(?SLAVE_NAME2, ?SLAVE2),
    ok = ct:pal("Slaves started"),
    ok.

start_slave(Name, Node) ->
    %% Starting a slave node with Distributed Erlang
    {ok, _Slave} = slave:start(?SLAVE_IP, Name, "+K true"),
    ok = rpc:call(Node, code, add_pathsz, [code:get_path()]),
    %% Start the application remotely
    {ok, _SlaveApps} = rpc:call(Node, application, ensure_all_started, [gen_rpc]),
    {module, gen_rpc_test_helper} = rpc:call(Node, code, ensure_loaded, [gen_rpc_test_helper]),
    ok.

stop_slaves() ->
    Slaves = [?SLAVE1, ?SLAVE2],
    [begin 
        ok = slave:stop(Node)
     end || Node <- Slaves],
    ok = ct:pal("Slaves stopped").

%% This is the middleman process listening for messages from slave nodes
%% Then relay back to test case Pid for check.
spawn_listener(_, _, _, Count) when Count =< 0-> ok;
spawn_listener(Node, Name, TestPid, Count)->
    spawn(fun() ->
                receive 
                       done -> {ok, done};
                       {pong, {Node, _, Name}} ->
                                ok = ct:pal("Receive pong from node=\"~p\" process=\"~p\"",[Node, Name]),
                                TestPid ! {ok, Node, passed},
                                spawn_listener(Node, Name, TestPid, Count-1);                                    
                        Else -> ok = ct:pal("Unknown Message: \"~p\"", [Else]),
                                TestPid ! Else
                after
                        10000 ->
                                ok = ct:pal("pong timeout", []),
                                {error, pong_timeout}
                end
          end).

wait_for_reply(Node) ->
    receive 
        {ok, Node, passed} -> {ok, Node, passed};                                                                   
        _Ign -> {error, _Ign}
    after
         5000 -> {error, timeout}
    end.

spawn_listener2(Node1, Node2, Name, TestPid, Count)->
    spawn(fun() -> loop(Node1, Node2, Name, TestPid, Count) end).

loop(_, _, _, _, Count) when Count =< 0 -> ok;
loop(Node1, Node2, Name, TestPid, Count) ->
          receive 
                done -> {ok, done};
                {pong, {Node1, _, Name}} ->
                       ok = ct:pal("Receive pong from node=\"~p\" process=\"~p\"",[Node1, Name]),
                       TestPid ! {ok, Node1, passed}, 
                       loop(Node1, Node2, Name, TestPid, Count-1);
                {pong, {Node2, _, Name}} ->
                        ok = ct:pal("Receive pong from node=\"~p\" process=\"~p\"",[Node2, Name]),
                        TestPid ! {ok, Node2, passed},
                        loop(Node1, Node2, Name, TestPid, Count-1);                                     
                Else -> ok = ct:pal("Unknown Message: \"~p\"", [Else]),
                        TestPid ! Else,
                        loop(Node1, Node2, Name, TestPid, Count)
          after
                5000 ->
                        ok = ct:pal("pong timeout", []),
                        {error, pong_timeout}
          end.

wait_for_reply(Node1, Node2) ->
    {ok, Node1, passed} = receive 
        {ok, Node1, passed} -> 
                        ok = ct:pal("function=wait_for_reply event_found_from=\"~p\"", [Node1]),
                        {ok, Node1, passed} 
    after
         5000 -> {error, timeout}
    end,

    {ok, Node2, passed} = 
    receive 
        {ok, Node2, passed} -> 
                        ok = ct:pal("function=wait_for_reply event_found_from=\"~p\"", [Node2]),
                       {ok, Node2, passed}; 
        _Ign -> {error, _Ign}
    after
         10000 -> {error, timeout}
    end,
    {ok, passed} = receive 
        Else -> {error, {unknown_msg, Else}}
    after
         0 -> {ok, passed}
    end.

clean_process(Name, Reason) ->
    Pid = whereis(Name),
    true = kill_it(Pid, Reason),
    ok.

kill_it(undefined, _Reason) -> true;
kill_it(Pid, Reason) ->
    true = exit(Pid, Reason).
