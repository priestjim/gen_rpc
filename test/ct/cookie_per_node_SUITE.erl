%%% -*-mode:erlang;coding:utf-8;tab-width:4;c-basic-offset:4;indent-tabs-mode:()-*-
%%% ex: set ft=erlang fenc=utf-8 sts=4 ts=4 sw=4 et:
%%%
%%% Copyright 2015 Panagiotis Papadomitsos. All Rights Reserved.
%%%

-module(cookie_per_node_SUITE).
-author("Panagiotis Papadomitsos <pj@ezgr.net>").

%%% CT Macros
-include_lib("test/include/ct.hrl").

%%% No need to export anything, everything is automatically exported
%%% as part of the test profile

%%% ===================================================
%%% CT callback functions
%%% ===================================================
all() ->
    [{group, tcp}, {group, ssl}].

groups() ->
    Cases = gen_rpc_test_helper:get_test_functions(?MODULE),
    [{tcp, [], Cases}, {ssl, [], Cases}].

init_per_group(Group, Config) ->
    % Our group name is the name of the driver
    Driver = Group,
    %% Starting Distributed Erlang on local node
    {ok, _Pid} = gen_rpc_test_helper:start_distribution(?MASTER),
    gen_rpc_test_helper:store_driver_in_config(Driver, Config).

end_per_group(_Driver, _Config) ->
    ok.

init_per_testcase(_Test, Config) ->
    ok = gen_rpc_test_helper:restart_application(),
    Driver = gen_rpc_test_helper:get_driver_from_config(Config),
    ok = gen_rpc_test_helper:start_master(Driver),
    ok = gen_rpc_test_helper:start_slave(Driver),
    Config.

end_per_testcase(_Test, Config) ->
    ok = gen_rpc_test_helper:stop_slave(),
    Config.

%%% ===================================================
%%% Test cases
%%% ===================================================
%% Without any configuration the node cookie is used
default_cookie(_Config) ->
    DefaultCookie = erlang:get_cookie(),
    DefaultCookie = gen_rpc_helper:get_cookie_per_node(?SLAVE),
    {_Mega, _Sec, _Micro} = gen_rpc:call(?SLAVE, os, timestamp).

internal_cookie_config(_Config) ->
    DefaultCookie = erlang:get_cookie(),
    ok = application:set_env(?APP, cookie_per_node, {internal, #{?SLAVE => slave_cookie}}),
    slave_cookie = gen_rpc_helper:get_cookie_per_node(?SLAVE),
    %% Nodes without a configured cookie fall back to the node cookie
    DefaultCookie = gen_rpc_helper:get_cookie_per_node('gen_rpc_other@127.0.0.1').

external_cookie_config(_Config) ->
    ok = application:set_env(?APP, cookie_per_node, {external, gen_rpc_test_helper}),
    external_test_cookie = gen_rpc_helper:get_cookie_per_node(?SLAVE).

%% Both nodes use a cookie per node that matches
matching_cookie_per_node(_Config) ->
    ok = set_cookies(#{?SLAVE => shared_cookie}, #{?MASTER => shared_cookie}),
    {_Mega, _Sec, _Micro} = gen_rpc:call(?SLAVE, os, timestamp),
    shared_cookie = gen_rpc_helper:get_cookie_per_node(?SLAVE),
    %% Calls from the slave to the master are authenticated too
    {_Mega1, _Sec1, _Micro1} = rpc:call(?SLAVE, gen_rpc, call, [?MASTER, os, timestamp]).

%% The cookie the client sends is not the one the server expects
mismatching_cookie_per_node(_Config) ->
    ok = set_cookies(#{?SLAVE => wrong_cookie}, #{}),
    {badrpc, invalid_cookie} = gen_rpc:call(?SLAVE, os, timestamp, []).

%% Casts and async calls fail gracefully as well
mismatching_cookie_per_node_async_call(_Config) ->
    ok = set_cookies(#{?SLAVE => wrong_cookie}, #{}),
    Key = gen_rpc:async_call(?SLAVE, os, timestamp, []),
    {badrpc, invalid_cookie} = gen_rpc:yield(Key),
    true = gen_rpc:cast(?SLAVE, os, timestamp, []),
    [] = gen_rpc:nodes().

%% Authentication is per node, the cookie for one node does not leak to another
cookie_per_node_other_node_unaffected(_Config) ->
    ok = set_cookies(#{'gen_rpc_other@127.0.0.1' => wrong_cookie}, #{}),
    {_Mega, _Sec, _Micro} = gen_rpc:call(?SLAVE, os, timestamp).

external_cookie_module(_Config) ->
    ok = set_cookies({external, gen_rpc_test_helper}, {external, gen_rpc_test_helper}),
    {_Mega, _Sec, _Micro} = gen_rpc:call(?SLAVE, os, timestamp),
    %% The server validates with the external module as well, so a client
    %% that uses a different cookie gets rejected
    ok = application:set_env(?APP, cookie_per_node, {internal, #{?SLAVE => not_the_external_cookie}}),
    ok = gen_rpc_client:stop(?SLAVE),
    {badrpc, invalid_cookie} = gen_rpc:call(?SLAVE, os, timestamp, []).

%%% ===================================================
%%% Auxiliary functions for test cases
%%% ===================================================
%% Set the cookie per node configuration on the master and the slave
set_cookies(MasterMap, SlaveMap) ->
    ok = application:set_env(?APP, cookie_per_node, to_config(MasterMap)),
    ok = rpc:call(?SLAVE, application, set_env, [?APP, cookie_per_node, to_config(SlaveMap)]),
    ok.

to_config({external, Module}) ->
    {external, Module};
to_config(Map) when is_map(Map) ->
    {internal, Map}.
