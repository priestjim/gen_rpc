%%% -*-mode:erlang;coding:utf-8;tab-width:4;c-basic-offset:4;indent-tabs-mode:()-*-
%%% ex: set ft=erlang fenc=utf-8 sts=4 ts=4 sw=4 et:
%%%
%%% Copyright 2015 Panagiotis Papadomitsos. All Rights Reserved.
%%%

-module(monitor_SUITE).
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
    {ok, _Pid} = gen_rpc_test_helper:start_distribution(?MASTER),
    Config.

end_per_suite(_Config) ->
    ok.

init_per_testcase(_Test, Config) ->
    ok = gen_rpc_test_helper:restart_application(),
    ok = gen_rpc_test_helper:start_master(tcp),
    ok = gen_rpc_test_helper:start_slave(tcp),
    Config.

end_per_testcase(_Test, Config) ->
    ok = gen_rpc_test_helper:stop_slave(),
    Config.

%%% ===================================================
%%% Test cases
%%% ===================================================
monitor_node_up_down(_Config) ->
    true = gen_rpc:monitor_node(?SLAVE, true),
    %% No connection yet, no messages
    ok = expect_no_message(100),
    %% The first connection to the node generates a nodeup message
    {_Mega, _Sec, _Micro} = gen_rpc:call(?SLAVE, os, timestamp),
    ok = expect_message({nodeup, ?SLAVE}, 1000),
    %% More calls over the same connection do not
    {_Mega1, _Sec1, _Micro1} = gen_rpc:call(?SLAVE, os, timestamp),
    ok = expect_no_message(100),
    %% Killing the node generates a nodedown message
    ok = gen_rpc_test_helper:stop_slave(),
    ok = expect_message({nodedown, ?SLAVE}, 5000),
    %% And reconnecting a new nodeup one
    ok = gen_rpc_test_helper:start_slave(tcp),
    {_Mega2, _Sec2, _Micro2} = gen_rpc:call(?SLAVE, os, timestamp),
    ok = expect_message({nodeup, ?SLAVE}, 1000).

monitor_node_unsubscribe(_Config) ->
    true = gen_rpc:monitor_node(?SLAVE, true),
    true = gen_rpc:monitor_node(?SLAVE, false),
    {_Mega, _Sec, _Micro} = gen_rpc:call(?SLAVE, os, timestamp),
    ok = gen_rpc_test_helper:stop_slave(),
    ok = expect_no_message(1000).

monitor_node_multiple_subscribers(_Config) ->
    Parent = self(),
    Subscribers = [spawn_link(fun() ->
        true = gen_rpc:monitor_node(?SLAVE, true),
        Parent ! {ready, self()},
        receive
            {nodedown, ?SLAVE} -> Parent ! {got_nodedown, self()}
        after 5000 ->
            Parent ! {timeout, self()}
        end
    end) || _ <- lists:seq(1, 3)],
    ok = lists:foreach(fun(Pid) -> ok = expect_message({ready, Pid}, 1000) end, Subscribers),
    {_Mega, _Sec, _Micro} = gen_rpc:call(?SLAVE, os, timestamp),
    ok = gen_rpc_test_helper:stop_slave(),
    ok = lists:foreach(fun(Pid) -> ok = expect_message({got_nodedown, Pid}, 5000) end, Subscribers).

monitor_node_subscribe_twice(_Config) ->
    %% Subscribing multiple times results to a single notification
    true = gen_rpc:monitor_node(?SLAVE, true),
    true = gen_rpc:monitor_node(?SLAVE, true),
    {_Mega, _Sec, _Micro} = gen_rpc:call(?SLAVE, os, timestamp),
    ok = expect_message({nodeup, ?SLAVE}, 1000),
    ok = expect_no_message(100).

monitor_node_multiple_connections(_Config) ->
    %% A node with multiple keyed connections is down only
    %% after all its connections are gone
    true = gen_rpc:monitor_node(?SLAVE, true),
    {_Mega1, _Sec1, _Micro1} = gen_rpc:call({?SLAVE,key1}, os, timestamp),
    {_Mega2, _Sec2, _Micro2} = gen_rpc:call({?SLAVE,key2}, os, timestamp),
    %% A single nodeup, even with two connections
    ok = expect_message({nodeup, ?SLAVE}, 1000),
    ok = expect_no_message(100),
    %% Kill the first connection, the node is still considered up
    ok = kill_client({?SLAVE,key1}),
    ok = expect_no_message(500),
    %% Kill the last connection
    ok = kill_client({?SLAVE,key2}),
    ok = expect_message({nodedown, ?SLAVE}, 1000),
    ok = expect_no_message(100).

monitor_multiple_nodes(_Config) ->
    OtherNode = 'gen_rpc_other@127.0.0.1',
    true = gen_rpc:monitor_node(?SLAVE, true),
    true = gen_rpc:monitor_node(OtherNode, true),
    %% Unsubscribing from a node does not affect the other subscription
    true = gen_rpc:monitor_node(OtherNode, false),
    {_Mega, _Sec, _Micro} = gen_rpc:call(?SLAVE, os, timestamp),
    ok = expect_message({nodeup, ?SLAVE}, 1000),
    ok = gen_rpc_test_helper:stop_slave(),
    ok = expect_message({nodedown, ?SLAVE}, 5000),
    true = gen_rpc:monitor_node(?SLAVE, false),
    {NTS, STN, STM} = get_subscription_state(),
    #{} = NTS,
    #{} = STN,
    #{} = STM.

monitor_subscriber_cleanup(_Config) ->
    OtherNode = 'gen_rpc_other@127.0.0.1',
    Parent = self(),
    Subscriber = spawn(fun() ->
        true = gen_rpc:monitor_node(?SLAVE, true),
        true = gen_rpc:monitor_node(OtherNode, true),
        Parent ! {ready, self()}
    end),
    ok = expect_message({ready, Subscriber}, 1000),
    %% The subscriber dies without unsubscribing, everything should be cleaned up
    ok = wait_until_state_is_empty(20),
    %% The monitor survived and keeps working
    true = gen_rpc:monitor_node(?SLAVE, true),
    {_Mega, _Sec, _Micro} = gen_rpc:call(?SLAVE, os, timestamp),
    ok = expect_message({nodeup, ?SLAVE}, 1000).

monitor_node_invalid_flag(_Config) ->
    {'EXIT', {function_clause, _}} = try gen_rpc:monitor_node(?SLAVE, "true") catch error:Reason:Stack -> {'EXIT', {Reason, Stack}} end,
    {'EXIT', {function_clause, _}} = try gen_rpc:monitor_node(?SLAVE, not_a_boolean) catch error:Reason2:Stack2 -> {'EXIT', {Reason2, Stack2}} end,
    ok.

%%% ===================================================
%%% Auxiliary functions for test cases
%%% ===================================================
expect_message(Msg, Timeout) ->
    receive
        Msg -> ok
    after
        Timeout -> {error, {no_message, Msg}}
    end.

expect_no_message(Timeout) ->
    receive
        Msg -> {error, {unexpected_message, Msg}}
    after
        Timeout -> ok
    end.

kill_client(NodeOrTuple) ->
    PidName = gen_rpc_helper:make_process_name("client", NodeOrTuple),
    Pid = erlang:whereis(PidName),
    true = is_pid(Pid),
    MRef = erlang:monitor(process, Pid),
    true = erlang:exit(Pid, kill),
    receive
        {'DOWN', MRef, process, Pid, _Reason} -> ok
    after
        1000 -> {error, client_not_killed}
    end.

%% The subscription maps of the monitor: node to subscribers,
%% subscriber to nodes and subscriber to monitor references
get_subscription_state() ->
    {state, _PTN, _NodeConns, NTS, STN, STM} = sys:get_state(gen_rpc_monitor),
    {NTS, STN, STM}.

wait_until_state_is_empty(0) ->
    {error, {subscriptions_not_cleaned_up, get_subscription_state()}};

wait_until_state_is_empty(Retries) ->
    case get_subscription_state() of
        {NTS, STN, STM} when map_size(NTS) =:= 0, map_size(STN) =:= 0, map_size(STM) =:= 0 ->
            ok;
        _Else ->
            ok = timer:sleep(50),
            wait_until_state_is_empty(Retries - 1)
    end.
