%%% -*-mode:erlang;coding:utf-8;tab-width:4;c-basic-offset:4;indent-tabs-mode:()-*-
%%% ex: set ft=erlang fenc=utf-8 sts=4 ts=4 sw=4 et:
%%%
%%% Copyright 2015 Panagiotis Papadomitsos. All Rights Reserved.
%%%

-module(dummy).
-author("Panagiotis Papadomitsos <pj@ezgr.net>").

%%% Common Test callbacks
-export([spawn_long_running/1,
         spawn_short_running/0,
         spawn_named_process/1
]).

spawn_long_running(TimeSpan) -> 
    spawn(fun() -> timer:sleep(TimeSpan) end).

spawn_short_running() -> 
    spawn(fun() -> exit(normal) end).

spawn_named_process(TimeSpan) ->
    Pid = spawn(fun () -> timer:sleep(TimeSpan) end),
    Name = atom_to_list(node()) ++ "wawawawa",
    ProcName = list_to_atom(Name),
    true = register(ProcName, Pid),
    {Pid, ProcName}.
