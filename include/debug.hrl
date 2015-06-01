%%% -*-mode:erlang;coding:utf-8;tab-width:4;c-basic-offset:4;indent-tabs-mode:()-*-
%%% ex: set ft=erlang fenc=utf-8 sts=4 ts=4 sw=4 et:
%%%
%%% Copyright 2015 Panagiotis Papadomitsos, Inc. All Rights Reserved.
%%%

-ifdef(DEBUG).
-define(debug(Msg), io:format(standard_error, "[DEBUG][~p:~p] " ++ Msg ++ "~n", [?MODULE, ?LINE])).
-define(debug(Msg, Args), io:format(standard_error, "[DEBUG][~p:~p] " ++ Msg ++ "~n", [?MODULE, ?LINE] ++ Args)).
-else.
-define(debug(Msg), ok).
-define(debug(Msg, Args), ok).
-endif.
