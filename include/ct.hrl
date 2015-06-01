%%% -*-mode:erlang;coding:utf-8;tab-width:4;c-basic-offset:4;indent-tabs-mode:()-*-
%%% ex: set ft=erlang fenc=utf-8 sts=4 ts=4 sw=4 et:
%%%
%%% Copyright 2015 Panagiotis Papadomitsos, Inc. All Rights Reserved.
%%%

%%% Common Test includes
-include_lib("common_test/include/ct.hrl").

-define(ctApplicationSetup(),
    [application:set_env(Application, Key, Value) || {Application, Key, Value} <-
        [{sync, growl, none},
        {sync, log, none}]]
).