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

%%% Include the HUT library
-include_lib("hut/include/hut.hrl").
%%% Include the debug logging macros
-include("logging.hrl").
%%% Include helpful guard macros
-include("guards.hrl").
%%% Include helpful types
-include("types.hrl").

%%% Local state
-record(state, {socket :: port(),
        driver :: atom(),
        driver_mod :: atom(),
        driver_closed :: atom(),
        driver_error :: atom(),
        keepalive :: gen_rpc_keepalive:keepalive(),
        send_timeout :: timeout() | undefined, % The send timeout set on the socket, undefined if unknown
        last_activity :: integer()}). % Monotonic time (ms) of the last non-keepalive activity

%%% Supervisor functions
-export([start/1, start_link/2, stop/1]).

%%% Server functions
-export([call/3, call/4, call/5, call/6, cast/3, cast/4, cast/5]).

-export([async_call/3, async_call/4, yield/1, nb_yield/1, nb_yield/2]).

-export([eval_everywhere/3, eval_everywhere/4, eval_everywhere/5]).

-export([multicall/3, multicall/4, multicall/5]).

-export([abcast/2, abcast/3, sbcast/2, sbcast/3]).

%%% Behaviour callbacks
-export([init/1, handle_call/3, handle_cast/2,
        handle_info/2, terminate/2, code_change/3]).

%%% Process exports
-export([async_call_worker/5, cast_worker/3]).

%%% ===================================================
%%% Supervisor functions
%%% ===================================================
%% Connects and authenticates to the server of a node and starts the client
%% process that owns the connection. The connection is established before the
%% client starts so that a node that is slow to answer does not hold up the
%% client supervisor, which starts its children one at a time
-spec start(node_or_tuple()) -> {ok, pid()} | {error, term()}.
start(NodeOrTuple) when ?is_node_or_tuple(NodeOrTuple) ->
    Node = case NodeOrTuple of
        {TNode,_Key} -> TNode;
        TNode -> TNode
    end,
    case connect(Node) of
        {ok, Driver, Socket} ->
            {DriverMod, _DriverClosed, _DriverError} = gen_rpc_helper:get_client_driver_options(Driver),
            case gen_rpc_client_sup:start_child(NodeOrTuple, {Driver, Socket}) of
                {ok, Pid} ->
                    %% The socket is passive until the client activates it
                    ok = DriverMod:set_controlling_process(Socket, Pid),
                    {ok, Pid};
                {error, _Reason} = Error ->
                    ok = DriverMod:close(Socket),
                    Error
            end;
        {error, _Reason} = Error ->
            Error
    end.

-spec start_link(node_or_tuple(), {atom(), term()}) -> gen_server:start_ret().
start_link(NodeOrTuple, {Driver, _Socket} = Connection) when ?is_node_or_tuple(NodeOrTuple), is_atom(Driver) ->
    PidName = gen_rpc_helper:make_process_name("client", NodeOrTuple),
    gen_server:start_link({local,PidName}, ?MODULE, {NodeOrTuple, Connection}, []).

-spec stop(node_or_tuple()) -> ok.
stop(NodeOrTuple) when ?is_node_or_tuple(NodeOrTuple) ->
    PidName = gen_rpc_helper:make_process_name("client", NodeOrTuple),
    gen_server:stop(PidName, normal, infinity).

%%% ===================================================
%%% Server functions
%%% ===================================================
%% Simple server call with no args and default timeout values
-spec call(node_or_tuple(), atom() | tuple(), atom() | function()) -> term() | {badrpc,term()} | {badtcp,term()}.
call(NodeOrTuple, M, F) ->
    call(NodeOrTuple, M, F, [], undefined, undefined).

%% Simple server call with args and default timeout values
-spec call(node_or_tuple(), atom() | tuple(), atom() | function(), list()) -> term() | {badrpc,term()} | {badtcp,term()}.
call(NodeOrTuple, M, F, A) ->
    call(NodeOrTuple, M, F, A, undefined, undefined).

%% Simple server call with custom receive timeout value
-spec call(node_or_tuple(), atom() | tuple(), atom() | function(), list(), timeout()) -> term() | {badrpc,term()} | {badtcp,term()}.
call(NodeOrTuple, M, F, A, RecvTO) ->
    call(NodeOrTuple, M, F, A, RecvTO, undefined).

%% Simple server call with custom receive and send timeout values
%% This is the function that all of the above call
-spec call(node_or_tuple(), atom() | tuple(), atom() | function(), list(), timeout() | undefined, timeout() | undefined) ->
    term() | {badrpc,term()} | {badtcp,term()}.
call(NodeOrTuple, M, F, A, RecvTO, SendTO) when ?is_node_or_tuple(NodeOrTuple), is_atom(M) orelse is_tuple(M), is_atom(F), is_list(A),
                                         RecvTO =:= undefined orelse ?is_timeout(RecvTO),
                                         SendTO =:= undefined orelse ?is_timeout(SendTO) ->
    case get_client(NodeOrTuple) of
        {ok, Pid} ->
            %% We take care of CALL inside the gen_server
            %% This is not resilient enough if the caller's mailbox is full
            %% but it's good enough for now
            try
                gen_server:call(Pid, {{call,M,F,A}, SendTO}, gen_rpc_helper:get_call_receive_timeout(RecvTO))
            catch
                exit:{timeout,_Reason} -> {badrpc,timeout};
                exit:OtherReason -> {badrpc, {unknown_error, OtherReason}}
            end;
        {error, Reason} ->
            Reason
    end.

%% Simple server cast with no args and default timeout values
-spec cast(node_or_tuple(), atom() | tuple(), atom() | function()) -> true.
cast(NodeOrTuple, M, F) ->
    cast(NodeOrTuple, M, F, [], undefined).

%% Simple server cast with args and default timeout values
-spec cast(node_or_tuple(), atom() | tuple(), atom() | function(), list()) -> true.
cast(NodeOrTuple, M, F, A) ->
    cast(NodeOrTuple, M, F, A, undefined).

%% Simple server cast with custom send timeout value
%% This is the function that all of the above casts call
-spec cast(node_or_tuple(), atom() | tuple(), atom() | function(), list(), timeout() | undefined) -> true.
cast(NodeOrTuple, M, F, A, SendTO) when ?is_node_or_tuple(NodeOrTuple), is_atom(M) orelse is_tuple(M), is_atom(F), is_list(A),
                                 SendTO =:= undefined orelse ?is_timeout(SendTO) ->
    ok = cast_to_client(NodeOrTuple, {cast,M,F,A}, SendTO),
    true.

%% Evaluate {M, F, A} on connected nodes.
-spec eval_everywhere([atom()], atom() | tuple(), atom() | function()) -> abcast.
eval_everywhere(Nodes, M, F) ->
    eval_everywhere(Nodes, M, F, [], undefined).

%% Evaluate {M, F, A} on connected nodes.
-spec eval_everywhere([atom()], atom() | tuple(), atom() | function(), list()) -> abcast.
eval_everywhere(Nodes, M, F, A) ->
    eval_everywhere(Nodes, M, F, A, undefined).

%% Evaluate {M, F, A} on connected nodes.
-spec eval_everywhere([atom()], atom() | tuple(), atom() | function(), list(), timeout() | undefined) -> abcast.
eval_everywhere(Nodes, M, F, A, SendTO) when is_list(Nodes), is_atom(M) orelse is_tuple(M), is_atom(F), is_list(A),
                                             SendTO =:= undefined orelse ?is_timeout(SendTO) ->
    _ = [cast_to_client(Node, {cast,M,F,A}, SendTO) || Node <- Nodes],
    abcast.

%% Simple server async_call with no args
-spec async_call(node_or_tuple(), atom() | tuple(), atom() | function()) -> term() | {badrpc,term()} | {badtcp,term()}.
async_call(NodeOrTuple, M, F) ->
    async_call(NodeOrTuple, M, F, []).

%% Simple server async_call with args
-spec async_call(node_or_tuple(), atom() | tuple(), atom() | function(), list()) -> term() | {badrpc,term()} | {badtcp,term()}.
async_call(NodeOrTuple, M, F, A) when ?is_node_or_tuple(NodeOrTuple), is_atom(M) orelse is_tuple(M), is_atom(F), is_list(A) ->
    Ref = erlang:make_ref(),
    Pid = erlang:spawn(?MODULE, async_call_worker, [NodeOrTuple, M, F, A, Ref]),
    {Pid, Ref}.

%% Simple server yield with key. Delegate to nb_yield. Default timeout form configuration.
-spec yield(tuple()) -> term() | {badrpc,term()}.
yield(Key) ->
    {value,Result} = nb_yield(Key, infinity),
    Result.

%% Simple server non-blocking yield with key, default timeout value of 0
-spec nb_yield(tuple()) -> {value,term()} | timeout.
nb_yield(Key)->
    nb_yield(Key, 0).

%% Simple server non-blocking yield with key and custom timeout value
-spec nb_yield(tuple(), timeout()) -> {value,term()} | timeout.
nb_yield({Pid,Ref}, Timeout) when is_pid(Pid), is_reference(Ref), ?is_timeout(Timeout) ->
    Pid ! {self(), Ref, yield},
    receive
        {Pid, Ref, async_call, Result} ->
            {value,Result}
    after
        Timeout ->
            ?log_debug("event=nb_yield_timeout async_call_pid=\"~p\" async_call_ref=\"~p\"", [Pid, Ref]),
            timeout
    end.

%% "Concurrent" call to a set of servers
-spec multicall(atom() | tuple(), atom(), list()) -> {list(), list()}.
multicall(M, F, A) when is_atom(M) orelse is_tuple(M), is_atom(F), is_list(A) ->
    multicall([node()|gen_rpc:nodes()], M, F, A).

-spec multicall(list() | atom() | tuple(), atom() | tuple(), atom() | list(), list() | timeout()) -> {list(), list()}.
multicall(M, F, A, Timeout) when is_atom(M) orelse is_tuple(M), is_atom(F), is_list(A), ?is_timeout(Timeout) ->
    multicall([node()|gen_rpc:nodes()], M, F, A, Timeout);

multicall(Nodes, M, F, A) when is_list(Nodes), is_atom(M) orelse is_tuple(M), is_atom(F), is_list(A) ->
    multicall(Nodes, M, F, A, infinity).

-spec multicall(list(), atom() | tuple(), atom(), list(), timeout()) -> {list(), list()}.
multicall(Nodes, M, F, A, Timeout) when is_list(Nodes), is_atom(M) orelse is_tuple(M), is_atom(F), is_list(A), ?is_timeout(Timeout) ->
    Keys = [async_call(Node, M, F, A) || Node <- Nodes],
    parse_multicall_results(Keys, Nodes, Timeout).

-spec abcast(atom(), term()) -> abcast.
abcast(Name, Msg) when is_atom(Name) ->
    abcast([node()|gen_rpc:nodes()], Name, Msg).

-spec abcast(list(), atom(), term()) -> abcast.
abcast(Nodes, Name, Msg) when is_list(Nodes), is_atom(Name) ->
    _ = [cast_to_client(Node, {abcast,Name,Msg}, undefined) || Node <- Nodes],
    abcast.

-spec sbcast(atom(), term()) -> {list(), list()}.
sbcast(Name, Msg) when is_atom(Name) ->
    sbcast([node()|gen_rpc:nodes()], Name, Msg).

-spec sbcast(list(), atom(), term()) -> {list(), list()}.
sbcast(Nodes, Name, Msg) when is_list(Nodes), is_atom(Name) ->
    Ref = erlang:make_ref(),
    _ = [cast_to_client(Node, {sbcast,Name,Msg,{self(),Ref,Node}}, undefined) || Node <- Nodes],
    parse_sbcast_results(Nodes, Ref).

%%% ===================================================
%%% Behaviour callbacks
%%% ===================================================
%% If we're called with a key, remove it, the key is only relevant
%% at the process name level
init({{Node,_Key}, Connection}) ->
    init({Node, Connection});

init({Node, {Driver, Socket}}) ->
    ok = gen_rpc_helper:set_optimal_process_flags(true),
    {DriverMod, DriverClosed, DriverError} = gen_rpc_helper:get_client_driver_options(Driver),
    ok = gen_rpc_monitor:register_node(Node, self()),
    KeepaliveFun = keepalive_probe(DriverMod, Socket),
    case gen_rpc_keepalive:start(KeepaliveFun, gen_rpc_helper:get_keepalive_interval(), {keepalive, check}) of
        {ok, KeepAlive} ->
            State = #state{socket=Socket,
                           driver=Driver,
                           driver_mod=DriverMod,
                           driver_closed=DriverClosed,
                           driver_error=DriverError,
                           keepalive=KeepAlive,
                           send_timeout=undefined,
                           last_activity=erlang:monotonic_time(millisecond)},
            {ok, State, remaining_timeout(State)};
        {error, Error} ->
            ?log(error, "event=start_keepalive_failed driver=~s reason=\"~p\"", [Driver, Error]),
            {stop, {badrpc, Error}}
    end.

%% This is the actual CALL handler
handle_call({{call,_M,_F,_A} = PacketTuple, SendTO}, Caller, #state{socket=Socket, driver=Driver} = State) ->
    Packet = erlang:term_to_binary({PacketTuple, Caller}),
    ?log_debug("message=call event=constructing_call_term driver=~s socket=\"~s\" caller=\"~p\"",
         [Driver, gen_rpc_helper:socket_to_string(Socket), Caller]),
    %% We need to enable the socket and perform the call only if the call succeeds
    case transmit(call, Packet, SendTO, true, State) of
        {ok, NewState} ->
            noreply_touched(NewState);
        {error, Reason} ->
            {stop, Reason, Reason, State}
    end;

%% Catch-all for calls - die if we get a message we don't expect
handle_call(Msg, _Caller, #state{socket=Socket, driver=Driver} = State) ->
    ?log(error, "event=unknown_call_received driver=~s socket=\"~s\" message=\"~p\" action=stopping",
         [Driver, gen_rpc_helper:socket_to_string(Socket), Msg]),
    {stop, {unknown_call, Msg}, {unknown_call, Msg}, State}.

%% This is the actual CAST handler for CAST
handle_cast({{cast,_M,_F,_A} = PacketTuple, SendTO}, State) ->
    send_cast(PacketTuple, State, SendTO, false);

%% This is the actual CAST handler for ABCAST
handle_cast({{abcast,_Name,_Msg} = PacketTuple, undefined}, State) ->
    send_cast(PacketTuple, State, undefined, false);

%% This is the actual CAST handler for SBCAST
handle_cast({{sbcast,_Name,_Msg,_Caller} = PacketTuple, undefined}, State) ->
    send_cast(PacketTuple, State, undefined, true);

%% This is the actual ASYNC CALL handler
handle_cast({{async_call,_M,_F,_A} = PacketTuple, Caller, Ref}, #state{socket=Socket} = State) ->
    Packet = erlang:term_to_binary({PacketTuple, {Caller,Ref}}),
    ?log_debug("message=async_call event=constructing_async_call_term socket=\"~s\" worker_pid=\"~p\" async_call_ref=\"~p\"",
         [gen_rpc_helper:socket_to_string(Socket), Caller, Ref]),
    %% We need to enable the socket and perform the call only if the call succeeds
    %% Reply will be handled from the worker
    case transmit(async_call, Packet, undefined, true, State) of
        {ok, NewState} ->
            noreply_touched(NewState);
        {error, Reason} ->
            {stop, Reason, Reason, State}
    end;

%% Catch-all for casts - die if we get a message we don't expect
handle_cast(Msg, #state{socket=Socket, driver=Driver} = State) ->
    ?log(error, "event=unknown_cast_received driver=~s socket=\"~s\" message=\"~p\" action=stopping",
         [Driver, gen_rpc_helper:socket_to_string(Socket), Msg]),
    {stop, {unknown_cast, Msg}, State}.

%% Handle any TCP packet coming in
handle_info({Driver,Socket,Data}, #state{socket=Socket, driver=Driver, driver_mod=DriverMod} = State) ->
    _Reply = case erlang:binary_to_term(Data) of
        {call, Caller, Reply} ->
            ?log_debug("event=call_reply_received driver=~s socket=\"~s\" caller=\"~p\" action=sending_reply",
                 [Driver, gen_rpc_helper:socket_to_string(Socket), Caller]),
            gen_server:reply(Caller, Reply);
        {async_call, {Caller, Ref}, Reply} ->
            ?log_debug("event=async_call_reply_received driver=~s socket=\"~s\" caller=\"~p\" action=sending_reply",
                 [Driver, gen_rpc_helper:socket_to_string(Socket), Caller]),
            Caller ! {self(), Ref, async_call, Reply};
        {sbcast, {Caller, Ref, Node}, Reply} ->
            ?log_debug("event=sbcast_reply_received driver=~s socket=\"~s\" caller=\"~p\" reference=\"~p\" action=sending_reply",
                 [Driver, gen_rpc_helper:socket_to_string(Socket), Caller, Ref]),
            Caller ! {Ref, Node, Reply};
        OtherData ->
            ?log(error, "event=erroneous_reply_received driver=~s socket=\"~s\" data=\"~p\" action=ignoring",
                 [Driver, gen_rpc_helper:socket_to_string(Socket), OtherData])
    end,
    ok = DriverMod:activate_socket(Socket),
    noreply_touched(State);

handle_info({DriverClosed, Socket}, #state{socket=Socket, driver=Driver, driver_closed=DriverClosed} = State) ->
    ?log(error, "message=channel_closed driver=~s socket=\"~s\" action=stopping", [Driver, gen_rpc_helper:socket_to_string(Socket)]),
    {stop, normal, State};

handle_info({DriverError, Socket, Reason}, #state{socket=Socket, driver=Driver, driver_error=DriverError} = State) ->
    ?log(error, "message=channel_error driver=~s socket=\"~s\" reason=\"~p\" action=stopping",
         [Driver, gen_rpc_helper:socket_to_string(Socket), Reason]),
    {stop, normal, State};

%% Handle the inactivity timeout gracefully
handle_info(timeout, #state{socket=Socket, driver=Driver} = State) ->
    ?log(info, "message=timeout event=client_inactivity_timeout driver=~s socket=\"~s\" action=stopping",
         [Driver, gen_rpc_helper:socket_to_string(Socket)]),
    {stop, normal, State};

%% Handle the keepalive check. Keepalive traffic does not count as client
%% activity so it does not postpone the inactivity timeout
handle_info({keepalive, check}, #state{driver=Driver, keepalive=KeepAlive} = State) ->
    case gen_rpc_keepalive:check(KeepAlive) of
        {ok, KeepAlive1} ->
            %% Data has been received since the last check, the connection is alive
            NewState = State#state{keepalive=KeepAlive1},
            {noreply, NewState, remaining_timeout(NewState)};
        {error, timeout} ->
            %% Nothing received, probe the server
            send_ping(State#state{keepalive=gen_rpc_keepalive:resume(KeepAlive)});
        {error, Reason} ->
            ?log(error, "event=keepalive_check_failed driver=~s reason=\"~p\" action=stopping",
                [Driver, Reason]),
            {stop, normal, State}
    end;

%% Catch-all for info - our protocol is strict so die!
handle_info(Msg, #state{socket=Socket, driver=Driver} = State) ->
    ?log(error, "event=unknown_message_received driver=~s socket=\"~s\" message=\"~p\" action=stopping",
         [Driver, gen_rpc_helper:socket_to_string(Socket), Msg]),
    {stop, {unknown_info, Msg}, State}.

%% Stub functions
code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

terminate(_Reason, #state{keepalive=KeepAlive}) ->
    ok = gen_rpc_keepalive:cancel(KeepAlive),
    ok.

%%% ===================================================
%%% Private functions
%%% ===================================================
%% Returns the function the keepalive uses to detect socket activity
keepalive_probe(DriverMod, Socket) ->
    fun() ->
        case DriverMod:getstat(Socket, [recv_oct]) of
            {ok, [{recv_oct, RecvOct}]} -> {ok, RecvOct};
            {error, Error}              -> {error, Error}
        end
    end.

%% Record client activity
touch(State) ->
    State#state{last_activity=erlang:monotonic_time(millisecond)}.

%% Record client activity and wait for the next message
noreply_touched(State) ->
    NewState = touch(State),
    {noreply, NewState, remaining_timeout(NewState)}.

%% Time left until the client inactivity timeout is reached
remaining_timeout(#state{last_activity=LastActivity}) ->
    case gen_rpc_helper:get_client_inactivity_timeout() of
        infinity ->
            infinity;
        TTL ->
            erlang:max(0, TTL - (erlang:monotonic_time(millisecond) - LastActivity))
    end.

send_cast(PacketTuple, #state{socket=Socket, driver=Driver} = State, SendTO, Activate) ->
    Packet = erlang:term_to_binary(PacketTuple),
    ?log_debug("event=constructing_cast_term driver=~s socket=\"~s\" cast=\"~p\"",
         [Driver, gen_rpc_helper:socket_to_string(Socket), PacketTuple]),
    case transmit(cast, Packet, SendTO, Activate, State) of
        {ok, NewState} ->
            noreply_touched(NewState);
        {error, Reason} ->
            {stop, Reason, State}
    end.

send_ping(State) ->
    Packet = erlang:term_to_binary(ping),
    %% Keep the socket active so that we get notified of a closed connection
    case transmit(ping, Packet, undefined, true, State) of
        {ok, NewState} ->
            {noreply, NewState, remaining_timeout(NewState)};
        {error, Reason} ->
            {stop, Reason, State}
    end.

%% Send a packet to the server and optionally re-enable the socket afterwards.
%% Returns the new state since the send timeout of the socket might change
transmit(Type, Packet, SendTO, Activate, #state{socket=Socket, driver=Driver, driver_mod=DriverMod} = State) ->
    NewState = set_send_timeout(SendTO, State),
    case DriverMod:send(Socket, Packet) of
        {error, Reason} ->
            ?log(error, "message=~s event=transmission_failed driver=~s socket=\"~s\" reason=\"~p\"",
                 [Type, Driver, gen_rpc_helper:socket_to_string(Socket), Reason]),
            {error, Reason};
        ok ->
            ?log_debug("message=~s event=transmission_succeeded driver=~s socket=\"~s\"",
                 [Type, Driver, gen_rpc_helper:socket_to_string(Socket)]),
            ok = case Activate of
                true -> DriverMod:activate_socket(Socket);
                false -> ok
            end,
            {ok, NewState}
    end.

%% Set the send timeout of the socket, undefined is the configured default.
%% This is a call to the port so only do it if the timeout actually changes
set_send_timeout(SendTO, #state{socket=Socket, driver_mod=DriverMod, send_timeout=CurrentSendTO} = State) ->
    case gen_rpc_helper:get_send_timeout(SendTO) of
        CurrentSendTO ->
            State;
        NewSendTO ->
            ok = DriverMod:set_send_timeout(Socket, NewSendTO),
            State#state{send_timeout=NewSendTO}
    end.

%% Connect and authenticate to the server of a node
connect(Node) ->
    case gen_rpc_helper:get_client_config_per_node(Node) of
        {error, Reason} ->
            ?log(error, "event=external_source_error action=stopping reason=\"~p\"", [Reason]),
            {error, {badrpc, {external_source_error, Reason}}};
        {Driver, Port} ->
            {DriverMod, _DriverClosed, _DriverError} = gen_rpc_helper:get_client_driver_options(Driver),
            ?log(info, "event=initializing_client driver=~s node=\"~s\" port=~B", [Driver, Node, Port]),
            case DriverMod:connect(Node, Port) of
                {ok, Socket} ->
                    case DriverMod:authenticate_to_server(Node, Socket) of
                        ok ->
                            {ok, Driver, Socket};
                        {error, ReasonTuple} ->
                            ?log(error, "event=client_authentication_failed driver=~s reason=\"~p\"", [Driver, ReasonTuple]),
                            {error, ReasonTuple}
                    end;
                {error, {_Class,Reason}} ->
                    %% This should be badtcp but to conform with
                    %% the RPC library we return badrpc
                    {error, {badrpc,Reason}}
            end
    end.

%% Returns the process of the client of a node, asking the dispatcher
%% to start it if it does not exist
get_client(NodeOrTuple) ->
    %% Create a unique name for the client because we register as such
    PidName = gen_rpc_helper:make_process_name("client", NodeOrTuple),
    case erlang:whereis(PidName) of
        undefined ->
            ?log(info, "event=client_process_not_found target=\"~p\" action=spawning_client", [NodeOrTuple]),
            gen_rpc_dispatcher:start_client(NodeOrTuple);
        Pid ->
            ?log_debug("event=client_process_found pid=\"~p\" target=\"~p\"", [Pid, NodeOrTuple]),
            {ok, Pid}
    end.

%% Send a cast to the client of a node. If the client is already running this
%% happens right away. Starting a client can block while connecting to the
%% node, so that is left to a separate process
cast_to_client(NodeOrTuple, Cast, SendTO) ->
    case erlang:whereis(gen_rpc_helper:make_process_name("client", NodeOrTuple)) of
        undefined ->
            _WorkerPid = erlang:spawn(?MODULE, cast_worker, [NodeOrTuple, Cast, SendTO]),
            ok;
        Pid ->
            gen_server:cast(Pid, {Cast,SendTO})
    end.

cast_worker(NodeOrTuple, Cast, SendTO) ->
    case get_client(NodeOrTuple) of
        {ok, Pid} ->
            gen_server:cast(Pid, {Cast,SendTO});
        {error, _Reason} ->
            ok
    end.

async_call_worker(NodeOrTuple, M, F, A, Ref) ->
    TTL = gen_rpc_helper:get_async_call_inactivity_timeout(),
    SrvPid = case get_client(NodeOrTuple) of
        {ok, Pid} ->
            ok = gen_server:cast(Pid, {{async_call,M,F,A}, self(), Ref}),
            Pid;
        {error, {badrpc,_} = RpcError} ->
            RpcError
    end,
    Reply = case SrvPid of
        _ when is_pid(SrvPid) ->
            receive
                %% Wait for the reply from the node's gen_rpc client process
                {SrvPid,Ref,async_call,SrvReply} ->
                    SrvReply
            after
                TTL ->
                    exit({error, async_call_cleanup_timeout_reached})
            end;
        _ ->
            SrvPid
    end,
    %% Wait for a yield request from the caller
    receive
        {YieldPid,Ref,yield} ->
            YieldPid ! {self(), Ref, async_call, Reply}
    after
        TTL ->
            exit({error, async_call_cleanup_timeout_reached})
    end.

parse_multicall_results(Keys, Nodes, Timeout) ->
    AsyncResults = [nb_yield(Key, Timeout) || Key <- Keys],
    {RealResults, RealBadNodes, _} = lists:foldl(fun
        ({value, {BadReply, _Reason}}, {Results, BadNodes, [Node|RestNodes]}) when BadReply =:= badrpc; BadReply =:= badtcp ->
            {Results, [Node|BadNodes], RestNodes};
        ({value, Value}, {Results, BadNodes, [_Node|RestNodes]}) ->
            {[Value|Results], BadNodes, RestNodes};
        (timeout, {Results, BadNodes, [Node|RestNodes]}) ->
            {Results, [Node|BadNodes], RestNodes}
    end, {[], [], Nodes}, AsyncResults),
    {RealResults, RealBadNodes}.

parse_sbcast_results(Nodes, Ref) ->
    Timeout = gen_rpc_helper:get_sbcast_receive_timeout(),
    parse_sbcast_results(Nodes, Ref, {[], []}, Timeout).

parse_sbcast_results([Node|Nodes], Ref, {Good, Bad}, Timeout) ->
    receive
        {Ref, Node, error} ->
            parse_sbcast_results(Nodes, Ref, {Good, [Node|Bad]}, Timeout);
        {Ref, Node, success} ->
            parse_sbcast_results(Nodes, Ref, {[Node|Good], Bad}, Timeout)
    after
        Timeout ->
            parse_sbcast_results(Nodes, Ref, {Good, [Node|Bad]}, Timeout)
    end;

parse_sbcast_results([], _Ref, Results, _Timeout) ->
    Results.
