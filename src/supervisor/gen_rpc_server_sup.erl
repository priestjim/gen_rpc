%%% -*-mode:erlang;coding:utf-8;tab-width:4;c-basic-offset:4;indent-tabs-mode:()-*-
%%% ex: set ft=erlang fenc=utf-8 sts=4 ts=4 sw=4 et:
%%%
%%% Copyright 2015 Panagiotis Papadomitsos. All Rights Reserved.
%%%

-module(gen_rpc_server_sup).
-author("Panagiotis Papadomitsos <pj@ezgr.net>").

%%% Behaviour
-behaviour(supervisor).

%%% Supervisor functions
-export([start_link/0, start_child/1, stop_child/1]).

%%% Supervisor callbacks
-export([init/1]).

%%% ===================================================
%%% Supervisor functions
%%% ===================================================
start_link() ->
    supervisor:start_link({local, ?MODULE}, ?MODULE, []).

%% Launch a local receiver and return the port
-spec start_child(Node::node()) -> {'ok', inet:port_number()} | {ok, _}.
start_child(Node) when is_atom(Node) ->
    ok = lager:debug("function=start_child event=starting_new_server client_node=\"~s\"", [Node]),
    {ok, Pid} = supervisor:start_child(?MODULE, [Node]),
    {ok, Port} = gen_rpc_server:get_port(Pid),
    {ok, Port}.

%% Terminate and unregister a child server
-spec stop_child(Pid::pid()) -> 'ok'.
stop_child(Pid) when is_pid(Pid) ->
    ok = lager:debug("function=stop_child event=stopping_server server_pid=\"~p\"", [Pid]),
    _ = supervisor:terminate_child(?MODULE, Pid),
    _ = supervisor:delete_child(?MODULE, Pid),
    ok.


%%% ===================================================
%%% Supervisor callbacks
%%% ===================================================
init([]) ->
    {ok, {{simple_one_for_one, 100, 1}, [
        {gen_rpc_server, {gen_rpc_server,start_link,[]}, transient, 5000, worker, [gen_rpc_server]}
    ]}}.
