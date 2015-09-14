%%% -*-mode:erlang;coding:utf-8;tab-width:4;c-basic-offset:4;indent-tabs-mode:()-*-
%%% ex: set ft=erlang fenc=utf-8 sts=4 ts=4 sw=4 et:
%%%
%%% Copyright 2015 Panagiotis Papadomitsos. All Rights Reserved.
%%%

-module(simple_request_reply_SUITE).
-author("Panagiotis Papadomitsos <pj@ezgr.net>").

-include_lib("gen_rpc_common_test.hrl").

%%% Common Test callbacks
-export([all/0, groups/0, 
         init_per_suite/1, end_per_suite/1,
         init_per_group/1, end_per_group/1,
         init_per_testcase/2, end_per_testcase/2
        ]).

%%% Testing functions
-export([check_remote_nodes_up/0, check_remote_nodes_tear_down/0,
         call_mod_func/0, call_mod_func_arg/0,
         call_anonymous_func/0, call_bad_module/0,
         call_bad_function/0, call_infinite_loop/0
        ]).

all() -> 
    [ 
     check_remote_nodes_up,        % Check sender able to receive result post remote execution
     {group, verify_execute},      % Tests function with or without arguments are executed 
     {group, verify_execute_failure}, % Tests sender receive proper message on bad remote call
     check_remote_nodes_tear_down     % Remote nodes are gone
    ].

groups() -> [
             {verify_execute, [sequence],
                 [call_mod_func, call_mod_func_arg, call_anonymous_func] },
             {verify_execute_failure, [sequence], 
                 [call_bad_module, call_bad_function, call_infinite_loop] }
    ].

init_per_group(Config) -> Config.
end_per_group(Config) -> Config.

init_per_suite(Config) -> Config.
end_per_suite(Config) -> Config.

init_per_testcase(_Test_Case, Config) ->
    ok = ?restart_application(),
    Config.

end_per_testcase(_Test_Case, Config) ->
    Config.

%%% ===================================================
%%% Test cases
%%% ===================================================
%% Test supervisor's status
call_mod_func() -> true.

call_mod_func_arg() -> true. 
call_anonymous_func() -> true.

call_bad_module() -> true.
call_bad_function() -> true.
call_infinite_loop() -> true.

%%% ===================================================
%%% Helper Functions
%%% ===================================================
check_remote_nodes_up() -> true.

check_remote_nodes_tear_down() -> true.
