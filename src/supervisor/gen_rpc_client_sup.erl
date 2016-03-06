%%% -*-mode:erlang;coding:utf-8;tab-width:4;c-basic-offset:4;indent-tabs-mode:()-*-
%%% ex: set ft=erlang fenc=utf-8 sts=4 ts=4 sw=4 et:
%%%
%%% Copyright 2015 Panagiotis Papadomitsos. All Rights Reserved.
%%%

-module(gen_rpc_client_sup).
-author("Panagiotis Papadomitsos <pj@ezgr.net>").

%%% Behaviour
-behaviour(supervisor).

%%% Supervisor functions
-export([start_link/0, start_child/1, stop_child/1, children_names/0]).

%%% Supervisor callbacks
-export([init/1]).

%%% ===================================================
%%% Supervisor functions
%%% ===================================================
-spec start_link() -> supervisor:startlink_ret().
start_link() ->
    supervisor:start_link({local, ?MODULE}, ?MODULE, []).

-spec start_child(Node::node()) ->  supervisor:startchild_ret().
start_child(Node) when is_atom(Node) ->
    ok = lager:debug("event=starting_new_client server_node=\"~s\"", [Node]),
    case supervisor:start_child(?MODULE, [Node]) of
        {error, {already_started, CPid}} ->
            %% If we've already started the child, terminate it and start anew
            ok = stop_child(CPid),
            supervisor:start_child(?MODULE, [Node]);
        {error, OtherError} ->
            {error, OtherError};
        {ok, Pid} ->
            {ok, Pid}
    end.

-spec stop_child(Pid::pid()) ->  'ok'.
stop_child(Pid) when is_pid(Pid) ->
    ok = lager:debug("event=stopping_client client_pid=\"~p\"", [Pid]),
    _ = supervisor:terminate_child(?MODULE, Pid),
    _ = supervisor:delete_child(?MODULE, Pid),
    ok.

-spec children_names() -> list().
children_names() ->
    lists:foldl(fun({_,Pid,_,_}, Acc) ->
        {_, Name} = erlang:process_info(Pid, registered_name),
        case Name of
            Name when Name =:= node() -> Acc; %% Skip the local node
            _Else -> [Name|Acc]
        end
    end, [], supervisor:which_children(?MODULE)).

%%% ===================================================
%%% Supervisor callbacks
%%% ===================================================
init([]) ->
    {ok, {{simple_one_for_one, 100, 1}, [
        {gen_rpc_client, {gen_rpc_client,start_link,[]}, temporary, 5000, worker, [gen_rpc_client]}
    ]}}.
