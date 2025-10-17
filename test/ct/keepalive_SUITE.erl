%%% -*-mode:erlang;coding:utf-8;tab-width:4;c-basic-offset:4;indent-tabs-mode:()-*-
%%% ex: set ft=erlang fenc=utf-8 sts=4 ts=4 sw=4 et:
%%%
%%% Copyright 2015 Panagiotis Papadomitsos. All Rights Reserved.
%%%

-module(keepalive_SUITE).
-author("Panagiotis Papadomitsos <pj@ezgr.net>").

%%% CT Macros
-include_lib("test/include/ct.hrl").

%%% Keepalive record definition (copied from gen_rpc_keepalive.erl)
-record(keepalive, {statfun :: function() | undefined,
                    statval :: integer() | undefined,
                    tsec :: integer() | undefined,
                    tmsg :: term(),
                    tref :: reference() | undefined,
                    repeat :: integer() | undefined}).

%%% No need to export anything, everything is automatically exported
%%% as part of the test profile

%%% ===================================================
%%% CT callback functions
%%% ===================================================
all() ->
    gen_rpc_test_helper:get_test_functions(?MODULE).

init_per_suite(Config) ->
    Config.

end_per_suite(_Config) ->
    ok.

init_per_testcase(_Test, Config) ->
    Config.

end_per_testcase(_Test, _Config) ->
    ok.

%%% ===================================================
%%% Test cases
%%% ===================================================
keepalive_start_disabled(_Config) ->
    %% Test starting keepalive with timeout 0 (disabled)
    StatFun = fun() -> {ok, 42} end,
    TimeoutMsg = timeout,
    {ok, KeepAlive} = gen_rpc_keepalive:start(StatFun, 0, TimeoutMsg),
    
    %% Keepalive should be empty/disabled
    #keepalive{statfun = undefined, 
               statval = undefined, 
               tsec = undefined, 
               tmsg = timeout, 
               tref = undefined, 
               repeat = undefined} = KeepAlive.

keepalive_start_enabled(_Config) ->
    %% Test starting keepalive with timeout > 0
    StatFun = fun() -> {ok, 42} end,
    TimeoutSec = 1,
    TimeoutMsg = timeout,
    {ok, KeepAlive} = gen_rpc_keepalive:start(StatFun, TimeoutSec, TimeoutMsg),
    
    %% Keepalive should be initialized
    #keepalive{statfun = StatFun, 
               statval = 42, 
               tsec = 1, 
               tmsg = timeout, 
               tref = TRef, 
               repeat = 0} = KeepAlive,
    
    %% Timer reference should be set
    true = is_reference(TRef),
    
    %% Cancel the keepalive
    ok = gen_rpc_keepalive:cancel(KeepAlive).

keepalive_start_error(_Config) ->
    %% Test starting keepalive when StatFun returns error
    StatFun = fun() -> {error, test_error} end,
    TimeoutSec = 1,
    TimeoutMsg = timeout,
    {error, test_error} = gen_rpc_keepalive:start(StatFun, TimeoutSec, TimeoutMsg).

keepalive_check_active(_Config) ->
    %% Test checking keepalive when stat changes (activity detected)
    Counter = make_ref(),
    put(Counter, 1),
    StatFun = fun() -> 
        Val = get(Counter),
        put(Counter, Val + 1),
        {ok, Val}
    end,
    TimeoutSec = 1,
    TimeoutMsg = timeout,
    {ok, KeepAlive} = gen_rpc_keepalive:start(StatFun, TimeoutSec, TimeoutMsg),
    
    %% Check should succeed as stat value changed
    {ok, NewKeepAlive} = gen_rpc_keepalive:check(KeepAlive),
    
    %% Should have new stat value and reset repeat count
    #keepalive{statval = 2, repeat = 0} = NewKeepAlive,
    
    %% Clean up
    ok = gen_rpc_keepalive:cancel(NewKeepAlive).

keepalive_check_timeout(_Config) ->
    %% Test checking keepalive when no activity (timeout)
    StatFun = fun() -> {ok, 42} end,
    TimeoutSec = 1,
    TimeoutMsg = timeout,
    {ok, KeepAlive} = gen_rpc_keepalive:start(StatFun, TimeoutSec, TimeoutMsg),
    
    %% Check should timeout as stat value hasn't changed
    {error, timeout} = gen_rpc_keepalive:check(KeepAlive),
    
    %% Clean up
    ok = gen_rpc_keepalive:cancel(KeepAlive).

keepalive_check_error(_Config) ->
    %% Test checking keepalive when StatFun returns error
    ErrCounter = make_ref(),
    put(ErrCounter, 0),
    StatFun = fun() -> 
        case get(ErrCounter) of
            0 -> 
                put(ErrCounter, 1),
                {ok, 42};
            _ -> 
                {error, stat_error}
        end
    end,
    TimeoutSec = 1,
    TimeoutMsg = timeout,
    {ok, KeepAlive} = gen_rpc_keepalive:start(StatFun, TimeoutSec, TimeoutMsg),
    
    %% Check should return error
    {error, stat_error} = gen_rpc_keepalive:check(KeepAlive),
    
    %% Clean up
    ok = gen_rpc_keepalive:cancel(KeepAlive).

keepalive_cancel(_Config) ->
    %% Test canceling keepalive
    StatFun = fun() -> {ok, 42} end,
    TimeoutSec = 1,
    TimeoutMsg = timeout,
    {ok, KeepAlive} = gen_rpc_keepalive:start(StatFun, TimeoutSec, TimeoutMsg),
    
    %% Cancel should succeed
    ok = gen_rpc_keepalive:cancel(KeepAlive),
    
    %% Cancel on empty keepalive should also succeed
    EmptyKeepAlive = #keepalive{},
    ok = gen_rpc_keepalive:cancel(EmptyKeepAlive).

keepalive_resume(_Config) ->
    %% Test resuming keepalive
    StatFun = fun() -> {ok, 42} end,
    TimeoutSec = 1,
    TimeoutMsg = timeout,
    {ok, KeepAlive} = gen_rpc_keepalive:start(StatFun, TimeoutSec, TimeoutMsg),
    
    %% Cancel first
    ok = gen_rpc_keepalive:cancel(KeepAlive),
    
    %% Resume should set new timer
    ResumedKeepAlive = gen_rpc_keepalive:resume(KeepAlive),
    #keepalive{tref = NewTRef} = ResumedKeepAlive,
    true = is_reference(NewTRef),
    
    %% Clean up
    ok = gen_rpc_keepalive:cancel(ResumedKeepAlive).