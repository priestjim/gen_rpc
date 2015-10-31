%%% -*-mode:erlang;coding:utf-8;tab-width:4;c-basic-offset:4;indent-tabs-mode:()-*-
%%% ex: set ft=erlang fenc=utf-8 sts=4 ts=4 sw=4 et:
%%%
%%% Copyright 2015 Panagiotis Papadomitsos. All Rights Reserved.
%%%

-module(gen_rpc_helper).
-author("Panagiotis Papadomitsos <pj@ezgr.net>").

-include("app.hrl").

-export([otp_release/0, default_tcp_opts/1, make_process_name/2]).

-spec otp_release() -> integer().
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

-spec default_tcp_opts(gen_tcp:option()) ->  gen_tcp:option().
default_tcp_opts(DefaultTcpOpts) ->
    case otp_release() >= 18 of
        true ->
            [{show_econnreset, true}|DefaultTcpOpts];
        false ->
            DefaultTcpOpts
    end.

-spec make_process_name(binary(), node()) -> atom().
make_process_name(Prefix, Node) when is_binary(Prefix), is_atom(Node)->
    NodeBin = atom_to_binary(Node, latin1),
    binary_to_atom( <<Prefix/binary, NodeBin/binary>>, latin1).

