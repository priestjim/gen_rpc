%%% -*-mode:erlang;coding:utf-8;tab-width:4;c-basic-offset:4;indent-tabs-mode:()-*-
%%% ex: set ft=erlang fenc=utf-8 sts=4 ts=4 sw=4 et:
%%%
%%% Copyright 2015 Panagiotis Papadomitsos. All Rights Reserved.
%%%
-module(gen_rpc_test_helper).
-author("Panagiotis Papadomitsos <pj@ezgr.net>").

%%% CT Macros
-include_lib("test/gen_rpc/include/ct.hrl").

-export([start_target/1, make_process_name/1, make_process_name/2, ping/1]).
-export([spawn_long_running/1, spawn_short_running/0]).

%% Start target test erlang node
start_target(Node)->
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

spawn_long_running(TimeSpan) -> 
    spawn(fun() -> timer:sleep(TimeSpan) end).

spawn_short_running() -> 
    spawn(fun() -> exit(normal) end).

make_process_name(Tag) -> make_process_name(node(), Tag).

make_process_name(Node, Tag) when is_binary(Tag) ->
    NodeBin = atom_to_binary(Node, latin1),
    binary_to_atom(<<Tag/binary, NodeBin/binary>>, latin1).

ping({Node, Process, Msg}) ->
    {Process, Node} ! {'pong', {node(), Process, Msg}}.
