%%% -*-mode:erlang;coding:utf-8;tab-width:4;c-basic-offset:4;indent-tabs-mode:()-*-
%%% ex: set ft=erlang fenc=utf-8 sts=4 ts=4 sw=4 et:
%%%
%%% Copyright 2015 Panagiotis Papadomitsos. All Rights Reserved.
%%%

-module(gen_rpc_util).
-author("Panagiotis Papadomitsos <pj@ezgr.net>").

-include("app.hrl").

-export([otp_release/0, default_tcp_opts/0, default_tcp_opts/1]).

-spec otp_release() -> pos_integer().
otp_release() ->
    try
        erlang:list_to_integer(erlang:system_info(otp_release))
    catch
        error:badarg ->
            %% Before Erlang 17, R was included in the OTP release,
            %% which would make the list_to_integer call fail.
            %% Since we only use this function to test the availability
            %% of the show_econnreset feature, 16 is good enough.
            16
    end.

%-spec default_tcp_opts() -> gen_rpc_tcp_opts().
default_tcp_opts(Default_tcp_opts) ->  
    case otp_release() >= 18 of
        true ->
            [{show_econnreset, true} | Default_tcp_opts];
        false ->
            Default_tcp_opts
    end.

default_tcp_opts() ->
    case gen_rpc_util:otp_release() >= 18 of
        true ->
            [{show_econnreset, true}|?DEFAULT_TCP_OPTS];
        false ->
            ?DEFAULT_TCP_OPTS
    end.

