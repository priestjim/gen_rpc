%%% -*-mode:erlang;coding:utf-8;tab-width:4;c-basic-offset:4;indent-tabs-mode:()-*-
%%% ex: set ft=erlang fenc=utf-8 sts=4 ts=4 sw=4 et:
%%%
%%% Copyright 2015 Panagiotis Papadomitsos. All Rights Reserved.
%%%
-module(gen_rpc_test_helper).
-author("Panagiotis Papadomitsos <pj@ezgr.net>").

%%% CT Macros
-include_lib("test/include/ct.hrl").

%%% Public API
-export([start_distribution/1,
        start_slave/1,
        set_application_environment/0,
        get_test_functions/1,
        make_process_name/1,
        make_process_name/2,
        spawn_long_running/1,
        spawn_short_running/0,
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
            ok = ct:pal("function=start_target event=fail_start_target Reason=\"~p\"", [Reason]),
            {error, Reason}
    end.

start_slave(Slave) ->
    %% Starting a slave node with Distributed Erlang
    SlaveStr = atom_to_list(Slave),
    [NameStr, IpStr] = string:tokens(SlaveStr, "@"),
    Name = list_to_atom(NameStr),
    {ok, _Slave} = slave:start(IpStr, Name, "+K true"),
    ok = rpc:call(Slave, code, add_pathsz, [code:get_path()]),
    %% Start the application remotely
    {ok, _SlaveApps} = rpc:call(Slave, application, ensure_all_started, [?APP]),
    ok.

stop_slave(Slave) ->
    ok = slave:stop(Slave),
    ok.

set_application_environment() ->
    _ = [application:set_env(Application, Key, Value, [{persistent, true}]) || {Application, Key, Value} <-
        [{sasl, errlog_type, error},
        {sasl, error_logger_mf_dir, false},
        {gen_rpc, connect_timeout, 500},
        {gen_rpc, send_timeout, 500},
        {lager, colored, true},
        {lager, handlers, [
            {lager_console_backend, [notice, {lager_default_formatter, ["[", date, " ", time, "] severity=", severity, " module=", {module, "gen_rpc"}, " pid=\"", pid, "\" ", message, "\n"]}]},
            {lager_common_test_backend, [notice, {lager_default_formatter, ["[", date, " ", time, "] severity=", severity, " module=", {module, "gen_rpc"}, " pid=\"", pid, "\" ", message, "\n"]}]}
        ]}
    ]],
    ok.

restart_application() ->
    ok = application:stop(?APP),
    ok = application:unload(?APP),
    ok = application:start(?APP),
    ok.

get_test_functions(Module) ->
    {exports, Functions} = lists:keyfind(exports, 1, Module:module_info()),
    [FName || {FName, _} <- lists:filter(
                               fun ({module_info,_}) -> false;
                                   ({all,_}) -> false;
                                   ({init_per_suite,1}) -> false;
                                   ({end_per_suite,1}) -> false;
                                   ({interleaved_call_proc,3}) -> false;
                                   ({wait_for_reply,1}) -> false;
                                   ({terminate_process,1}) -> false;
                                   ({interleaved_call_executor,1}) -> false;
                                   ({_,1}) -> true;
                                   ({_,_}) -> false
                               end, Functions)].

make_process_name(Tag) ->
    make_process_name(node(), Tag).

make_process_name(Node, Tag) when is_binary(Tag) ->
    NodeBin = atom_to_binary(Node, utf8),
    binary_to_atom(<<Tag/binary, NodeBin/binary>>, utf8).
spawn_long_running(TimeSpan) ->
    spawn(fun() -> timer:sleep(TimeSpan) end).

spawn_short_running() ->
    spawn(fun() -> exit(normal) end).

ping({Node, Process, Msg}) ->
    {Process, Node} ! {'pong', {node(), Process, Msg}}.
