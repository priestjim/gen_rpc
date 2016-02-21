%%% -*-mode:erlang;coding:utf-8;tab-width:4;c-basic-offset:4;indent-tabs-mode:()-*-
%%% ex: set ft=erlang fenc=utf-8 sts=4 ts=4 sw=4 et:
%%%
%%% Copyright 2015 Panagiotis Papadomitsos. All Rights Reserved.
%%%

-module(multi_rpc_functional_SUITE).
-author("Panagiotis Papadomitsos <pj@ezgr.net>").

%%% CT Macros
-include_lib("test/include/ct.hrl").

%%% No need to export anything, everything is automatically exported
%%% as part of the test profile

%%% ===================================================
%%% CT callback functions
%%% ===================================================
all() ->
    gen_rpc_test_helper:get_test_functions(?MODULE).

init_per_suite(Config) ->
    %% Starting Distributed Erlang on local node
    {ok, _Pid} = gen_rpc_test_helper:start_distribution(?NODE),
    %% Setup application logging
    ok = gen_rpc_test_helper:set_application_environment(),
    %% Starting the application locally
    {ok, _MasterApps} = application:ensure_all_started(?APP),
    ok = ct:pal("Started [multi_rpc_functional] suite with master node [~s]", [node()]),
    Config.

end_per_suite(_Config) ->
    ok.

init_per_testcase(_OtherTest, Config) ->
    ok = gen_rpc_test_helper:start_slave(?SLAVE1),
    ok = gen_rpc_test_helper:start_slave(?SLAVE2),
    Config.

end_per_testcase(_OtherTest, Config) ->
    ok = gen_rpc_test_helper:stop_slave(?SLAVE1),
    ok = gen_rpc_test_helper:stop_slave(?SLAVE2),
    Config.

%%% ===================================================
%%% Test cases
%%% ===================================================
%% Test main functions
eval_everywhere_mfa_no_node(_Config) ->
    ok = ct:pal("Testing [eval_everywhere_mfa_no_node]"),
    ConnectedNodes = [],
    abcast = gen_rpc:eval_everywhere(ConnectedNodes, erlang, whereis, [node()]),
    % Nothing catastrophically on sender side after sending call to the ether.
    true = erlang:is_process_alive(whereis(gen_rpc_server_sup)),
    true = erlang:is_process_alive(whereis(gen_rpc_acceptor_sup)),
    true = erlang:is_process_alive(whereis(gen_rpc_client_sup)).

%% Eval_everywhere is fire and forget, which means some test cases need to show
%% something has been executed on target nodes. 
%% The main technique used in eval_everywhere testing is to setup servers- slaves,
%% and have the test script to ping the slaves with tagged messages and then wait for 
%% such and match the tags to verify originality.

%% Ping the target node with tagged msg. Target Node reply back with
%% tagged msg and its own identity.
 
eval_everywhere_mfa_one_node(_Config) ->
    ok = ct:pal("Testing [eval_everywhere_mfa_one_node]"),
    ConnectedNodes = [?SLAVE1],
    Msg = Name = 'evalmfa1',
    TestPid = self(),
    ok = terminate_process(Name),
    Pid = spawn_listener(?SLAVE1, Name, TestPid),
    true = register(Name, Pid),
    ok = ct:pal("Testing [eval_everywhere_mfa_one_node] registered listening node"),
    abcast = gen_rpc:eval_everywhere(ConnectedNodes, 'gen_rpc_test_helper', ping, [{?NODE, Name, Msg}]),
    {ok, passed} = wait_for_reply(?SLAVE1),
    ok.

eval_everywhere_mfa_multiple_nodes(_Config) ->
    ok = ct:pal("Testing [eval_everywhere_mfa_multiple_nodes]"),
    ConnectedNodes = [?SLAVE1, ?SLAVE2],
    Msg = Name = 'evalmfamulti',
    TestPid = self(),
    ok = terminate_process(Name),
    Pid = spawn_listener2(?SLAVE1, ?SLAVE2, Name, TestPid, 2),
    true = register(Name, Pid),
    abcast = gen_rpc:eval_everywhere(ConnectedNodes, 'gen_rpc_test_helper', ping, [{?NODE, Name, Msg}]),
    {ok, passed} = wait_for_reply(?SLAVE1, ?SLAVE2),
    ok.

eval_everywhere_mfa_multiple_nodes_timeout(_Config) ->
    ok = ct:pal("Testing [eval_everywhere_mfa_multiple_nodes_timeout]"),
    ConnectedNodes = [?SLAVE1, ?SLAVE2],
    Msg = Name = 'evalmfamultito',
    TestPid = self(),
    ok = terminate_process(Name),
    Pid = spawn_listener2(?SLAVE1, ?SLAVE2, Name, TestPid, 2),
    true = register(Name, Pid),
    abcast = gen_rpc:eval_everywhere(ConnectedNodes, 'gen_rpc_test_helper', ping, [{?NODE, Name, Msg}], 10),
    {ok, passed} = wait_for_reply(?SLAVE1, ?SLAVE2),
    ok.

eval_everywhere_mfa_exit_multiple_nodes(_Config) ->
    ok = ct:pal("Testing [eval_everywhere_mfa_exit_multiple_nodes]"),
    ConnectedNodes = [?SLAVE1, ?SLAVE2],
    abcast = gen_rpc:eval_everywhere(ConnectedNodes, erlang, exit, [fatal]),
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
    TestPid = self(),
    ok = terminate_process(Name),
    Pid = spawn_listener(?SLAVE1, Name, TestPid),
    true = register(Name, Pid),
    ok = ct:pal("Testing [safe_eval_everywhere_mfa_one_node] Registered Listening Node"),
    [true, []] = gen_rpc:safe_eval_everywhere(ConnectedNodes, 'gen_rpc_test_helper', ping, [{?NODE, Name, Msg}]),
    {ok, passed} = wait_for_reply(?SLAVE1),
    ok.

safe_eval_everywhere_mfa_multiple_nodes(_Config) ->
    ok = ct:pal("Testing [safe_eval_everywhere_mfa_multiple_nodes]"),
    ConnectedNodes = [?SLAVE1, ?SLAVE2, ?FAKE_NODE],
    Msg = Name = 'safeevalmfamulti',
    TestPid = self(),
    ok = terminate_process(Name),
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
    ok = terminate_process(Name),
    Pid = spawn_listener2(?SLAVE1, ?SLAVE2, Name, TestPid, 2),
    true = register(Name, Pid),
    [true,[]] = gen_rpc:safe_eval_everywhere(ConnectedNodes, 'gen_rpc_test_helper', ping, [{?NODE, Name, Msg}], 10),
    {ok, passed} = wait_for_reply(?SLAVE1, ?SLAVE2),
    ok.

safe_eval_everywhere_mfa_exit_multiple_nodes(_Config) ->
    ok = ct:pal("Testing [safe_eval_everywhere_mfa_exit_multiple_nodes]"),
    ConnectedNodes = [?SLAVE1, ?SLAVE2],
    [true, []] = gen_rpc:safe_eval_everywhere(ConnectedNodes, erlang, exit, [fatal]),
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
%% This is the middleman process listening for messages from slave nodes
%% Then relay back to test case Pid for check.
spawn_listener(Node, Name, TestPid)->
    spawn(fun() -> loop1(Node, Name, TestPid) end).


spawn_listener2(Node1, Node2, Name, TestPid, Count)->
    spawn(fun() -> loop2(Node1, Node2, Name, TestPid, Count) end).

loop1(Node, Name, TestPid) ->
    receive
        done ->
            {ok, done};
        {pong, {Node, _, Name}} ->
            ok = ct:pal("Receive pong from node=\"~s\" process=\"~p\"",[Node, Name]),
            TestPid ! {ok, Node, passed};
        Else ->
            ok = ct:pal("Unknown Message: \"~p\"", [Else]),
            TestPid ! Else
    after
        10000 ->
            ok = ct:pal("pong timeout", []),
            {error, pong_timeout}
    end.

loop2(_, _, _, _, Count) when Count =< 0 ->
    ok;

loop2(Node1, Node2, Name, TestPid, Count) ->
    receive
        done ->
            {ok, done};
        {pong, {Node1, _, Name}} ->
            ok = ct:pal("Receive pong from node=\"~p\" process=\"~p\"",[Node1, Name]),
            TestPid ! {ok, Node1, passed},
            loop2(Node1, Node2, Name, TestPid, Count-1);
        {pong, {Node2, _, Name}} ->
            ok = ct:pal("Receive pong from node=\"~p\" process=\"~p\"",[Node2, Name]),
            TestPid ! {ok, Node2, passed},
            loop2(Node1, Node2, Name, TestPid, Count-1);
        Else ->
            ok = ct:pal("Unknown Message: \"~p\"", [Else]),
            TestPid ! Else,
            loop2(Node1, Node2, Name, TestPid, Count)
    after
        10000 ->
            ok = ct:pal("pong timeout", []),
            {error, pong_timeout}
    end.

wait_for_reply(Node)->
    wait_for_reply(Node, 0).

wait_for_reply(_Node1, 1) ->
    {ok,passed};

wait_for_reply(Node, Acc) when is_atom(Node), is_integer(Acc) ->
    {ok, passed} = receive
        {ok, Node, passed} ->
            ok = ct:pal("function=wait_for_reply event_found_from=\"~p\"", [Node]),
            wait_for_reply(Node, Acc+1);
        Else ->
            ok = ct:pal("function=wait_for_reply event_unknown_msg=\"~p\"", [Else]),
             wait_for_reply(Node, Acc)
    after
         10000 ->
            receive
                M ->
                    {error, {msg_too_late, M}}
            end
    end;

wait_for_reply(Node1, Node2) ->
    wait_for_reply(Node1, Node2, 0).

wait_for_reply(_Node1, _Node2, 2) ->
    {ok,passed};

wait_for_reply(Node1, Node2, Acc)  when is_atom(Node1) , is_atom(Node2), is_integer(Acc) ->
    {ok,passed} = receive
        {ok, Node1, passed} ->
            ok = ct:pal("function=wait_for_reply event_found_from=\"~p\"", [Node1]),
            wait_for_reply(Node1, Node2, Acc+1);
        {ok, Node2, passed} ->
            ok = ct:pal("function=wait_for_reply event_found_from=\"~p\"", [Node2]),
            wait_for_reply(Node1, Node2, Acc+1);
        Else ->
            ok = ct:pal("function=wait_for_reply event_unkn0wn_msg=\"~p\"", [Else]),
             wait_for_reply(Node1, Node2, Acc)
    after
        10000 ->
            receive
                M ->
                    {error, {msg_too_late, M}}
            end
    end.

%% Terminate named processes
terminate_process(Name) ->
    terminate_process(Name, normal).

terminate_process(undefined, _) ->
    ok;

terminate_process(Proc, Reason) when is_atom(Proc) ->
    terminate_process(whereis(Proc), Reason);

terminate_process(Pid, Reason) when is_pid(Pid), is_atom(Reason) ->
    true = exit(Pid, Reason),
    ok.
