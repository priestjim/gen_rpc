%%% -*-mode:erlang;coding:utf-8;tab-width:4;c-basic-offset:4;indent-tabs-mode:()-*-
%%% ex: set ft=erlang fenc=utf-8 sts=4 ts=4 sw=4 et:
%%%
%%% Copyright 2015 Panagiotis Papadomitsos. All Rights Reserved.
%%%

-module(gen_rpc_monitor).

%%% Behaviour
-behaviour(gen_server).

%%% Include the HUT library
-include_lib("hut/include/hut.hrl").
%%% Include the debug logging macros
-include("logging.hrl").

%%% Local state
-record(state, {pid_to_node :: map(), % Used to map a crashed PID to a specific node
        node_conns :: map(), % Used to count connections to a specific node
        node_to_sub :: map(), % Used to map a node to its subscribers
        sub_to_node :: map(), % Used to map a subscriber PID to the set of nodes it monitors
        sub_to_mref :: map()}). % Used to map a client PID to its monitor reference

%%% Supervisor functions
-export([start_link/0, stop/0]).

%%% Server functions
-export([register_node/2, monitor_node/2]).

%%% Behaviour callbacks
-export([init/1, handle_call/3, handle_cast/2,
        handle_info/2, terminate/2, code_change/3]).

%%% ===================================================
%%% Public API
%%% ===================================================
-spec start_link() -> gen_server:start_ret().
start_link() ->
    gen_server:start_link({local,?MODULE}, ?MODULE, [], []).

-spec stop() -> ok.
stop() ->
    gen_server:stop(?MODULE, normal, infinity).

-spec register_node(atom(), pid()) -> ok.
register_node(Node, Pid) when is_atom(Node), is_pid(Pid) ->
    gen_server:call(?MODULE, {register_node,Node,Pid}, infinity).

-spec monitor_node(atom(), boolean()) -> true.
monitor_node(Node, Flag) when is_atom(Node), is_boolean(Flag) ->
    gen_server:call(?MODULE, {monitor_node,Node,Flag}, infinity).

%%% ===================================================
%%% Behaviour callbacks
%%% ===================================================
init([]) ->
    ?log(info, "event=start"),
    {ok, #state{pid_to_node=maps:new(),
        node_conns=maps:new(),
        node_to_sub=maps:new(),
        sub_to_node=maps:new(),
        sub_to_mref=maps:new()
    }}.

%% Register a node
handle_call({register_node,Node,Pid}, _Caller, #state{pid_to_node=PTN,node_conns=NodeConns} = State) ->
    _MRef = erlang:monitor(process, Pid),
    %% Save the client PID to node map
    %% so we can lookup the PID to node mapping if
    %% the gen_rpc client process for that node dies
    NewPTN = maps:put(Pid, Node, PTN),
    %% Increase the node connection count
    NewNodeConns = case maps:get(Node, NodeConns, 0) of
        0 ->
            %% The connection to this node is new
            %% Notify the subscribers
            ?log_debug("event=new_node_connection_detected node=\"~s\"", [Node]),
            ok = gen_server:cast(self(), {notify,nodeup,Node}),
            maps:put(Node, 1, NodeConns);
        NodeConn when NodeConn > 0 ->
            maps:put(Node, NodeConn + 1, NodeConns)
    end,
    {reply, ok, State#state{pid_to_node=NewPTN,node_conns=NewNodeConns}};

%% Register a subscriber
handle_call({monitor_node,Node,true}, {Caller,_Tag}, #state{node_to_sub=NTS, sub_to_node=STN, sub_to_mref=STM} = State) ->
    %% Register the subscriber in the list of subscribers for that
    %% specific node. Subscribers are registered only once per node
    NewSubSet = sets:add_element(Caller, maps:get(Node, NTS, sets:new())),
    NewNTS = maps:put(Node, NewSubSet, NTS),
    %% Register the subscriber to node assignment, a subscriber
    %% can monitor multiple nodes
    NewNodeSet = sets:add_element(Node, maps:get(Caller, STN, sets:new())),
    NewSTN = maps:put(Caller, NewNodeSet, STN),
    %% Monitor the new subscriber to remove them in case
    %% they die
    NewSTM = case maps:find(Caller, STM) of
        {ok, _MRef} ->
            %% Subscriber already has a monitor setup for them
            %% Do nothing
            STM;
        error ->
            MRef = erlang:monitor(process, Caller),
            maps:put(Caller, MRef, STM)
    end,
    {reply, true, State#state{node_to_sub=NewNTS, sub_to_node=NewSTN, sub_to_mref=NewSTM}};

%% Unregister a subscriber
handle_call({monitor_node,Node,false}, {Caller,_Tag}, #state{node_to_sub=NTS, sub_to_node=STN, sub_to_mref=STM} = State) ->
    NewNTS = remove_subscriber_from_node(Caller, Node, NTS),
    %% Unregister the node from the subscriber's node set
    NewNodeSet = sets:del_element(Node, maps:get(Caller, STN, sets:new())),
    case sets:is_empty(NewNodeSet) of
        true ->
            %% The subscriber monitors no more nodes, forget about it
            %% and remove the monitor
            NewSTM = case maps:find(Caller, STM) of
                {ok, MRef} ->
                    _Any = erlang:demonitor(MRef, [flush]),
                    maps:remove(Caller, STM);
                error ->
                    STM
            end,
            {reply, true, State#state{node_to_sub=NewNTS, sub_to_node=maps:remove(Caller, STN), sub_to_mref=NewSTM}};
        false ->
            {reply, true, State#state{node_to_sub=NewNTS, sub_to_node=maps:put(Caller, NewNodeSet, STN)}}
    end;

%% Catch-all for calls - die if we get a message we don't expect
handle_call(Msg, _Caller, State) ->
    ?log(error, "event=unknown_call_received message=\"~p\" action=stopping", [Msg]),
    {stop, {unknown_call, Msg}, State}.

%% Notify the subscribers of a node that it went up or down
handle_cast({notify,Event,Node}, #state{node_to_sub=NTS} = State) when Event =:= nodeup; Event =:= nodedown ->
    ok = lists:foreach(fun(Pid) ->
        _Msg = erlang:send(Pid, {Event,Node})
    end, sets:to_list(maps:get(Node, NTS, sets:new()))),
    {noreply, State};

%% Catch-all for casts - die if we get a message we don't expect
handle_cast(Msg, State) ->
    ?log(error, "event=unknown_cast_received message=\"~p\" action=stopping", [Msg]),
    {stop, {unknown_cast, Msg}, State}.

%% Handle client node disconnects and subscriber deaths
handle_info({'DOWN', _MRef, process, Pid, _Info}, #state{pid_to_node=PTN, node_conns=NodeConns, node_to_sub=NTS,
            sub_to_node=STN, sub_to_mref=STM} = State) ->
    %% Get the pid to node assignment
    case maps:find(Pid, PTN) of
        {ok, Node} ->
            %% This is a node event
            %% Remove the crashed PID from the pid to node list
            NewPTN = maps:remove(Pid, PTN),
            case maps:get(Node, NodeConns) - 1 of
                0 ->
                    %% The node truly went down, let's notify the subscribers
                    ?log_debug("event=node_connection_lost node=\"~s\"", [Node]),
                    ok = gen_server:cast(self(), {notify,nodedown,Node}),
                    {noreply, State#state{pid_to_node=NewPTN, node_conns=maps:remove(Node, NodeConns)}};
                RemainingConns ->
                    %% Just a single connection went down, not a notification event
                    {noreply, State#state{pid_to_node=NewPTN, node_conns=maps:put(Node, RemainingConns, NodeConns)}}
            end;
        error ->
            %% This is not a node event, this is a subscriber process event
            %% The subscriber is dead, remove it from all the nodes it monitored
            NewNTS = sets:fold(fun(Node, Acc) ->
                remove_subscriber_from_node(Pid, Node, Acc)
            end, NTS, maps:get(Pid, STN, sets:new())),
            {noreply, State#state{node_to_sub=NewNTS, sub_to_node=maps:remove(Pid, STN), sub_to_mref=maps:remove(Pid, STM)}}
    end;

%% Catch-all for info - our protocol is strict so die!
handle_info(Msg, State) ->
    ?log(error, "event=unknown_message_received message=\"~p\" action=stopping", [Msg]),
    {stop, {unknown_info, Msg}, State}.

code_change(_OldVersion, State, _Extra) ->
    {ok, State}.

terminate(_Reason, _State) ->
    ok.

%%% ===================================================
%%% Private functions
%%% ===================================================
remove_subscriber_from_node(Subscriber, Node, NTS) ->
    case maps:find(Node, NTS) of
        {ok, SubSet} ->
            NewSubSet = sets:del_element(Subscriber, SubSet),
            case sets:is_empty(NewSubSet) of
                true -> maps:remove(Node, NTS);
                false -> maps:put(Node, NewSubSet, NTS)
            end;
        error ->
            NTS
    end.
