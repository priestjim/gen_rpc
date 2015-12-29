%%% -*-mode:erlang;coding:utf-8;tab-width:4;c-basic-offset:4;indent-tabs-mode:()-*-
%%% ex: set ft=erlang fenc=utf-8 sts=4 ts=4 sw=4 et:
%%%
%%% Copyright 2015 Panagiotis Papadomitsos. All Rights Reserved.
%%%
%%% Original concept inspired and some code copied from
%%% https://erlangcentral.org/wiki/index.php?title=Building_a_Non-blocking_TCP_server_using_OTP_principles

-module(gen_rpc_client).
-author("Panagiotis Papadomitsos <pj@ezgr.net>").

%%% Behaviour
-behaviour(gen_server).

%%% Include this library's name macro
-include("app.hrl").
%%% Include helpful guard macros
-include("guards.hrl").

%%% Local state
-record(state, {socket :: port(),
        server_node :: atom(),
        send_timeout :: timeout(),
        receive_timeout :: timeout(),
        inactivity_timeout :: timeout()}).

%%% Supervisor functions
-export([start_link/1, stop/1]).

%%% FSM functions
-export([call/3, call/4, call/5, call/6, cast/3, cast/4, cast/5, safe_cast/3, safe_cast/4, safe_cast/5]).

-export([async_call/3, async_call/4, yield/1, yield/2, nb_yield/1, nb_yield/2]).

-export([eval_everywhere/3, eval_everywhere/4, eval_everywhere/5,
         safe_eval_everywhere/3, safe_eval_everywhere/4, safe_eval_everywhere/5]).

-export([pinfo/1, pinfo/2]).

%%% Behaviour callbacks
-export([init/1, handle_call/3, handle_cast/2,
        handle_info/2, terminate/2, code_change/3]).

%%% Process exports
-export([call_worker/3]).

%%% ===================================================
%%% Supervisor functions
%%% ===================================================
start_link(Node) when is_atom(Node) ->
    %% Naming our gen_server as the node we're calling as it is extremely efficent:
    %% We'll never deplete atoms because all connected node names are already atoms in this VM
    gen_server:start_link({local,Node}, ?MODULE, {Node}, [{spawn_opt, [{priority, high}]}]).

stop(Node) when is_atom(Node) ->
    gen_server:call(Node, stop).

%%% ===================================================
%%% Server functions
%%% ===================================================
%% Simple server async_call with no args
async_call(Node, M, F)->
    async_call(Node, M, F, []).

%% Simple server async_call with args
async_call(Node, M, F, A) when is_atom(Node), is_atom(M), is_atom(F), is_list(A) ->
    ReplyTo = self(),
    spawn(fun()-> 
              Reply = call(Node, M, F, A, undefined, undefined),
              ReplyTo ! {self(), {promise_reply, Reply}}
          end).

%% Simple server call with no args and default timeout values
call(Node, M, F) ->
    call(Node, M, F, [], undefined, undefined).

%% Simple server call with args and default timeout values
call(Node, M, F, A) ->
    call(Node, M, F, A, undefined, undefined).

%% Simple server call with custom receive timeout value
call(Node, M, F, A, RecvTO) ->
    call(Node, M, F, A, RecvTO, undefined).

%% Simple server call with custom receive and send timeout values
%% This is the function that all of the above call
call(Node, M, F, A, RecvTO, SendTO) when is_atom(Node), is_atom(M), is_atom(F), is_list(A),
                                         RecvTO =:= undefined orelse ?is_timeout(RecvTO),
                                         SendTO =:= undefined orelse ?is_timeout(SendTO) ->
    case whereis(Node) of
        undefined ->
            ok = lager:info("function=call event=client_process_not_found server_node=\"~s\" action=spawning_client", [Node]),
            case gen_rpc_dispatcher:start_client(Node) of
                {ok, NewPid} ->
                    %% We take care of CALL inside the gen_server
                    %% This is not resilient enough if the caller's mailbox is full
                    %% but it's good enough for now
                    gen_server:call(NewPid, {{call,M,F,A},RecvTO,SendTO}, infinity);
                {error, Reason} ->
                    Reason
            end;
        Pid ->
            ok = lager:debug("function=call event=client_process_found pid=\"~p\" server_node=\"~s\"", [Pid, Node]),
            gen_server:call(Pid, {{call,M,F,A},RecvTO,SendTO}, infinity)
    end.

%% Simple server cast with no args and default timeout values
cast(Node, M, F) ->
    cast(Node, M, F, [], undefined).

%% Simple server cast with args and default timeout values
cast(Node, M, F, A) ->
    cast(Node, M, F, A, undefined).

%% Simple server cast with custom send timeout value
%% This is the function that all of the above casts call
cast(Node, M, F, A, SendTO) when is_atom(Node), is_atom(M), is_atom(F), is_list(A),
                                 SendTO =:= undefined orelse ?is_timeout(SendTO) ->
    %% Naming our gen_server as the node we're calling as it is extremely efficent:
    %% We'll never deplete atoms because all connected node names are already atoms in this VM
    case whereis(Node) of
        undefined ->
            ok = lager:info("function=cast event=client_process_not_found server_node=\"~s\" action=spawning_client", [Node]),
            case gen_rpc_dispatcher:start_client(Node) of
                {ok, NewPid} ->
                    %% We take care of CALL inside the gen_server
                    %% This is not resilient enough if the caller's mailbox is full
                    %% but it's good enough for now
                    ok = gen_server:cast(NewPid, {{cast,M,F,A},SendTO}),
                    true;
                {error, _Reason} ->
                    true
            end;
        Pid ->
            ok = lager:debug("function=cast event=client_process_found pid=\"~p\" server_node=\"~s\"", [Pid, Node]),
            ok = gen_server:cast(Pid, {{cast,M,F,A},SendTO}),
            true
    end.

%% Evaluate {M, F, A} on connected nodes.
eval_everywhere(Nodes, M, F) ->
    eval_everywhere(Nodes, M, F, [], undefined).

%% Evaluate {M, F, A} on connected nodes.
eval_everywhere(Nodes, M, F, A) ->
    eval_everywhere(Nodes, M, F, A, undefined).

%% Evaluate {M, F, A} on connected nodes.
eval_everywhere(Nodes, M, F, A, SendTO) when is_list(Nodes), is_atom(M), is_atom(F), is_list(A),
                                             SendTO =:= undefined orelse ?is_timeout(SendTO) ->
    [cast(Node, M, F, A, SendTO) || Node <- Nodes],
    abcast.

%% @doc Location transparent version of the BIF process_info/2.
-spec pinfo(Pid::pid()) -> [{Item::atom(), Info::term()}] | undefined.
pinfo(Pid) when is_pid(Pid) ->
    call(node(Pid), erlang, process_info, [Pid]).

%% @doc Location transparent version of the BIF process_info/2.
-spec pinfo(Pid::pid(), Iterm::atom()) -> {Item::atom(), Info::term()} | undefined | [].
pinfo(Pid, Item) when is_pid(Pid), is_atom(Item) ->
    call(node(Pid), erlang, process_info, [Pid, Item]).

%% Safe server cast with no args and default timeout values
safe_cast(Node, M, F) ->
    safe_cast(Node, M, F, [], undefined).

%% Safe server cast with args and default timeout values
safe_cast(Node, M, F, A) ->
    safe_cast(Node, M, F, A, undefined).

%% Safe server cast with custom send timeout value
%% This is the function that all of the above casts call
safe_cast(Node, M, F, A, SendTO) when is_atom(Node), is_atom(M), is_atom(F), is_list(A),
                                 SendTO =:= undefined orelse is_integer(SendTO) orelse SendTO =:= infinity ->
    %% Naming our gen_server as the node we're calling as it is extremely efficent:
    %% We'll never deplete atoms because all connected node names are already atoms in this VM
    case whereis(Node) of
        undefined ->
            ok = lager:info("function=safe_cast event=client_process_not_found server_node=\"~s\" action=spawning_client", [Node]),
            case gen_rpc_dispatcher:start_client(Node) of
                {ok, NewPid} ->
                    %% We take care of CALL inside the gen_server
                    %% This is not resilient enough if the caller's mailbox is full
                    %% but it's good enough for now
                    gen_server:call(NewPid, {{cast,M,F,A},SendTO}, infinity);
                {error, Reason} ->
                    Reason
            end;
        Pid ->
            ok = lager:debug("function=safe_cast event=client_process_found pid=\"~p\" server_node=\"~s\"", [Pid, Node]),
            gen_server:call(Pid, {{cast,M,F,A},SendTO}, infinity)
    end.

%% Safely evaluate {M, F, A} on connected nodes.
safe_eval_everywhere(Nodes, M, F) ->
    safe_eval_everywhere(Nodes, M, F, [], undefined).

%% Safely evaluate{M, F, A} on implicit connected nodes
safe_eval_everywhere(Nodes, M, F, A) ->
    safe_eval_everywhere(Nodes, M, F, A, undefined).

%% Safe evaluate{M, F, A} on custom list of nodes.
safe_eval_everywhere(Nodes, M, F, A, SendTO) when is_list(Nodes), is_atom(M), is_atom(F), is_list(A),
                                             SendTO =:= undefined orelse ?is_timeout(SendTO) ->
    Ret = [{Node, safe_cast(Node, M, F, A, SendTO)} || Node <- Nodes],
    parse_safe_eval_everywhere_result(Ret, Nodes).

%% Simple server yield with key. Delegate to nb_yield. Default timeout form configuration.
yield(Key)-> 
    yield(Key, infinity).

yield(Key, YieldTO)-> 
    case nb_yield(Key, YieldTO) of
        {value, R} -> R;
        {badrpc, Reason} -> {badrpc, Reason}
    end.

%% Simple server non-blocking yield with key, default timeout value of 0
nb_yield(Key)->
    nb_yield(Key, 0).

%% Simple server non-blocking yield with key and custom timeout value
nb_yield(Key, Timeout) when is_pid(Key), is_integer(Timeout) orelse Timeout =:= infinity ->
    receive 
            {Key, {promise_reply, Reply}} -> {value, Reply};
            UnknownMsg -> 
                    ok = lager:notice("function=nb_yield event=unknown_msg yield_key=\"~p\" message=\"~p\"", [Key, UnknownMsg]),
                    {value, {badrpc, timeout}}
    after Timeout ->
            ok = lager:notice("function=nb_yield event=call_timeout yield_key=\"~p\"", [Key]),
            {value, {badrpc, timeout}}
    end.


%%% ===================================================
%%% Behaviour callbacks
%%% ===================================================
init({Node}) ->
    _OldVal = erlang:process_flag(trap_exit, true),
    ok = net_kernel:monitor_nodes(true, [nodedown_reason]),
    %% Extract application-specific settings
    Settings = application:get_all_env(?APP),
    {connect_timeout, ConnTO} = lists:keyfind(connect_timeout, 1, Settings),
    {send_timeout, SendTO} = lists:keyfind(send_timeout, 1, Settings),
    {receive_timeout, RecvTO} = lists:keyfind(receive_timeout, 1, Settings),
    {client_inactivity_timeout, TTL} = lists:keyfind(client_inactivity_timeout, 1, Settings),
    %% Perform an in-band RPC call to the remote node
    %% asking it to launch a listener for us and return us
    %% the port that has been allocated for us
    ok = lager:info("function=init event=initializing_client server_node=\"~s\" connect_timeout=~B send_timeout=~B receive_timeout=~B inactivity_timeout=\"~p\"",
                    [Node, ConnTO, SendTO, RecvTO, TTL]),
    case rpc:call(Node, gen_rpc_server_sup, start_child, [node()], ConnTO) of
        {ok, Port} ->
            %% Fetching the IP ourselves, since the remote node
            %% does not have a straightforward way of returning
            %% the proper remote IP
            Address = get_remote_node_ip(Node),
            ok = lager:debug("function=init event=remote_server_started_successfully server_node=\"~s\" server_ip=\"~p:~B\"",
                             [Node, Address, Port]),
            case gen_tcp:connect(Address, Port, gen_rpc_helper:default_tcp_opts(?DEFAULT_TCP_OPTS), ConnTO) of
                {ok, Socket} ->
                    ok = lager:debug("function=init event=connecting_to_server server_node=\"~s\" server_ip=\"~p:~B\" result=success",
                                     [Node, Address, Port]),
                    {ok, #state{socket=Socket,server_node=Node,send_timeout=SendTO,receive_timeout=RecvTO,inactivity_timeout=TTL}, TTL};
                {error, Reason} ->
                    ok = lager:error("function=init event=connecting_to_server server_node=\"~s\" server_ip=\"~s:~B\" result=failure reason=\"~p\"",
                                     [Node, Address, Port, Reason]),
                    {stop, {badtcp,Reason}}
            end;
        {badrpc, Reason} ->
            {stop, {badrpc, Reason}}
    end.

%% This is the actual CALL handler
handle_call({{call,_M,_F,_A} = PacketTuple, URecvTO, USendTO}, Caller, #state{socket=Socket,server_node=Node} = State) ->
    {RecvTO, SendTO} = merge_timeout_values(State#state.receive_timeout, URecvTO, State#state.send_timeout, USendTO),
    Ref = erlang:make_ref(),
    %% Spawn the worker that will wait for the server's reply
    WorkerPid = erlang:spawn(?MODULE, call_worker, [Ref, Caller, RecvTO]),
    %% Let the server know of the responsible process
    Packet = erlang:term_to_binary({node(), WorkerPid, Ref, PacketTuple}),
    ok = lager:debug("function=handle_call message=call event=constructing_call_term socket=\"~p\" call_reference=\"~p\"",
                     [Socket, Ref]),
    ok = inet:setopts(Socket, [{send_timeout, SendTO}]),
    %% Since call can fail because of a timed out connection without gen_rpc knowing it,
    %% we have to make sure the remote node is reachable somehow before we send data. net_kernel:connect does that
    case net_kernel:connect(Node) of
        true ->
            case gen_tcp:send(Socket, Packet) of
                {error, timeout} ->
                    ok = lager:error("function=handle_call message=call event=transmission_failed socket=\"~p\" call_reference=\"~p\" reason=\"timeout\"",
                                     [Socket, Ref]),
                    %% Reply will be handled from the worker
                    {stop, {badtcp,send_timeout}, {badtcp,send_timeout}, State};
                {error, Reason} ->
                    ok = lager:error("function=handle_call message=call event=transmission_failed socket=\"~p\" call_reference=\"~p\" reason=\"~p\"",
                                     [Socket, Ref, Reason]),
                    %% Reply will be handled from the worker
                    {stop, {badtcp,Reason}, {badtcp,Reason}, State};
                ok ->
                    ok = lager:debug("function=handle_call message=call event=transmission_succeeded socket=\"~p\" call_reference=\"~p\"",
                                     [Socket, Ref]),
                    %% We need to enable the socket and perform the call only if the call succeeds
                    ok = inet:setopts(Socket, [{active, once}]),
                    %% Reply will be handled from the worker
                    {noreply, State, State#state.inactivity_timeout}
            end;
        _Else ->
            ok = lager:error("function=handle_call message=call event=node_down socket=\"~p\" call_reference=\"~p\"",
                             [Socket, Ref]),
            {stop, {badrpc,nodedown}, {badrpc,nodedown}, State}
    end;
%% This is the actual CAST handler for SAFE_CAST
handle_call({{cast,_M,_F,_A} = PacketTuple, USendTO}, _Caller, #state{socket=Socket,server_node=Node} = State) ->
    case do_cast(PacketTuple, USendTO, Socket, Node, State) of
        {error, Error} ->
            {stop, Error, Error, State};
        ok ->
            {reply, true, State, State#state.inactivity_timeout}
    end;

%% Gracefully terminate
handle_call(stop, _Caller, State) ->
    ok = lager:debug("function=handle_call event=stopping_client socket=\"~p\"", [State#state.socket]),
    {stop, normal, ok, State};

%% Catch-all for calls - die if we get a message we don't expect
handle_call(Msg, _Caller, State) ->
    ok = lager:critical("function=handle_call event=uknown_call_received socket=\"~p\" message=\"~p\" action=stopping", [State#state.socket, Msg]),
    {stop, {unknown_call, Msg}, {unknown_call, Msg}, State}.

%% This is the actual CAST handler for CAST
handle_cast({{cast,_M,_F,_A} = PacketTuple, USendTO}, #state{socket=Socket,server_node=Node} = State) ->
    case do_cast(PacketTuple, USendTO, Socket, Node, State) of
        {error, Error} ->
            {stop, Error, State};
        ok ->
            {noreply, State, State#state.inactivity_timeout}
    end;

%% Catch-all for casts - die if we get a message we don't expect
handle_cast(Msg, State) ->
    ok = lager:critical("function=handle_call event=uknown_cast_received socket=\"~p\" message=\"~p\" action=stopping", [State#state.socket, Msg]),
    {stop, {unknown_cast, Msg}, State}.

%% Handle any TCP packet coming in
handle_info({tcp,Socket,Data}, #state{socket=Socket} = State) ->
    _Reply = try erlang:binary_to_term(Data) of
        {WorkerPid, Ref, Reply} ->
            case erlang:is_process_alive(WorkerPid) of
                true ->
                    ok = lager:debug("function=handle_info message=tcp event=reply_received call_reference=\"~p\" worker_pid=\"~p\" action=sending_to_worker",
                                     [Ref, WorkerPid]),
                    WorkerPid ! {reply,Ref,Reply};
                false ->
                    ok = lager:notice("function=handle_info message=tcp event=reply_received_with_dead_worker call_reference=\"~p\" worker_pid=\"~p\"",
                                      [Ref, WorkerPid])
            end;
        OtherData ->
            ok = lager:error("function=handle_info message=tcp event=erroneous_reply_received socket=\"~p\" data=\"~p\" action=ignoring",
                             [Socket, OtherData])
    catch
        error:badarg ->
            ok = lager:error("function=handle_info message=tcp event=corrupt_data_received socket=\"~p\" action=ignoring", [Socket])
    end,
    ok = inet:setopts(Socket, [{active, once}]),
    {noreply, State, State#state.inactivity_timeout};

%% Handle VM node down information
handle_info({nodedown, Node, [{nodedown_reason,Reason}]}, #state{socket=Socket,server_node=Node} = State) ->
    ok = lager:warning("function=handle_info message=nodedown event=node_down socket=\"~p\" node=~s reason=\"~p\" action=stopping", [Socket, Node, Reason]),
    {stop, normal, State};

handle_info({tcp_closed, Socket}, #state{socket=Socket} = State) ->
    ok = lager:warning("function=handle_info message=tcp_closed event=tcp_socket_closed socket=\"~p\" action=stopping", [Socket]),
    {stop, normal, State};

handle_info({tcp_error, Socket, Reason}, #state{socket=Socket} = State) ->
    ok = lager:warning("function=handle_info message=tcp_error event=tcp_socket_error socket=\"~p\" reason=\"~p\" action=stopping", [Socket, Reason]),
    {stop, normal, State};

%% Stub for VM up information
handle_info({NodeEvent, _Node, _InfoList}, State) when NodeEvent =:= nodeup; NodeEvent =:= nodedown ->
    {noreply, State, State#state.inactivity_timeout};

%% Handle the inactivity timeout gracefully
handle_info(timeout, State) ->
    ok = lager:info("function=handle_info message=timeout event=client_inactivity_timeout socket=\"~p\" action=stopping", [State#state.socket]),
    {stop, normal, State};

%% Catch-all for info - our protocol is strict so die!
handle_info(Msg, State) ->
    ok = lager:critical("function=handle_info event=uknown_message_received socket=\"~p\" message=\"~p\" action=stopping", [State#state.socket, Msg]),
    {stop, {unknown_info, Msg}, State}.

%% Stub functions
code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

terminate(_Reason, #state{socket=Socket}) ->
    ok = lager:debug("function=terminate socket=\"~p\"", [Socket]),
    _Pid = erlang:spawn(gen_rpc_client_sup, stop_child, [self()]),
    ok.

%%% ===================================================
%%% Private functions
%%% ===================================================

%% DRY function for cast and safe_cast
do_cast(PacketTuple, USendTO, Socket, Node, State) ->
    {_RecvTO, SendTO} = merge_timeout_values(undefined, undefined, State#state.send_timeout, USendTO),
    %% Cast requests do not need a reference
    Packet = erlang:term_to_binary({node(), PacketTuple}),
    ok = lager:debug("function=do_cast message=cast event=constructing_cast_term socket=\"~p\"", [Socket]),
    %% Set the send timeout and do not run in active mode - we're a cast!
    ok = inet:setopts(Socket, [{send_timeout, SendTO}]),
    %% Since cast can fail because of a timed out connection without gen_rpc knowing it,
    %% we have to make sure the remote node is reachable somehow before we send data. net_kernel:connect does that
    case net_kernel:connect(Node) of
        true ->
            case gen_tcp:send(Socket, Packet) of
                {error, timeout} ->
                    %% Terminate will handle closing the socket
                    ok = lager:error("function=do_cast message=cast event=transmission_failed socket=\"~p\" reason=\"timeout\"", [Socket]),
                    {error, {badtcp,send_timeout}};
                {error, Reason} ->
                    ok = lager:error("function=do_cast message=cast event=transmission_failed socket=\"~p\" reason=\"~p\"", [Socket, Reason]),
                    {error, {badtcp,Reason}};
                ok ->
                    ok = lager:debug("function=do_cast message=cast event=transmission_succeeded socket=\"~p\"", [Socket]),
                    ok
            end;
        _Else ->
            ok = lager:error("function=do_cast message=cast event=node_down socket=\"~p\"", [Socket]),
            {error, {badrpc,nodedown}}
    end.

%% For loopback communication and performance testing
get_remote_node_ip(Node) when Node =:= node() ->
    {127,0,0,1};
get_remote_node_ip(Node) ->
    {ok, NodeInfo} = net_kernel:node_info(Node),
    {address, AddressInfo} = lists:keyfind(address, 1, NodeInfo),
    {net_address, {Ip, _Port}, _Name, _Proto, _Channel} = AddressInfo,
    ok = lager:debug("function=get_remote_node_ip node=\"~s\" ip_address=\"~p\"", [Node, Ip]),
    Ip.

%% This function is a process launched by the gen_server, waiting to receive a
%% reply from the TCP channel via the gen_server
call_worker(Ref, Caller, Timeout) when is_tuple(Caller), is_reference(Ref) ->
    receive
        {reply,Ref,Reply} ->
            ok = lager:debug("function=call_worker event=reply_received call_reference=\"~p\" reply=\"~p\"",
                             [Ref, Reply]),
            _Ign = gen_server:reply(Caller, Reply),
            ok;
        Else ->
            ok = lager:error("function=call_worker event=invalid_message_received call_reference=\"~p\" message=\"~p\"",
                             [Ref, Else]),
            _Ign = gen_server:reply(Caller, {badrpc, invalid_message_received})
    after
        Timeout ->
            ok = lager:notice("function=call_worker event=call_timeout call_reference=\"~p\"", [Ref]),
            _Ign = gen_server:reply(Caller, {badrpc, timeout})
    end.

%% Merges user-define timeout values with state timeout values
merge_timeout_values(SRecvTO, undefined, SSendTO, undefined) ->
    {SRecvTO, SSendTO};
merge_timeout_values(_SRecvTO, URecvTO, SSendTO, undefined) ->
    {URecvTO, SSendTO};
merge_timeout_values(SRecvTO, undefined, _SSendTO, USendTO) ->
    {SRecvTO, USendTO};
merge_timeout_values(_SRecvTO, URecvTO, _SSendTO, USendTO) ->
    {URecvTO, USendTO}.

%% Transform result for safe_eval_everywhere to look like multicall
parse_safe_eval_everywhere_result(ResultNodes, AllNodes) ->
    BadNodes = [ X || {X, {_,_}} <- ResultNodes],
    GoodNodes = AllNodes -- BadNodes,
    case GoodNodes =/= [] of
        true -> [true, BadNodes];
        false -> BadNodes
    end.
