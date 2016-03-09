%%% -*-mode:erlang;coding:utf-8;tab-width:4;c-basic-offset:4;indent-tabs-mode:()-*-
%%% ex: set ft=erlang fenc=utf-8 sts=4 ts=4 sw=4 et:
%%%
%%% Copyright 2015 Panagiotis Papadomitsos. All Rights Reserved.
%%%

-module(local_SUITE).
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
    Config.

end_per_suite(_Config) ->
    ok.

init_per_testcase(client_inactivity_timeout, Config) ->
    ok = gen_rpc_test_helper:restart_application(),
    ok = gen_rpc_test_helper:set_application_environment(),
    ok = application:set_env(?APP, client_inactivity_timeout, 500),
    Config;

init_per_testcase(server_inactivity_timeout, Config) ->
    ok = gen_rpc_test_helper:restart_application(),
    ok = gen_rpc_test_helper:set_application_environment(),
    ok = application:set_env(?APP, server_inactivity_timeout, 500),
    Config;

init_per_testcase(async_call_inexistent_node, Config) ->
    ok = gen_rpc_test_helper:restart_application(),
    ok = gen_rpc_test_helper:set_application_environment(),
    Config;

init_per_testcase(remote_node_call, Config) ->
    ok = gen_rpc_test_helper:restart_application(),
    ok = gen_rpc_test_helper:set_application_environment(),
    %% In order to connect to the slave
    ok = application:set_env(?APP, tcp_server_port, 5370),
    ok = gen_rpc_test_helper:start_slave(?SLAVE, 5370),
    Config;

init_per_testcase(_OtherTest, Config) ->
    Config.

end_per_testcase(client_inactivity_timeout, Config) ->
    ok = application:set_env(?APP, client_inactivity_timeout, infinity),
    Config;

end_per_testcase(server_inactivity_timeout, Config) ->
    ok = application:set_env(?APP, server_inactivity_timeout, infinity),
    Config;

end_per_testcase(remote_node_call, Config) ->
    ok = gen_rpc_test_helper:stop_slave(?SLAVE),
    ok = gen_rpc_test_helper:restart_application(),
    ok = gen_rpc_test_helper:set_application_environment(),
    Config;

end_per_testcase(_OtherTest, Config) ->
    Config.

%%% ===================================================
%%% Test cases
%%% ===================================================
%% Test supervisor's status
supervisor_black_box(_Config) ->
    true = erlang:is_process_alive(whereis(gen_rpc_server_sup)),
    true = erlang:is_process_alive(whereis(gen_rpc_acceptor_sup)),
    true = erlang:is_process_alive(whereis(gen_rpc_tcp_acceptor_sup)),
    true = erlang:is_process_alive(whereis(gen_rpc_client_sup)),
    true = erlang:is_process_alive(whereis(gen_rpc_tcp_server)),
    true = erlang:is_process_alive(whereis(gen_rpc_dispatcher)),
    ok.

%% Test main functions
call(_Config) ->
    {_Mega, _Sec, _Micro} = gen_rpc:call(?NODE, os, timestamp).

call_anonymous_function(_Config) ->
    {_,"\"call_anonymous_function\""} = gen_rpc:call(?NODE, erlang, apply,[fun(A) -> {self(), io_lib:print(A)} end,
                                                     ["call_anonymous_function"]]).

call_anonymous_undef(_Config) ->
    {badrpc, {'EXIT', {undef,[{os,timestamp_undef,[],[]},_]}}}  = gen_rpc:call(?NODE, erlang, apply, [fun() -> os:timestamp_undef() end, []]),
   ok = ct:pal("Result [call_anonymous_undef]: signal=EXIT Reason={os,timestamp_undef}").

call_mfa_undef(_Config) ->
    {badrpc, {'EXIT', {undef,[{os,timestamp_undef,_,_},_]}}} = gen_rpc:call(?NODE, os, timestamp_undef),
    ok = ct:pal("Result [call_mfa_undef]: signal=EXIT Reason={os,timestamp_undef}").

call_mfa_exit(_Config) ->
    {badrpc, {'EXIT', die}} = gen_rpc:call(?NODE, erlang, exit, ['die']),
    ok = ct:pal("Result [call_mfa_undef]: signal=EXIT Reason={die}").

call_mfa_throw(_Config) ->
    'throwXdown' = gen_rpc:call(?NODE, erlang, throw, ['throwXdown']),
    ok = ct:pal("Result [call_mfa_undef]: signal=EXIT Reason={throwXdown}").

call_with_receive_timeout(_Config) ->
    {badrpc, timeout} = gen_rpc:call(?NODE, timer, sleep, [500], 1),
    ok = timer:sleep(500).

interleaved_call(_Config) ->
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
    true = gen_rpc:cast(?NODE, erlang, timestamp).

cast_anonymous_function(_Config) ->
    true = gen_rpc:cast(?NODE, erlang, apply, [fun() -> os:timestamp() end, []]).

cast_mfa_undef(_Config) ->
    true = gen_rpc:cast(?NODE, os, timestamp_undef, []).

cast_mfa_exit(_Config) ->
    true = gen_rpc:cast(?NODE, erlang, apply, [fun() -> exit(die) end, []]).

cast_mfa_throw(_Config) ->
    true = gen_rpc:cast(?NODE, erlang, throw, ['throwme']).

cast_inexistent_node(_Config) ->
    true = gen_rpc:cast(?FAKE_NODE, os, timestamp, [], 1000).

async_call(_Config) ->
    YieldKey0 = gen_rpc:async_call(?NODE, os, timestamp, []),
    {_Mega, _Sec, _Micro} = gen_rpc:yield(YieldKey0),
    NbYieldKey0 = gen_rpc:async_call(?NODE, os, timestamp, []),
    {value, {_,_,_}} = gen_rpc:nb_yield(NbYieldKey0, 10),
    YieldKey = gen_rpc:async_call(?NODE, io_lib, print, [yield_key]),
    "yield_key" = gen_rpc:yield(YieldKey),
    NbYieldKey = gen_rpc:async_call(?NODE, io_lib, print, [nb_yield_key]),
    {value, "nb_yield_key"} = gen_rpc:nb_yield(NbYieldKey, 100).

async_call_yield_reentrant(_Config) ->
    YieldKey0 = gen_rpc:async_call(?NODE, os, timestamp, []),
    {_Mega, _Sec, _Micro} = gen_rpc:yield(YieldKey0),
    Self = self(),
    Pid = erlang:spawn(fun()->
        timeout = gen_rpc:yield(YieldKey0),
        Self ! {self(), something_went_wrong}
    end),
    receive
        _ ->
            exit(got_answer_when_none_expected)
    after
        5000 ->
            true = erlang:exit(Pid, brutal_kill)
    end,
    NbYieldKey0 = gen_rpc:async_call(?NODE, os, timestamp, []),
    {value, {_,_,_}} = gen_rpc:nb_yield(NbYieldKey0, 100),
    % Verify not able to reuse Key again. Key is one time use.
    timeout = gen_rpc:nb_yield(NbYieldKey0, 10),
    YieldKey = gen_rpc:async_call(?NODE, io_lib, print, [yield_key]),
    "yield_key" = gen_rpc:yield(YieldKey),
    NbYieldKey = gen_rpc:async_call(?NODE, io_lib, print, [nb_yield_key]),
    {value, "nb_yield_key"} = gen_rpc:nb_yield(NbYieldKey, 100).

async_call_anonymous_function(_Config) ->
    YieldKey = gen_rpc:async_call(?NODE, erlang, apply, [fun(A) -> {self(), io_lib:print(A)} end,
                                  [yield_key_anonymous_func]]),
    {_, "yield_key_anonymous_func"} = gen_rpc:yield(YieldKey),
    NBYieldKey = gen_rpc:async_call(?NODE, erlang, apply,[fun(A) -> {self(), io_lib:print(A)} end,
                                    [nb_yield_key_anonymous_func]]),
    {value, {_, "nb_yield_key_anonymous_func"}} = gen_rpc:nb_yield(NBYieldKey, 100).

async_call_anonymous_undef(_Config) ->
    YieldKey = gen_rpc:async_call(?NODE, erlang, apply, [fun() -> os:timestamp_undef() end, []]),
    {badrpc, {'EXIT', {undef,[{os,timestamp_undef,[],[]},_]}}} = gen_rpc:yield(YieldKey),
    NBYieldKey = gen_rpc:async_call(?NODE, erlang, apply, [fun() -> os:timestamp_undef() end, []]),
    {value, {badrpc, {'EXIT', {undef,[{os,timestamp_undef,[],[]},_]}}}} = gen_rpc:nb_yield(NBYieldKey, 100),
    ok = ct:pal("Result [async_call_anonymous_undef]: signal=EXIT Reason={os,timestamp_undef}").

async_call_mfa_undef(_Config) ->
    YieldKey = gen_rpc:async_call(?NODE, os, timestamp_undef),
    {badrpc, {'EXIT', {undef,[{os,timestamp_undef,_,_},_]}}} = gen_rpc:yield(YieldKey),
    NBYieldKey = gen_rpc:async_call(?NODE, os, timestamp_undef),
    {value, {badrpc, {'EXIT', {undef,[{os,timestamp_undef,_,_},_]}}}} = gen_rpc:nb_yield(NBYieldKey, 100),
    ok = ct:pal("Result [async_call_mfa_undef]: signal=EXIT Reason={os,timestamp_undef}").

async_call_mfa_exit(_Config) ->
    YieldKey = gen_rpc:async_call(?NODE, erlang, exit, ['die']),
    {badrpc, {'EXIT', die}} = gen_rpc:yield(YieldKey),
    NBYieldKey = gen_rpc:async_call(?NODE, erlang, exit, ['die']),
    {value, {badrpc, {'EXIT', die}}} = gen_rpc:nb_yield(NBYieldKey, 100),
    ok = ct:pal("Result [async_call_mfa_undef]: signal=EXIT Reason={os,timestamp_undef}").

async_call_mfa_throw(_Config) ->
    YieldKey = gen_rpc:async_call(?NODE, erlang, throw, ['throwXdown']),
    'throwXdown' = gen_rpc:yield(YieldKey),
    NBYieldKey = gen_rpc:async_call(?NODE, erlang, throw, ['throwXdown']),
    {value, 'throwXdown'} = gen_rpc:nb_yield(NBYieldKey, 100),
    ok = ct:pal("Result [async_call_mfa_undef]: throw Reason={throwXdown}").

async_call_yield_timeout(_Config) ->
    NBYieldKey = gen_rpc:async_call(?NODE, timer, sleep, [100]),
    timeout = gen_rpc:nb_yield(NBYieldKey, 5),
    ok = ct:pal("Result [async_call_yield_timeout]: signal=badrpc Reason={timeout}").

async_call_nb_yield_infinity(_Config) ->
    YieldKey = gen_rpc:async_call(?NODE, timer, sleep, [100]),
    ok = gen_rpc:yield(YieldKey),
    NBYieldKey = gen_rpc:async_call(?NODE, timer, sleep, [100]),
    {value, ok} = gen_rpc:nb_yield(NBYieldKey, infinity),
    ok = ct:pal("Result [async_call_yield_infinity]: timer_sleep Result={ok}").

async_call_inexistent_node(_Config) ->
    YieldKey1 = gen_rpc:async_call(?FAKE_NODE, os, timestamp, []),
    {badrpc, _} = gen_rpc:yield(YieldKey1),
    YieldKey2 = gen_rpc:async_call(?FAKE_NODE, os, timestamp, []),
    {value, {badrpc, _}} = gen_rpc:nb_yield(YieldKey2, 10000).

client_inactivity_timeout(_Config) ->
    {_Mega, _Sec, _Micro} = gen_rpc:call(?NODE, os, timestamp),
    ok = timer:sleep(600),
    %% Lookup the client named process, shouldn't be there
    undefined = whereis(?NODE).

server_inactivity_timeout(_Config) ->
    {_Mega, _Sec, _Micro} = gen_rpc:call(?NODE, os, timestamp),
    ok = timer:sleep(600),
    %% Lookup the client named process, shouldn't be there
    [] = supervisor:which_children(gen_rpc_acceptor_sup),
    %% The server supervisor should have no children
    [] = supervisor:which_children(gen_rpc_server_sup).

random_tcp_close(_Config) ->
    {_Mega, _Sec, _Micro} = gen_rpc:call(?NODE, os, timestamp),
    ClientName = gen_rpc_helper:make_process_name("client", ?NODE),
    {_,Socket} = sys:get_state(ClientName),
    ok = gen_tcp:close(Socket),
    ok = timer:sleep(100), % Give some time to the supervisor to kill the children
    [] = gen_rpc:nodes(),
    [] = supervisor:which_children(gen_rpc_server_sup),
    [] = supervisor:which_children(gen_rpc_client_sup),
    [] = supervisor:which_children(gen_rpc_acceptor_sup).

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
    Result = gen_rpc:call(?NODE, ?MODULE, interleaved_call_executor, [Num], Timeout),
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
