%%% -*-mode:erlang;coding:utf-8;tab-width:4;c-basic-offset:4;indent-tabs-mode:()-*-
%%% ex: set ft=erlang fenc=utf-8 sts=4 ts=4 sw=4 et:
%%%
%%% Copyright 2015 Panagiotis Papadomitsos. All Rights Reserved.
%%%

%%% Debug logging for the hot paths. When hut falls back to the logger it builds
%%% the arguments of every ?log call even if the level is disabled, which is
%%% noticeable for the debug lines that run on each RPC. This only evaluates the
%%% arguments if debug logging is enabled. The other hut backends (lager, etc.)
%%% already evaluate the arguments lazily.
%%% Include after hut.hrl
-if(?log_type =:= "logger").
-define(log_debug(__Fmt),
        ?log_debug(__Fmt, [])).
-define(log_debug(__Fmt, __Args),
        case logger:allow(debug, ?MODULE) of
            true -> ?log(debug, __Fmt, __Args);
            false -> ok
        end).
-else.
-define(log_debug(__Fmt),
        ?log(debug, __Fmt)).
-define(log_debug(__Fmt, __Args),
        ?log(debug, __Fmt, __Args)).
-endif.
