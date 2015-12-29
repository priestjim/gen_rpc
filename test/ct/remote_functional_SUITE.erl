%%% -*-mode:erlang;coding:utf-8;tab-width:4;c-basic-offset:4;indent-tabs-mode:()-*-
%%% ex: set ft=erlang fenc=utf-8 sts=4 ts=4 sw=4 et:
%%%
%%% Copyright 2015 Panagiotis Papadomitsos. All Rights Reserved.
%%%

-module(remote_functional_SUITE).
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
    ok = ct:pal("Started [remote_functional] suite with master node [~s]", [node()]),
    Config.

end_per_suite(_Config) ->
    ok.

init_per_testcase(client_inactivity_timeout, Config) ->
    ok = gen_rpc_test_helper:start_slave(?SLAVE),
    ok = gen_rpc_test_helper:restart_application(),
    ok = application:set_env(?APP, client_inactivity_timeout, infinity),
    Config;

init_per_testcase(server_inactivity_timeout, Config) ->
    ok = gen_rpc_test_helper:start_slave(?SLAVE),
    ok = gen_rpc_test_helper:restart_application(),
    ok = application:set_env(?APP, server_inactivity_timeout, infinity),
    Config;

init_per_testcase(_OtherTest, Config) ->
    ok = gen_rpc_test_helper:start_slave(?SLAVE),
    Config.

end_per_testcase(client_inactivity_timeout, Config) ->
    ok = gen_rpc_test_helper:stop_slave(?SLAVE),
    ok = gen_rpc_test_helper:restart_application(),
    Config;

end_per_testcase(server_inactivity_timeout, Config) ->
    ok = gen_rpc_test_helper:stop_slave(?SLAVE),
    ok = gen_rpc_test_helper:restart_application(),
    Config;

end_per_testcase(_OtherTest, Config) ->
    ok = gen_rpc_test_helper:stop_slave(?SLAVE),
    Config.

%%% ===================================================
%%% Test cases
%%% ===================================================
%% Test main functions
call(_Config) ->
    ok = ct:pal("Testing [call]"),
    {_Mega, _Sec, _Micro} = gen_rpc:call(?SLAVE, os, timestamp).

call_mfa_undef(_Config) ->
    ok = ct:pal("Testing [call_mfa_undef]"),
    {badrpc, {'EXIT', {undef,[{os,timestamp_undef,_,_},_]}}} = gen_rpc:call(?SLAVE, os, timestamp_undef),
    ok = ct:pal("Result [call_mfa_undef]: signal=EXIT Reason={os,timestamp_undef}").

call_mfa_exit(_Config) ->
    ok = ct:pal("Testing [call_mfa_exit]"),
    {badrpc, {'EXIT', die}} = gen_rpc:call(?SLAVE, erlang, exit, ['die']),
    ok = ct:pal("Result [call_mfa_undef]: signal=EXIT Reason={die}").

call_mfa_throw(_Config) ->
    ok = ct:pal("Testing [call_mfa_throw]"),
    'throwXdown' = gen_rpc:call(?SLAVE, erlang, throw, ['throwXdown']),
    ok = ct:pal("Result [call_mfa_undef]: signal=EXIT Reason={die}").

call_with_receive_timeout(_Config) ->
    ok = ct:pal("Testing [call_with_receive_timeout]"),
    {badrpc, timeout} = gen_rpc:call(?SLAVE, timer, sleep, [500], 1),
    ok = timer:sleep(500).

interleaved_call(_Config) ->
    ok = ct:pal("Testing [interleaved_call]"),
    %% Spawn 3 consecutive processes that execute gen_rpc:call
    %% to the remote node and wait an inversely proportionate time
    %% for their result (effectively rendering the results out of order)
    %% in order to test proper data interleaving
    Pid1 = erlang:spawn(?MODULE, interleaved_call_proc, [self(), 1, infinity]),
    Pid2 = erlang:spawn(?MODULE, interleaved_call_proc, [self(), 2, 10]),
    Pid3 = erlang:spawn(?MODULE, interleaved_call_proc, [self(), 3, infinity]),
    ok = interleaved_call_loop(Pid1, Pid2, Pid3, 0),
    ok.

cast(_Config) ->
    ok = ct:pal("Testing [cast]"),
    true = gen_rpc:cast(?SLAVE, erlang, timestamp).

cast_anonymous_function(_Config) ->
    ok = ct:pal("Testing [cast_anonymous_function]"),
    true = gen_rpc:cast(?SLAVE, erlang, apply, [fun() -> os:timestamp() end, []]).

cast_mfa_undef(_Config) ->
    ok = ct:pal("Testing [cast_mfa_undef]"),
    true = gen_rpc:cast(?SLAVE, os, timestamp_undef, []).

cast_mfa_exit(_Config) ->
    ok = ct:pal("Testing [cast_mfa_exit]"),
    true = gen_rpc:cast(?SLAVE, erlang, apply, [fun() -> exit(die) end, []]).

cast_mfa_throw(_Config) ->
    ok = ct:pal("Testing [cast_mfa_throw]"),
    true = gen_rpc:cast(?SLAVE, erlang, throw, ['throwme']).

cast_inexistent_node(_Config) ->
    ok = ct:pal("Testing [cast_inexistent_node]"),
    true = gen_rpc:cast(?FAKE_NODE, os, timestamp, [], 1000).

pinfo_alive_process(_Config) ->
    ok = ct:pal("Testing [pinfo]"),
    Pid = gen_rpc:call(?SLAVE, gen_rpc_test_helper, spawn_long_running, [100000]),
    % If this process is alive when pinfo it, we should get non-empty list
    true = gen_rpc:call(?SLAVE, erlang, is_process_alive, [Pid]),
    [] =/= gen_rpc:pinfo(Pid).

pinfo_dead_process(_Config) ->
    ok = ct:pal("Testing [pinfo]"),
    Pid = gen_rpc:call(?SLAVE, gen_rpc_test_helper, spawn_short_running, []),
    % If this process is dead when pinfo it, we should get undefined.
    false = gen_rpc:call(?SLAVE, erlang, is_process_alive, [Pid]),
    'undefined' = gen_rpc:pinfo(Pid).

pinfo_item(_Config) ->
    ok = ct:pal("Testing [pinfo_item]"),
    Pid = gen_rpc:call(?SLAVE, erlang, spawn, [fun() -> timer:sleep(100000) end]),
    % If this process is alive when pinfo it, we should get non-empty list
    true = gen_rpc:call(?SLAVE, erlang, is_process_alive, [Pid]),
    [{status,waiting}] = gen_rpc:pinfo(Pid, [status]).

safe_cast(_Config) ->
    ok = ct:pal("Testing [safe_cast]"),
    true = gen_rpc:safe_cast(?SLAVE, erlang, timestamp).

safe_cast_anonymous_function(_Config) ->
    ok = ct:pal("Testing [safe_cast_anonymous_function]"),
    true = gen_rpc:safe_cast(?SLAVE, erlang, apply, [fun() -> os:timestamp() end, []]).

safe_cast_mfa_undef(_Config) ->
    ok = ct:pal("Testing [safe_cast_mfa_undef]"),
    true = gen_rpc:safe_cast(?SLAVE, os, timestamp_undef, []).

safe_cast_mfa_exit(_Config) ->
    ok = ct:pal("Testing [safe_cast_mfa_exit]"),
    true = gen_rpc:safe_cast(?SLAVE, erlang, apply, [fun() -> exit(die) end, []]).

safe_cast_mfa_throw(_Config) ->
    ok = ct:pal("Testing [safe_cast_mfa_throw]"),
    true = gen_rpc:safe_cast(?SLAVE, erlang, throw, ['throwme']).

safe_cast_inexistent_node(_Config) ->
    ok = ct:pal("Testing [safe_cast_inexistent_node]"),
    {badrpc, nodedown} = gen_rpc:safe_cast(?FAKE_NODE, os, timestamp, [], 1000).

async_call(_Config) ->
    ok = ct:pal("Testing [async_call]"),
    YieldKey0 = gen_rpc:async_call(?SLAVE, os, timestamp, []),
    {_Mega, _Sec, _Micro} = gen_rpc:yield(YieldKey0),
    NbYieldKey0 = gen_rpc:async_call(?SLAVE, os, timestamp, []),
    {value,{_,_,_}}= gen_rpc:nb_yield(NbYieldKey0, 1000),
    YieldKey = gen_rpc:async_call(?SLAVE, io_lib, print, [yield_key]),
    "yield_key" = gen_rpc:yield(YieldKey),
    NbYieldKey = gen_rpc:async_call(?SLAVE, io_lib, print, [nb_yield_key]),
    {value, "nb_yield_key"} = gen_rpc:nb_yield(NbYieldKey, 10).

async_call_yield_reentrant(_Config) ->
    ok = ct:pal("Testing [async_call_yield_reentrant]"),
    YieldKey0 = gen_rpc:async_call(?SLAVE, os, timestamp, []),
    {_Mega, _Sec, _Micro} = gen_rpc:yield(YieldKey0),
    Pid = proc_lib:spawn(fun()->
                                {value, {badrpc, timeout}} = gen_rpc:yield(YieldKey0),
                                ok = ct:pal("yield/1 waits forever. Should never see this.")
                         end),
    {ok, _} = timer:kill_after(5000, Pid),
    NbYieldKey0 = gen_rpc:async_call(?SLAVE, os, timestamp, []),
    % Verify not able to reuse Key again. Key is one time use.
    {_,_,_} = gen_rpc:yield(NbYieldKey0, 100),
    {value, {badrpc, timeout}} = gen_rpc:nb_yield(NbYieldKey0, 10),
    YieldKey = gen_rpc:async_call(?SLAVE, io_lib, print, [yield_key]),
    "yield_key" = gen_rpc:yield(YieldKey),
    {badrpc, timeout} = gen_rpc:yield(YieldKey, 100),
    NbYieldKey = gen_rpc:async_call(?SLAVE, io_lib, print, [nb_yield_key]),
    {value, "nb_yield_key"} = gen_rpc:nb_yield(NbYieldKey, 10).

async_call_mfa_undef(_Config) ->
    ok = ct:pal("Testing [async_call_mfa_undef]"),
    YieldKey = gen_rpc:async_call(?SLAVE, os, timestamp_undef),
    {badrpc, {'EXIT', {undef,[{os,timestamp_undef,_,_},_]}}} = gen_rpc:yield(YieldKey),
    NBYieldKey = gen_rpc:async_call(?SLAVE, os, timestamp_undef),
    {value, {badrpc, {'EXIT', {undef,[{os,timestamp_undef,_,_},_]}}}} = gen_rpc:nb_yield(NBYieldKey, 2000),
    ok = ct:pal("Result [async_call_mfa_undef]: signal=EXIT Reason={os,timestamp_undef}").

async_call_mfa_exit(_Config) ->
    ok = ct:pal("Testing [async_call_mfa_exit]"),
    YieldKey = gen_rpc:async_call(?SLAVE, erlang, exit, ['die']),
    {badrpc, {'EXIT', die}} = gen_rpc:yield(YieldKey),
    NBYieldKey = gen_rpc:async_call(?SLAVE, erlang, exit, ['die']),
    {value, {badrpc, {'EXIT', die}}} = gen_rpc:nb_yield(NBYieldKey, 1000),
    ok = ct:pal("Result [async_call_mfa_undef]: signal=EXIT Reason={os,timestamp_undef}").

async_call_mfa_throw(_Config) ->
    ok = ct:pal("Testing [async_call_mfa_throw]"),
    YieldKey = gen_rpc:async_call(?SLAVE, erlang, throw, ['throwXdown']),
    'throwXdown' = gen_rpc:yield(YieldKey),
    NBYieldKey = gen_rpc:async_call(?SLAVE, erlang, throw, ['throwXdown']),
    {value, 'throwXdown'} = gen_rpc:nb_yield(NBYieldKey, 1000),
    ok = ct:pal("Result [async_call_mfa_undef]: signal=EXIT Reason={throwXdown}").

async_call_yield_timeout(_Config) ->
    ok = ct:pal("Testing [async_call_yield_timeout]"),
    YieldKey = gen_rpc:async_call(?SLAVE, timer, sleep, [1000]),
    {badrpc,timeout} = gen_rpc:yield(YieldKey, 5),
    NBYieldKey = gen_rpc:async_call(?SLAVE, timer, sleep, [1000]),
    {value, {badrpc,timeout}} = gen_rpc:nb_yield(NBYieldKey, 5),
    ok = ct:pal("Result [async_call_yield_timeout]: signal=EXIT Reason={timeout}").

async_call_nb_yield_infinity(_Config) ->
    ok = ct:pal("Testing [async_call_yield_infinity]"),
    YieldKey = gen_rpc:async_call(?SLAVE, timer, sleep, [1000]),
    ok = gen_rpc:yield(YieldKey),
    NBYieldKey = gen_rpc:async_call(?SLAVE, timer, sleep, [1000]),
    {value, ok} = gen_rpc:nb_yield(NBYieldKey, infinity),
    ok = ct:pal("Result [async_call_yield_infinity]: signal=EXIT Reason={ok}").

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
%% Loop in order to receive all messages from all workers
interleaved_call_loop(Pid1, Pid2, Pid3, Num) when Num < 3 ->
    receive
        {reply, Pid1, 1, 1} ->
            ct:pal("Received proper reply from Worker 1"),
            interleaved_call_loop(Pid1, Pid2, Pid3, Num+1);
        {reply, Pid2, 2, {badrpc, timeout}} ->
            ct:pal("Received proper reply from Worker 2"),
            interleaved_call_loop(Pid1, Pid2, Pid3, Num+1);
        {reply, Pid3, 3, 3} ->
            ct:pal("Received proper reply from Worker 3"),
            interleaved_call_loop(Pid1, Pid2, Pid3, Num+1);
        _Else ->
            ct:pal("Received out of order reply"),
            fail
    end;
interleaved_call_loop(_, _, _, 3) ->
    ok.

%% This function will become a spawned process that performs the RPC
%% call and then returns the value of the RPC call
%% We spawn it in order to achieve parallelism and test out-of-order
%% execution of multiple RPC calls
interleaved_call_proc(Caller, Num, Timeout) ->
    Result = gen_rpc:call(?SLAVE, ?MODULE, interleaved_call_executor, [Num], Timeout),
    Caller ! {reply, self(), Num, Result},
    ok.

%% This is the function that gets executed in the "remote"
%% node, sleeping 3 minus $Num seconds and returning the number
%% effectively returning a number thats inversely proportional
%% to the number of seconds the worker slept
interleaved_call_executor(Num) when is_integer(Num) ->
    %% Sleep for 3 - Num
    ok = timer:sleep((3 - Num) * 1000),
    %% Then return the number
    Num.
