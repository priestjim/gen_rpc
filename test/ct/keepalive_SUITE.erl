%%% -*-mode:erlang;coding:utf-8;tab-width:4;c-basic-offset:4;indent-tabs-mode:()-*-
%%% ex: set ft=erlang fenc=utf-8 sts=4 ts=4 sw=4 et:
%%%
%%% Copyright 2015 Panagiotis Papadomitsos. All Rights Reserved.
%%%

-module(keepalive_SUITE).
-author("Panagiotis Papadomitsos <pj@ezgr.net>").

%%% CT Macros
-include_lib("test/include/ct.hrl").

%%% No need to export anything, everything is automatically exported
%%% as part of the test profile

%%% ===================================================
%%% CT callback functions
%%% ===================================================
all() ->
    [{group, unit}, {group, integration}].

groups() ->
    UnitCases = [start_disabled, start_enabled, start_error, check_active, check_timeout,
                 check_error, cancel, resume, timer_message],
    IntegrationCases = [client_stays_alive, client_without_keepalive_is_closed_by_server,
                        client_inactivity_timeout_ignores_keepalive],
    [{unit, [], UnitCases}, {integration, [], IntegrationCases}].

init_per_group(unit, Config) ->
    Config;

init_per_group(integration, Config) ->
    %% Starting Distributed Erlang on local node
    {ok, _Pid} = gen_rpc_test_helper:start_distribution(?MASTER),
    Config.

end_per_group(_Group, _Config) ->
    ok.

init_per_testcase(Test, Config) when Test =:= client_stays_alive;
                                     Test =:= client_without_keepalive_is_closed_by_server;
                                     Test =:= client_inactivity_timeout_ignores_keepalive ->
    ok = gen_rpc_test_helper:restart_application(),
    ok = gen_rpc_test_helper:start_master(tcp),
    ok = gen_rpc_test_helper:start_slave(tcp),
    Config;

init_per_testcase(_Test, Config) ->
    Config.

end_per_testcase(Test, Config) when Test =:= client_stays_alive;
                                    Test =:= client_without_keepalive_is_closed_by_server;
                                    Test =:= client_inactivity_timeout_ignores_keepalive ->
    ok = gen_rpc_test_helper:stop_slave(),
    Config;

end_per_testcase(_Test, Config) ->
    Config.

%%% ===================================================
%%% Unit test cases
%%% ===================================================
%% A zero interval disables the keepalive
start_disabled(_Config) ->
    StatFun = fun() -> {ok, 42} end,
    {ok, KeepAlive} = gen_rpc_keepalive:start(StatFun, 0, timeout),
    ok = gen_rpc_keepalive:cancel(KeepAlive),
    ok = gen_rpc_test_helper:expect_no_message(100).

start_enabled(_Config) ->
    StatFun = fun() -> {ok, 42} end,
    {ok, KeepAlive} = gen_rpc_keepalive:start(StatFun, 1, timeout),
    ok = gen_rpc_test_helper:expect_message(timeout, 5000),
    ok = gen_rpc_keepalive:cancel(KeepAlive).

start_error(_Config) ->
    StatFun = fun() -> {error, test_error} end,
    {error, test_error} = gen_rpc_keepalive:start(StatFun, 1, timeout).

%% The statistic changed since the last check, the connection is alive
check_active(_Config) ->
    {ok, KeepAlive} = gen_rpc_keepalive:start(counting_stat_fun(), 1, timeout),
    {ok, KeepAlive1} = gen_rpc_keepalive:check(KeepAlive),
    {ok, KeepAlive2} = gen_rpc_keepalive:check(KeepAlive1),
    ok = gen_rpc_keepalive:cancel(KeepAlive2).

%% The statistic did not change since the last check
check_timeout(_Config) ->
    StatFun = fun() -> {ok, 42} end,
    {ok, KeepAlive} = gen_rpc_keepalive:start(StatFun, 1, timeout),
    {error, timeout} = gen_rpc_keepalive:check(KeepAlive),
    ok = gen_rpc_keepalive:cancel(KeepAlive).

check_error(_Config) ->
    Ref = make_ref(),
    StatFun = fun() ->
        case erlang:get(Ref) of
            undefined ->
                erlang:put(Ref, true),
                {ok, 42};
            true ->
                {error, closed}
        end
    end,
    {ok, KeepAlive} = gen_rpc_keepalive:start(StatFun, 1, timeout),
    {error, closed} = gen_rpc_keepalive:check(KeepAlive),
    ok = gen_rpc_keepalive:cancel(KeepAlive).

cancel(_Config) ->
    StatFun = fun() -> {ok, 42} end,
    {ok, KeepAlive} = gen_rpc_keepalive:start(StatFun, 1, timeout),
    ok = gen_rpc_keepalive:cancel(KeepAlive),
    %% The cancelled timer never fires
    ok = gen_rpc_test_helper:expect_no_message(1500),
    %% Cancelling twice is not a problem
    ok = gen_rpc_keepalive:cancel(KeepAlive),
    %% Neither is cancelling a disabled keepalive
    {ok, Disabled} = gen_rpc_keepalive:start(StatFun, 0, timeout),
    ok = gen_rpc_keepalive:cancel(Disabled).

resume(_Config) ->
    StatFun = fun() -> {ok, 42} end,
    {ok, KeepAlive} = gen_rpc_keepalive:start(StatFun, 1, timeout),
    ok = gen_rpc_keepalive:cancel(KeepAlive),
    KeepAlive1 = gen_rpc_keepalive:resume(KeepAlive),
    ok = gen_rpc_test_helper:expect_message(timeout, 5000),
    ok = gen_rpc_keepalive:cancel(KeepAlive1).

%% The message sent to the owner is the one configured
timer_message(_Config) ->
    StatFun = fun() -> {ok, 42} end,
    {ok, KeepAlive} = gen_rpc_keepalive:start(StatFun, 1, {keepalive, check}),
    ok = gen_rpc_test_helper:expect_message({keepalive, check}, 5000),
    ok = gen_rpc_keepalive:cancel(KeepAlive).

%%% ===================================================
%%% Integration test cases
%%% ===================================================
%% An idle connection is kept alive by the pings of the client
%% even if the server would otherwise close it due to inactivity
client_stays_alive(_Config) ->
    ok = application:set_env(?APP, keepalive_interval, 1),
    ok = rpc:call(?SLAVE, application, set_env, [?APP, server_inactivity_timeout, 2500]),
    {_Mega, _Sec, _Micro} = gen_rpc:call(?SLAVE, os, timestamp),
    ClientPid = gen_rpc_test_helper:get_client_pid(?SLAVE),
    true = is_pid(ClientPid),
    ok = timer:sleep(5000),
    ClientPid = gen_rpc_test_helper:get_client_pid(?SLAVE),
    {_Mega1, _Sec1, _Micro1} = gen_rpc:call(?SLAVE, os, timestamp),
    ClientPid = gen_rpc_test_helper:get_client_pid(?SLAVE).

%% Without keepalive the server closes the idle connection
client_without_keepalive_is_closed_by_server(_Config) ->
    ok = application:set_env(?APP, keepalive_interval, 0),
    ok = rpc:call(?SLAVE, application, set_env, [?APP, server_inactivity_timeout, 500]),
    {_Mega, _Sec, _Micro} = gen_rpc:call(?SLAVE, os, timestamp),
    ClientPid = gen_rpc_test_helper:get_client_pid(?SLAVE),
    true = is_pid(ClientPid),
    ok = gen_rpc_test_helper:wait_until(fun() -> gen_rpc_test_helper:get_client_pid(?SLAVE) =:= undefined end, 5000),
    %% A new call transparently establishes a new connection
    {_Mega1, _Sec1, _Micro1} = gen_rpc:call(?SLAVE, os, timestamp).

%% Keepalive pings are not client activity, they do not postpone
%% the client inactivity timeout
client_inactivity_timeout_ignores_keepalive(_Config) ->
    ok = application:set_env(?APP, keepalive_interval, 1),
    ok = application:set_env(?APP, client_inactivity_timeout, 2500),
    {_Mega, _Sec, _Micro} = gen_rpc:call(?SLAVE, os, timestamp),
    true = is_pid(gen_rpc_test_helper:get_client_pid(?SLAVE)),
    % The pings do not keep the client alive, it goes away once the timeout is reached
    ok = gen_rpc_test_helper:wait_until(fun() -> gen_rpc_test_helper:get_client_pid(?SLAVE) =:= undefined end, 6000),
    ok = application:set_env(?APP, client_inactivity_timeout, infinity).

%%% ===================================================
%%% Auxiliary functions for test cases
%%% ===================================================
counting_stat_fun() ->
    Ref = make_ref(),
    fun() ->
        Val = case erlang:get(Ref) of
            undefined -> 0;
            Prev -> Prev + 1
        end,
        erlang:put(Ref, Val),
        {ok, Val}
    end.

