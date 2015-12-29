%%% -*-mode:erlang;coding:utf-8;tab-width:4;c-basic-offset:4;indent-tabs-mode:()-*-
%%% ex: set ft=erlang fenc=utf-8 sts=4 ts=4 sw=4 et:
%%%
%%% Copyright 2015 Panagiotis Papadomitsos. All Rights Reserved.
%%%

-module(local_functional_SUITE).
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
    ok = ct:pal("Started [local_functional] suite with master node [~s]", [node()]),
    Config.

end_per_suite(_Config) ->
    ok.

init_per_testcase(client_inactivity_timeout, Config) ->
    ok = gen_rpc_test_helper:restart_application(),
    ok = application:set_env(?APP, client_inactivity_timeout, 500),
    Config;

init_per_testcase(server_inactivity_timeout, Config) ->
    ok = gen_rpc_test_helper:restart_application(),
    ok = application:set_env(?APP, server_inactivity_timeout, 500),
    Config;

init_per_testcase(remote_node_call, Config) ->
    ok = gen_rpc_test_helper:start_slave(?SLAVE),
    Config;

init_per_testcase(_OtherTest, Config) ->
    Config.

end_per_testcase(client_inactivity_timeout, Config) ->
    ok = gen_rpc_test_helper:restart_application(),
    ok = application:set_env(?APP, client_inactivity_timeout, infinity),
    Config;

end_per_testcase(server_inactivity_timeout, Config) ->
    ok = gen_rpc_test_helper:restart_application(),
    ok = application:set_env(?APP, server_inactivity_timeout, infinity),
    Config;

end_per_testcase(remote_node_call, Config) ->
    ok = gen_rpc_test_helper:stop_slave(?SLAVE),
    Config;

end_per_testcase(_OtherTest, Config) ->
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
block_call(_Config) ->
    ok = ct:pal("Testing [block_call]"),
    RevTO = 200,
    {_Mega, _Sec, _Micro} = gen_rpc:block_call(?NODE, os, timestamp, RevTO).

block_call_mfa(_Config) ->
    ok = ct:pal("Testing [block_call_mfa]"),
    SendTO = RevTO = 200,
    true = gen_rpc:block_call(?NODE, erlang, is_process_alive, [whereis(gen_rpc_client_sup)], RevTO, SendTO).

block_call_anonymous_function(_Config) ->
    ok = ct:pal("Testing [block_call_anonymous_function]"),
    RevTO = 200,
    {_,"\"block_call_anonymous_function\""} = gen_rpc:block_call(?NODE, erlang, apply,[fun(A) -> {self(), io_lib:print(A)} end,                                                     ["block_call_anonymous_function"]], RevTO).

block_call_anonymous_undef(_Config) ->
    ok = ct:pal("Testing [block_call_anonymous_undef]"),
    ok = ct:pal("Testing [block_call_anonymous_undef] Assumping stackstack depth is 5"),
    RevTO = 200,
    {badrpc, {'EXIT', {undef,[{os,timestamp_undef,[],[]},_]}}}  = gen_rpc:block_call(?NODE, erlang, apply, [fun() -> os:timestamp_undef() end, []], RevTO),
   ok = ct:pal("Result [block_call_anonymous_undef]: signal=EXIT Reason={os,timestamp_undef}").

block_call_mfa_undef(_Config) ->
    ok = ct:pal("Testing [block_call_mfa_undef]"),
    RevTO = 200,
    {badrpc, {'EXIT', {undef,[{os,timestamp_undef,_,_},_]}}} = gen_rpc:block_call(?NODE, os, timestamp_undef, RevTO),
    ok = ct:pal("Result [block_call_mfa_undef]: signal=EXIT Reason={os,timestamp_undef}").

block_call_mfa_exit(_Config) ->
    ok = ct:pal("Testing [block_call_mfa_exit]"),
    RevTO = 200,
    {badrpc, {'EXIT', die}} = gen_rpc:block_call(?NODE, erlang, exit, ['die'], RevTO),
    ok = ct:pal("Result [block_call_mfa_undef]: signal=EXIT Reason={die}").

block_call_mfa_throw(_Config) ->
    ok = ct:pal("Testing [block_call_mfa_throw]"),
    RevTO = 200,
    'throwXdown' = gen_rpc:block_call(?NODE, erlang, throw, ['throwXdown'], RevTO),
    ok = ct:pal("Result [block_call_mfa_undef]: signal=EXIT Reason={die}").

block_call_with_receive_timeout(_Config) ->
    ok = ct:pal("Testing [block_call_with_receive_timeout]"),
    RevTO = 1,
    {badrpc, timeout} = gen_rpc:block_call(?NODE, timer, sleep, [500], RevTO),
    ok = timer:sleep(500).

call(_Config) ->
    ok = ct:pal("Testing [call]"),
    {_Mega, _Sec, _Micro} = gen_rpc:call(?NODE, os, timestamp).

call_anonymous_function(_Config) ->
    ok = ct:pal("Testing [call_anonymous_function]"),
    {_,"\"call_anonymous_function\""} = gen_rpc:call(?NODE, erlang, apply,[fun(A) -> {self(), io_lib:print(A)} end,
                                                     ["call_anonymous_function"]]).

call_anonymous_undef(_Config) ->
    ok = ct:pal("Testing [call_anonymous_undef]"),
    ok = ct:pal("Testing [call_anonymous_undef] assuming stackstack depth of 5"),
    {badrpc, {'EXIT', {undef,[{os,timestamp_undef,[],[]},_]}}}  = gen_rpc:call(?NODE, erlang, apply, [fun() -> os:timestamp_undef() end, []]),
   ok = ct:pal("Result [call_anonymous_undef]: signal=EXIT Reason={os,timestamp_undef}").

call_mfa_undef(_Config) ->
    ok = ct:pal("Testing [call_mfa_undef]"),
    {badrpc, {'EXIT', {undef,[{os,timestamp_undef,_,_},_]}}} = gen_rpc:call(?NODE, os, timestamp_undef),
    ok = ct:pal("Result [call_mfa_undef]: signal=EXIT Reason={os,timestamp_undef}").

call_mfa_exit(_Config) ->
    ok = ct:pal("Testing [call_mfa_exit]"),
    {badrpc, {'EXIT', die}} = gen_rpc:call(?NODE, erlang, exit, ['die']),
    ok = ct:pal("Result [call_mfa_undef]: signal=EXIT Reason={die}").

call_mfa_throw(_Config) ->
    ok = ct:pal("Testing [call_mfa_throw]"),
    'throwXdown' = gen_rpc:call(?NODE, erlang, throw, ['throwXdown']),
    ok = ct:pal("Result [call_mfa_undef]: signal=EXIT Reason={die}").

call_with_receive_timeout(_Config) ->
    ok = ct:pal("Testing [call_with_receive_timeout]"),
    {badrpc, timeout} = gen_rpc:call(?NODE, timer, sleep, [500], 1),
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
    true = gen_rpc:cast(?NODE, erlang, timestamp).

cast_anonymous_function(_Config) ->
    ok = ct:pal("Testing [cast_anonymous_function]"),
    true = gen_rpc:cast(?NODE, erlang, apply, [fun() -> os:timestamp() end, []]).

cast_mfa_undef(_Config) ->
    ok = ct:pal("Testing [cast_mfa_undef]"),
    true = gen_rpc:cast(?NODE, os, timestamp_undef, []).

cast_mfa_exit(_Config) ->
    ok = ct:pal("Testing [cast_mfa_exit]"),
    true = gen_rpc:cast(?NODE, erlang, apply, [fun() -> exit(die) end, []]).

cast_mfa_throw(_Config) ->
    ok = ct:pal("Testing [cast_mfa_throw]"),
    true = gen_rpc:cast(?NODE, erlang, throw, ['throwme']).

cast_inexistent_node(_Config) ->
    ok = ct:pal("Testing [cast_inexistent_node]"),
    true = gen_rpc:cast(?FAKE_NODE, os, timestamp, [], 1000).

pinfo_alive_process(_Config) ->
    ok = ct:pal("Testing [pinfo]"),
    Pid = gen_rpc:call(?NODE, erlang, spawn, [fun() -> timer:sleep(100000) end]),
    % If this process is alive when pinfo it, we should get non-empty list
    true = erlang:is_process_alive(Pid),
    [] =/= gen_rpc:pinfo(Pid).

pinfo_dead_process(_Config) ->
    ok = ct:pal("Testing [pinfo]"),
    Pid = gen_rpc:call(?NODE, erlang, spawn, [fun() -> exit(normal) end]),
    % If this process is dead when pinfo it, we should get undefined.
    false = gen_rpc:call(?NODE, erlang, is_process_alive, [Pid]),
    'undefined' = gen_rpc:pinfo(Pid).

pinfo_item(_Config) ->
    ok = ct:pal("Testing [pinfo_item]"),
    Pid = gen_rpc:call(?NODE, erlang, spawn, [fun() -> timer:sleep(100000) end]),
    % If this process is alive when pinfo it, we should get non-empty list
    true = gen_rpc:call(?NODE, erlang, is_process_alive, [Pid]),
    [{status,waiting}] = gen_rpc:pinfo(Pid, [status]).

safe_cast(_Config) ->
    ok = ct:pal("Testing [safe_cast]"),
    true = gen_rpc:safe_cast(?NODE, erlang, timestamp).

safe_cast_anonymous_function(_Config) ->
    ok = ct:pal("Testing [safe_cast_anonymous_function]"),
    true = gen_rpc:safe_cast(?NODE, erlang, apply, [fun() -> os:timestamp() end, []]).

safe_cast_mfa_undef(_Config) ->
    ok = ct:pal("Testing [safe_cast_mfa_undef]"),
    true = gen_rpc:safe_cast(?NODE, os, timestamp_undef, []).

safe_cast_mfa_exit(_Config) ->
    ok = ct:pal("Testing [safe_cast_mfa_exit]"),
    true = gen_rpc:safe_cast(?NODE, erlang, apply, [fun() -> exit(die) end, []]).

safe_cast_mfa_throw(_Config) ->
    ok = ct:pal("Testing [safe_cast_mfa_throw]"),
    true = gen_rpc:safe_cast(?NODE, erlang, throw, ['throwme']).

safe_cast_inexistent_node(_Config) ->
    ok = ct:pal("Testing [safe_cast_inexistent_node]"),
    {badrpc, nodedown} = gen_rpc:safe_cast(?FAKE_NODE, os, timestamp, [], 1000).

client_inactivity_timeout(_Config) ->
    ok = ct:pal("Testing [client_inactivity_timeout]"),
    {_Mega, _Sec, _Micro} = gen_rpc:call(?NODE, os, timestamp),
    ok = timer:sleep(600),
    %% Lookup the client named process, shouldn't be there
    undefined = whereis(?NODE).

server_inactivity_timeout(_Config) ->
    ok = ct:pal("Testing [server_inactivity_timeout]"),
    {_Mega, _Sec, _Micro} = gen_rpc:call(?NODE, os, timestamp),
    ok = timer:sleep(600),
    %% Lookup the client named process, shouldn't be there
    [] = supervisor:which_children(gen_rpc_acceptor_sup),
    %% The server supervisor should have no children
    [] = supervisor:which_children(gen_rpc_server_sup).

remote_node_call(_Config) ->
    ok = ct:pal("Testing [remote_node_call]"),
    {_Mega, _Sec, _Micro} = gen_rpc:call(?SLAVE, os, timestamp).

compat_call(_Config) ->
    ok = ct:pal("Testing [compat_call]"),
    {ok, _Port} = 'Elixir.ExRPC.Supervisor.Server':start_child(?NODE),
    ServerProc = gen_rpc_helper:make_process_name(server, ?NODE),
    ServerPid = whereis(ServerProc),
    ok = gen_rpc_server_sup:stop_child(ServerPid).

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
