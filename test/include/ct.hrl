%%% -*-mode:erlang;coding:utf-8;tab-width:4;c-basic-offset:4;indent-tabs-mode:()-*-
%%% ex: set ft=erlang fenc=utf-8 sts=4 ts=4 sw=4 et:
%%%
%%% Copyright 2015 Panagiotis Papadomitsos. All Rights Reserved.
%%%

%%% Common Test includes
-include_lib("common_test/include/ct.hrl").
%%% Include this library's name macro
-include_lib("gen_rpc/include/app.hrl").

%%% Node definitions
-define(NODE, 'gen_rpc_master@127.0.0.1').
-define(SLAVE, 'gen_rpc_slave@127.0.0.1').
-define(SLAVE1, 'gen_rpc_slave1@127.0.0.1').
-define(SLAVE2, 'gen_rpc_slave2@127.0.0.1').

-define(FAKE_NODE, 'fake_node@1.2.3.4').
-define(TEST_APPLICATION_ENV, [{sasl, errlog_type, error},
        {sasl, error_logger_mf_dir, false},
        {gen_rpc, connect_timeout, 500},
        {gen_rpc, send_timeout, 500},
        {lager, colored, true},
        {lager, handlers, [
            % Commented out to reduce test output polution, uncomment during development
            % {lager_common_test_backend, [debug,
            %     {lager_default_formatter, ["[", date, " ", time, "] severity=", severity, " node=\"", {node, "undefined"}, "\" pid=\"", pid,
            %         "\" module=", {module, "gen_rpc"}, " function=", {function, "undefined"}, " ", message, "\n"]}]},
            {lager_file_backend, [{file, "messages.log"}, {level, debug}, {formatter, lager_default_formatter}, {size, 0}, {date, "$D0"}, {count, 7},
                {formatter_config, ["[", date, " ", time, "] severity=", severity, " node=\"", {node, "undefined"}, "\" pid=\"", pid,
                    "\" module=", {module, "gen_rpc"}, " function=", {function, "undefined"}, " ", message, "\n"]}]}
        ]}
]).