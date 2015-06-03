%%% -*-mode:erlang;coding:utf-8;tab-width:4;c-basic-offset:4;indent-tabs-mode:()-*-
%%% ex: set ft=erlang fenc=utf-8 sts=4 ts=4 sw=4 et:
%%%
%%% Copyright 2015 Panagiotis Papadomitsos. All Rights Reserved.
%%%

%%% Common Test includes
-include_lib("common_test/include/ct.hrl").
%%% Include this library's name macro
-include("include/app.hrl").
%%% Application setup
-define(ctApplicationSetup(),
    [application:set_env(Application, Key, Value, [{persistent, true}]) || {Application, Key, Value} <-
        [{sync, growl, none},
        {sync, log, none},
        {sasl, errlog_type, error},
        {sasl, error_logger_mf_dir, false},
        {lager, colored, true},
        {lager, handlers, [
            {lager_console_backend, [info, {lager_default_formatter, ["[", date, " ", time, "] severity=", severity, " module=", {module, "gen_rpc"}, " pid=\"", pid, "\" ", message, "\n"]}]},
            {lager_common_test_backend, [error, {lager_default_formatter, ["[", date, " ", time, "] severity=", severity, " module=", {module, "gen_rpc"}, " pid=\"", pid, "\" ", message, "\n"]}]}
        ]}
    ]]
).