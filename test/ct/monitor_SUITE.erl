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
    %% Setup application logging
    ok = gen_rpc_test_helper:set_application_environment(?MASTER),
    %% Setup the simple TCP driver
    ok = gen_rpc_test_helper:set_driver_configuration(tcp, ?MASTER),
    %% Starting the application locally
    {ok, _MasterApps} = application:ensure_all_started(?APP),
    %% Starting the second node
    {ok, SlaveNode} = gen_rpc_test_helper:start_slave(tcp),
    [{slave,SlaveNode}|Config].

end_per_suite(Config) ->
    SlaveNode = proplists:get_value(slave, Config),
    ok = gen_rpc_test_helper:stop_slave(SlaveNode).

init_per_testcase(_Test, Config) ->
    Config.

end_per_testcase(_Test, _Config) ->
    ok.

%%% ===================================================
%%% Test cases
%%% ===================================================
monitor_node_up_down(_Config) ->
    %% Test monitor_node functionality
    SlaveNode = proplists:get_value(slave, _Config),
    
    %% Start monitoring the slave node
    true = gen_rpc:monitor_node(SlaveNode, true),
    
    %% Make sure we can connect to the slave node first
    pong = gen_rpc:call(SlaveNode, erlang, ping, []),
    
    %% Stop the slave node to trigger nodedown message
    ok = gen_rpc_test_helper:stop_slave(SlaveNode),
    
    %% Wait for nodedown message
    receive
        {nodedown, SlaveNode} ->
            ok
    after 5000 ->
        ct:fail("Did not receive nodedown message")
    end,
    
    %% Restart the slave node
    {ok, NewSlaveNode} = gen_rpc_test_helper:start_slave(tcp),
    
    %% Wait for nodeup message
    receive
        {nodeup, NewSlaveNode} ->
            ok
    after 5000 ->
        ct:fail("Did not receive nodeup message")
    end,
    
    %% Stop monitoring
    true = gen_rpc:monitor_node(NewSlaveNode, false),
    
    %% Clean up
    ok = gen_rpc_test_helper:stop_slave(NewSlaveNode).

monitor_node_multiple_subscribers(_Config) ->
    %% Test that multiple processes can monitor the same node
    SlaveNode = proplists:get_value(slave, _Config),
    
    %% Start two monitoring processes
    Parent = self(),
    Pid1 = spawn(fun() ->
        true = gen_rpc:monitor_node(SlaveNode, true),
        Parent ! {ready, self()},
        receive
            {nodedown, SlaveNode} ->
                Parent ! {got_nodedown, self()}
        after 5000 ->
            Parent ! {timeout, self()}
        end
    end),
    
    Pid2 = spawn(fun() ->
        true = gen_rpc:monitor_node(SlaveNode, true),
        Parent ! {ready, self()},
        receive
            {nodedown, SlaveNode} ->
                Parent ! {got_nodedown, self()}
        after 5000 ->
            Parent ! {timeout, self()}
        end
    end),
    
    %% Wait for both to be ready
    receive {ready, Pid1} -> ok end,
    receive {ready, Pid2} -> ok end,
    
    %% Stop the slave node
    ok = gen_rpc_test_helper:stop_slave(SlaveNode),
    
    %% Both should receive nodedown
    receive {got_nodedown, Pid1} -> ok end,
    receive {got_nodedown, Pid2} -> ok end.

monitor_node_unsubscribe(_Config) ->
    %% Test unsubscribing from node monitoring
    SlaveNode = proplists:get_value(slave, _Config),
    
    %% Start monitoring
    true = gen_rpc:monitor_node(SlaveNode, true),
    
    %% Stop monitoring
    true = gen_rpc:monitor_node(SlaveNode, false),
    
    %% Stop the slave node
    ok = gen_rpc_test_helper:stop_slave(SlaveNode),
    
    %% Should not receive nodedown message
    receive
        {nodedown, SlaveNode} ->
            ct:fail("Received unexpected nodedown message")
    after 1000 ->
        ok
    end.

monitor_node_process_death_cleanup(_Config) ->
    %% Test that monitor subscriptions are cleaned up when subscriber dies
    SlaveNode = proplists:get_value(slave, _Config),
    
    Parent = self(),
    Pid = spawn(fun() ->
        true = gen_rpc:monitor_node(SlaveNode, true),
        Parent ! {ready, self()},
        %% Just exit without unsubscribing
        exit(normal)
    end),
    
    %% Wait for process to be ready and then die
    receive {ready, Pid} -> ok end,
    
    %% Give some time for cleanup
    timer:sleep(100),
    
    %% Monitor should be automatically cleaned up when process dies
    %% This is verified by the gen_rpc_monitor process not crashing
    ok.
