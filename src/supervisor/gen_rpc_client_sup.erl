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
%%% Include the debug logging macros
-include("logging.hrl").
%%% Include helpful guard macros
-include("guards.hrl").
%%% Include helpful types
-include("types.hrl").

%%% Supervisor functions
-export([start_link/0]).

%%% API functions
-export([nodes/0, start_child/2, stop_child/1]).

%%% Supervisor callbacks
-export([init/1]).

%%% ===================================================
%%% Supervisor functions
%%% ===================================================
-spec start_link() -> supervisor:startlink_ret().
start_link() ->
    supervisor:start_link({local, ?MODULE}, ?MODULE, []).

-spec start_child(node_or_tuple(), {atom(), term()}) -> supervisor:startchild_ret().
start_child(NodeOrTuple, {Driver, _Socket} = Connection) when ?is_node_or_tuple(NodeOrTuple), is_atom(Driver) ->
    ?log_debug("event=starting_new_client target=\"~p\"", [NodeOrTuple]),
    case supervisor:start_child(?MODULE, [NodeOrTuple, Connection]) of
        {error, {already_started, CPid}} ->
            %% If we've already started the child, terminate it and start anew
            ok = stop_child(CPid),
            supervisor:start_child(?MODULE, [NodeOrTuple, Connection]);
        Other ->
            Other
    end.

-spec stop_child(pid()) -> ok.
stop_child(Pid) when is_pid(Pid) ->
    ?log_debug("event=stopping_client client_pid=\"~p\"", [Pid]),
    _ = supervisor:terminate_child(?MODULE, Pid),
    ok.

-spec nodes() -> list().
nodes() ->
    Node = node(),
    NodeList = lists:foldl(fun({_,Pid,_,_}, Acc) ->
        case erlang:process_info(Pid, registered_name) of
            undefined ->
                %% Process was killed while traversing the children, skip
                Acc;
            {_, Name} ->
                case extract_node_name(erlang:atom_to_list(Name)) of
                    Node -> Acc; %% Skip the local node
                    NodeName -> [NodeName|Acc]
                end
        end
    end, [], supervisor:which_children(?MODULE)),
    lists:usort(NodeList).

%%% ===================================================
%%% Supervisor callbacks
%%% ===================================================
init([]) ->
    {ok, {{simple_one_for_one, 100, 1}, [
        {gen_rpc_client, {gen_rpc_client,start_link,[]}, temporary, 5000, worker, [gen_rpc_client]}
    ]}}.

%%% ===================================================
%%% Private functions
%%% ===================================================
%% Extract the node name from a gen_rpc client process name
%% (see gen_rpc_helper:make_process_name/2)
extract_node_name("gen_rpc.client." ++ Name) ->
    Node = case string:tokens(Name, "/") of
        [TNode, _Key] -> TNode;
        [TNode] -> TNode
    end,
    erlang:list_to_atom(Node).
