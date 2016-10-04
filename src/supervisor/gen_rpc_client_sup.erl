%%% -*-mode:erlang;coding:utf-8;tab-width:4;c-basic-offset:4;indent-tabs-mode:()-*-
%%% ex: set ft=erlang fenc=utf-8 sts=4 ts=4 sw=4 et:
%%%
%%% Copyright 2015 Panagiotis Papadomitsos. All Rights Reserved.
%%%

-module(gen_rpc_client_sup).
-author("Panagiotis Papadomitsos <pj@ezgr.net>").

%%% Behaviour
-behaviour(supervisor).

%%% Include the HUT library
-include_lib("hut/include/hut.hrl").

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

-spec start_child(node()) -> supervisor:startchild_ret().
start_child(Node) when is_atom(Node) ->
    ?log(debug, "event=starting_new_client server_node=\"~s\"", [Node]),
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

-spec stop_child(pid()) -> ok.
stop_child(Pid) when is_pid(Pid) ->
    ?log(debug, "event=stopping_client client_pid=\"~p\"", [Pid]),
    _ = supervisor:terminate_child(?MODULE, Pid),
    ok.

-spec children_names() -> list().
children_names() ->
    NodePid = gen_rpc_helper:make_process_name("client", node()),
    lists:foldl(fun({_,Pid,_,_}, Acc) ->
        case erlang:process_info(Pid, registered_name) of
            undefined ->
                %% Process was killed while traversing the children, skip
                Acc;
            {_, Name} ->
                case Name of
                    Name when Name =:= NodePid -> Acc; %% Skip the local node
                    _Else -> [gen_rpc_helper:extract_node_name(Name)|Acc]
                end
        end
    end, [], supervisor:which_children(?MODULE)).

%%% ===================================================
%%% Supervisor callbacks
%%% ===================================================
init([]) ->
    {ok, {{simple_one_for_one, 100, 1}, [
        {gen_rpc_client, {gen_rpc_client,start_link,[]}, temporary, 5000, worker, [gen_rpc_client]}
    ]}}.
