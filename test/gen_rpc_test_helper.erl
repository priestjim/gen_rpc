%%% -*-mode:erlang;coding:utf-8;tab-width:4;c-basic-offset:4;indent-tabs-mode:()-*-
%%% ex: set ft=erlang fenc=utf-8 sts=4 ts=4 sw=4 et:
%%%
%%% Copyright 2015 Panagiotis Papadomitsos. All Rights Reserved.
%%%
-module(gen_rpc_test_helper).
-author("Panagiotis Papadomitsos <pj@ezgr.net>").
-vsn("1.0.0").

%%% CT Macros
-include_lib("test/include/ct.hrl").

%%% Public API
-export([start_distribution/1,
        start_master/1,
        start_distributed_master/1,
        wait_until/2,
        start_slave/1,
        stop_slave/0,
        restart_application/0,
        get_cookie/1,
        set_driver_configuration/2,
        set_application_environment/1,
        store_driver_in_config/2,
        get_driver_from_config/1,
        get_test_functions/1,
        spawn_listener/3,
        spawn_listener2/5,
        wait_for_reply/1,
        wait_for_reply/2,
        terminate_process/1,
        terminate_process/2,
        get_client_pid/1,
        expect_message/2,
        expect_no_message/1,
        stub_function/0,
        ping/1]).

%%% ===================================================
%%% Public API
%%% ===================================================

%% Start target test erlang node
start_distribution(Node)->
    %% Try to spin up net_kernel
    case net_kernel:start([Node, longnames]) of
        {ok, _} ->
            {ok, {Node, started}};
        {error,{already_started, _Pid}} ->
            {ok, {Node, already_started}};
        {error, Reason} ->
            ok = ct:pal("function=start_target event=fail_start_target reason=\"~p\"", [Reason]),
            {error, Reason}
    end.

start_master(Driver) ->
    ok = set_application_environment(?MASTER),
    ok = set_driver_configuration(Driver, ?MASTER),
    %% Start lager
    {ok, _LApps} = application:ensure_all_started(lager),
    %% Start the application remotely
    {ok, _Apps} = application:ensure_all_started(?APP),
    ok.

start_slave(Driver) ->
    %% Starting a peer node with Distributed Erlang
    %% (the slave module is deprecated, peer is its replacement)
    SlaveStr = atom_to_list(?SLAVE),
    [NameStr, IpStr] = string:tokens(SlaveStr, [$@]),
    %% Peer nodes do not inherit the cookie of the node that started them
    Args = ["-setcookie", atom_to_list(erlang:get_cookie())],
    {ok, Peer, ?SLAVE} = peer:start(#{name => NameStr, host => IpStr, args => Args}),
    %% Keep the peer controller around so we can stop the node later,
    %% from any process
    ok = persistent_term:put({?MODULE, peer}, Peer),
    ok = rpc:call(?SLAVE, code, add_pathsz, [code:get_path()]),
    ok = set_application_environment(?SLAVE),
    ok = set_driver_configuration(Driver, ?SLAVE),
    %% Start lager
    {ok, _SlaveLApps} = rpc:call(?SLAVE, application, ensure_all_started, [lager]),
    %% Start the application remotely
    {ok, _SlaveApps} = rpc:call(?SLAVE, application, ensure_all_started, [?APP]),
    ok.

stop_slave() ->
    case persistent_term:get({?MODULE, peer}, undefined) of
        undefined ->
            ok;
        Peer ->
            _ = persistent_term:erase({?MODULE, peer}),
            %% The node might already be down
            try peer:stop(Peer) of
                ok -> ok
            catch
                exit:_ -> ok
            end
    end,
    ok.

set_application_environment(?MASTER) ->
    ok = lists:foreach(fun({Application, Key, Value}) ->
        ok = application:set_env(Application, Key, Value, [{persistent, true}])
    end, ?TEST_APPLICATION_ENV),
    ok;

set_application_environment(?SLAVE) ->
    ok = lists:foreach(fun({Application, Key, Value}) ->
        ok = rpc:call(?SLAVE, application, set_env, [Application, Key, Value, [{persistent, true}]])
    end, ?TEST_APPLICATION_ENV),
    ok.

set_driver_configuration(ssl, ?MASTER) ->
    Prefix = filename:join(["..", "..", ".."]),
    CertFile = filename:join([Prefix, "priv", "ec_ssl", atom_to_list(?MASTER)]),
    CaFile = filename:join([Prefix, "priv", "ec_ssl", "ca.cert.pem"]),
    ok = application:set_env(?APP, default_client_driver, ssl, [{persistent, true}]),
    ok = application:set_env(?APP, ssl_server_port, ?MASTER_PORT, [{persistent, true}]),
    ok = application:set_env(?APP, ssl_server_options, [
                             {certfile, CertFile ++ ".cert.pem"},
                             {keyfile, CertFile ++ ".key.pem"},
                             {cacertfile, CaFile}], [{persistent, true}]),
    ok = application:set_env(?APP, ssl_client_options, [
                             {certfile, CertFile ++ ".cert.pem"},
                             {keyfile, CertFile ++ ".key.pem"},
                             {cacertfile, CaFile}], [{persistent, true}]),
    ok;

set_driver_configuration(ssl, ?SLAVE) ->
    Prefix = filename:join(["..", "..", ".."]),
    CertFile = filename:join([Prefix, "priv", "ec_ssl", atom_to_list(?SLAVE)]),
    CaFile = filename:join([Prefix, "priv", "ec_ssl", "ca.cert.pem"]),
    ok = rpc:call(?SLAVE, application, set_env, [?APP, default_client_driver, ssl, [{persistent, true}]]),
    ok = rpc:call(?SLAVE, application, set_env, [?APP, ssl_server_port, ?SLAVE_PORT, [{persistent, true}]]),
    ok = rpc:call(?SLAVE, application, set_env, [?APP, ssl_server_options, [
                  {certfile, CertFile ++ ".cert.pem"},
                  {keyfile, CertFile ++ ".key.pem"},
                  {cacertfile, CaFile}], [{persistent, true}]]),
    ok = rpc:call(?SLAVE, application, set_env, [?APP, ssl_client_options, [
                  {certfile, CertFile ++ ".cert.pem"},
                  {keyfile, CertFile ++ ".key.pem"},
                  {cacertfile, CaFile}], [{persistent, true}]]),
    ok;

set_driver_configuration(tcp, ?MASTER) ->
    ok = application:set_env(?APP, default_client_driver, tcp, [{persistent, true}]),
    ok = application:set_env(?APP, tcp_server_port, ?MASTER_PORT, [{persistent, true}]),
    ok;

set_driver_configuration(tcp, ?SLAVE) ->
    ok = rpc:call(?SLAVE, application, set_env, [?APP, default_client_driver, tcp, [{persistent, true}]]),
    ok = rpc:call(?SLAVE, application, set_env, [?APP, tcp_server_port, ?SLAVE_PORT, [{persistent, true}]]),
    ok.

store_driver_in_config(Driver, State) ->
    lists:keystore(driver, 1, State, {driver,Driver}).

%% Start distributed Erlang on the local node and the application as the master
start_distributed_master(Driver) ->
    {ok, _Pid} = start_distribution(?MASTER),
    ok = start_master(Driver),
    ok.

%% Poll until the fun returns true. Returns {error,timeout} after Timeout milliseconds
-spec wait_until(fun(() -> boolean()), non_neg_integer()) -> ok | {error, timeout}.
wait_until(Fun, Timeout) when is_function(Fun, 0) ->
    wait_until(Fun, erlang:monotonic_time(millisecond) + Timeout, 20).

wait_until(Fun, Deadline, Interval) ->
    case Fun() of
        true ->
            ok;
        false ->
            case erlang:monotonic_time(millisecond) >= Deadline of
                true ->
                    {error, timeout};
                false ->
                    ok = timer:sleep(Interval),
                    wait_until(Fun, Deadline, Interval)
            end
    end.

restart_application() ->
    _ = application:stop(?APP),
    _ = application:unload(?APP),
    ok = timer:sleep(100),
    {ok, _LApps} = application:ensure_all_started(lager),
    {ok, _Apps} = application:ensure_all_started(?APP),
    ok.

get_test_functions(Module) ->
    {exports, Functions} = lists:keyfind(exports, 1, Module:module_info()),
    [FName || {FName, _} <- lists:filter(
                               fun ({module_info,_}) -> false;
                                   ({all,_}) -> false;
                                   %% Every exported function with an arity of 1 is a test case
                                   %% except for the callbacks and the auxiliary functions of the suites
                                   ({init_per_suite,_}) -> false;
                                   ({end_per_suite,_}) -> false;
                                   %% Local tests
                                   ({interleaved_call_executor,_}) -> false;
                                   ({get_config,_}) -> false;
                                   %% Monitor
                                   ({kill_client,_}) -> false;
                                   ({wait_until_state_is_empty,_}) -> false;
                                   %% Cookie per node
                                   ({to_config,_}) -> false;
                                   %% Else
                                   ({_,1}) -> true;
                                   ({_,_}) -> false
                               end, Functions)].

get_driver_from_config(Config) ->
    case lists:keyfind(driver, 1, Config) of
        false -> ?DEFAULT_DRIVER;
        {driver, Driver} -> Driver
    end.

stub_function() ->
  stub_function.

%% Callback for the external cookie per node configuration
get_cookie(_Node) ->
    external_test_cookie.

ping({Node, Process, Msg}) ->
    {Process, Node} ! {pong, {node(), Process, Msg}}.

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
            after
                0 ->
                    {error, no_reply}
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
            after
                0 ->
                    {error, no_reply}
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

%% Returns the pid of the client process of a node
get_client_pid(NodeOrTuple) ->
    erlang:whereis(gen_rpc_helper:make_process_name("client", NodeOrTuple)).

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
