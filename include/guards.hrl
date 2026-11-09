%%% -*-mode:erlang;coding:utf-8;tab-width:4;c-basic-offset:4;indent-tabs-mode:()-*-
%%% ex: set ft=erlang fenc=utf-8 sts=4 ts=4 sw=4 et:
%%%
%%% Copyright 2015 Panagiotis Papadomitsos. All Rights Reserved.
%%%

-define(is_timeout(A), (is_integer(A) andalso A >= 0) orelse A =:= infinity).
-define(is_node_or_tuple(A), is_atom(A) orelse is_tuple(A)).
