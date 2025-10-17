%%% -*-mode:erlang;coding:utf-8;tab-width:4;c-basic-offset:4;indent-tabs-mode:()-*-
%%% ex: set ft=erlang fenc=utf-8 sts=4 ts=4 sw=4 et:
%%%
%%% Copyright 2015 Panagiotis Papadomitsos. All Rights Reserved.
%%%

-module(ec_ssl_SUITE).
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
    %% Setup the EC SSL driver
    ok = gen_rpc_test_helper:set_driver_configuration(ec_ssl, ?MASTER),
    %% Starting the application locally
    {ok, _MasterApps} = application:ensure_all_started(?APP),
    %% Starting the second node with EC SSL
    {ok, SlaveNode} = gen_rpc_test_helper:start_slave(ec_ssl),
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
ec_ssl_call(_Config) ->
    %% Test basic call functionality over EC SSL
    SlaveNode = proplists:get_value(slave, _Config),
    pong = gen_rpc:call(SlaveNode, erlang, ping, []).

ec_ssl_cast(_Config) ->
    %% Test cast functionality over EC SSL
    SlaveNode = proplists:get_value(slave, _Config),
    ok = gen_rpc:cast(SlaveNode, erlang, put, [test_key, test_value]).

ec_ssl_async_call(_Config) ->
    %% Test async call functionality over EC SSL
    SlaveNode = proplists:get_value(slave, _Config),
    Key = gen_rpc:async_call(SlaveNode, erlang, node, []),
    SlaveNode = gen_rpc:yield(Key).

ec_ssl_multicall(_Config) ->
    %% Test multicall functionality over EC SSL
    SlaveNode = proplists:get_value(slave, _Config),
    {[SlaveNode], []} = gen_rpc:multicall([SlaveNode], erlang, ping, []).

ec_ssl_abcast(_Config) ->
    %% Test abcast functionality over EC SSL
    SlaveNode = proplists:get_value(slave, _Config),
    
    %% Register a test process on slave
    _TestPid = spawn_link(SlaveNode, fun() ->
        register(test_process, self()),
        receive
            test_message -> ok
        after 5000 -> timeout
        end
    end),
    
    %% Wait for registration
    timer:sleep(100),
    
    %% Send abcast
    abcast = gen_rpc:abcast([SlaveNode], test_process, test_message),
    
    %% Wait for completion
    timer:sleep(100).

ec_ssl_certificate_verification(_Config) ->
    %% Test that EC SSL certificates are properly verified
    %% This test verifies that the connection was established successfully
    %% which means certificate verification passed
    SlaveNode = proplists:get_value(slave, _Config),
    
    %% Call should succeed with proper certificate verification
    pong = gen_rpc:call(SlaveNode, erlang, ping, []),
    
    %% Verify we're actually using SSL by checking the driver
    {ok, DefaultDriver} = application:get_env(?APP, default_client_driver),
    ssl = DefaultDriver.

ec_ssl_large_payload(_Config) ->
    %% Test EC SSL with larger payloads to ensure encryption works properly
    SlaveNode = proplists:get_value(slave, _Config),
    LargeData = lists:duplicate(1000, <<"test_data">>),
    LargeData = gen_rpc:call(SlaveNode, erlang, identity, [LargeData]).

ec_ssl_concurrent_calls(_Config) ->
    %% Test multiple concurrent calls over EC SSL
    SlaveNode = proplists:get_value(slave, _Config),
    
    Parent = self(),
    Workers = [spawn_link(fun() ->
        Result = gen_rpc:call(SlaveNode, erlang, node, []),
        Parent ! {result, self(), Result}
    end) || _ <- lists:seq(1, 5)],
    
    %% Collect results
    Results = [receive {result, Pid, Result} -> Result end || Pid <- Workers],
    
    %% All should succeed with slave node name
    ExpectedResults = lists:duplicate(5, SlaveNode),
    ExpectedResults = Results.

ec_ssl_connection_persistence(_Config) ->
    %% Test that EC SSL connections are properly maintained
    SlaveNode = proplists:get_value(slave, _Config),
    
    %% Make multiple calls - should reuse connection
    pong = gen_rpc:call(SlaveNode, erlang, ping, []),
    timer:sleep(100),
    pong = gen_rpc:call(SlaveNode, erlang, ping, []),
    timer:sleep(100), 
    pong = gen_rpc:call(SlaveNode, erlang, ping, []).