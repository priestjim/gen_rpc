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

%%% Connection and reply timeouts from the TCP server
-define(TCP_SERVER_CONN_TIMEOUT, 5000).
-define(TCP_SERVER_SEND_TIMEOUT, 5000).
-define(TCP_SERVER_RECV_TIMEOUT, 5000).

%%% Local state
-record(state, {socket :: port()}).

%%% Supervisor functions
-export([start_link/1, stop/1]).

%%% FSM functions
-export([call/3, call/4, call/5, call/6, cast/3, cast/4, cast/5]).

-export([async_call/3, async_call/4, yield/1, nb_yield/1, nb_yield/2]).

-export([eval_everywhere/3, eval_everywhere/4, eval_everywhere/5]).

-export([multicall/3, multicall/4, multicall/5]).

%%% Behaviour callbacks
-export([init/1, handle_call/3, handle_cast/2,
        handle_info/2, terminate/2, code_change/3]).

%%% Process exports
-export([async_call_worker/5]).

%%% ===================================================
%%% Supervisor functions
%%% ===================================================
-spec start_link(node()) -> gen_server:startlink_ret().
start_link(Node) when is_atom(Node) ->
    PidName = gen_rpc_helper:make_process_name("client", Node),
    gen_server:start_link({local,PidName}, ?MODULE, {Node}, [{spawn_opt, [{priority, high}]}]).

-spec stop(node()) -> ok.
stop(Node) when is_atom(Node) ->
    gen_server:call(Node, stop).

%%% ===================================================
%%% Server functions
%%% ===================================================

%% Simple server call with no args and default timeout values
-spec call(node(), module(), atom()|function()) -> term() | {badrpc, term()} | {badtcp | term()}.
call(Node, M, F) ->
    call(Node, M, F, [], undefined, undefined).

%% Simple server call with args and default timeout values
-spec call(node(), module(), atom()|function(), list()) -> term() | {badrpc, term()} | {badtcp | term()}.
call(Node, M, F, A) ->
    call(Node, M, F, A, undefined, undefined).

%% Simple server call with custom receive timeout value
-spec call(node(), module(), atom()|function(), list(), timeout()) -> term() | {badrpc, term()} | {badtcp | term()}.
call(Node, M, F, A, RecvTO) ->
    call(Node, M, F, A, RecvTO, undefined).

%% Simple server call with custom receive and send timeout values
%% This is the function that all of the above call
-spec call(node(), module(), atom()|function(), list(), timeout() | undefined, timeout() | undefined) -> term() | {badrpc, term()} | {badtcp | term()}.
call(Node, M, F, A, RecvTO, SendTO) when is_atom(Node), is_atom(M), is_atom(F), is_list(A),
                                         RecvTO =:= undefined orelse ?is_timeout(RecvTO),
                                         SendTO =:= undefined orelse ?is_timeout(SendTO) ->
    %% Create a unique name for the client because we register as such
    PidName = gen_rpc_helper:make_process_name("client", Node),
    case whereis(PidName) of
        undefined ->
            ok = lager:info("event=client_process_not_found server_node=\"~s\" action=spawning_client", [Node]),
            case gen_rpc_dispatcher:start_client(Node) of
                {ok, NewPid} ->
                    %% We take care of CALL inside the gen_server
                    %% This is not resilient enough if the caller's mailbox is full
                    %% but it's good enough for now
                    do_call(NewPid, M, F, A, RecvTO, SendTO);
                {error, Reason} ->
                    Reason
            end;
        Pid ->
            ok = lager:debug("event=client_process_found pid=\"~p\" server_node=\"~s\"", [Pid, Node]),
            do_call(Pid, M, F, A, RecvTO, SendTO)
    end.

%% Simple server cast with no args and default timeout values
-spec cast(node(), module(), atom()|function()) -> true.
cast(Node, M, F) ->
    cast(Node, M, F, [], undefined).

%% Simple server cast with args and default timeout values
-spec cast(node(), module(), atom()|function(), list()) -> true.
cast(Node, M, F, A) ->
    cast(Node, M, F, A, undefined).

%% Simple server cast with custom send timeout value
%% This is the function that all of the above casts call
-spec cast(node(), module(), atom()|function(), list(), timeout() | undefined) -> true.
cast(Node, M, F, A, SendTO) when is_atom(Node), is_atom(M), is_atom(F), is_list(A),
                                 SendTO =:= undefined orelse ?is_timeout(SendTO) ->
    %% Create a unique name for the client because we register as such
    PidName = gen_rpc_helper:make_process_name("client", Node),
    case whereis(PidName) of
        undefined ->
            ok = lager:info("event=client_process_not_found server_node=\"~s\" action=spawning_client", [Node]),
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
            ok = lager:debug("event=client_process_found pid=\"~p\" server_node=\"~s\"", [Pid, Node]),
            ok = gen_server:cast(Pid, {{cast,M,F,A},SendTO}),
            true
    end.

%% Evaluate {M, F, A} on connected nodes.
-spec eval_everywhere([node()], module(), atom()|function()) -> abcast.
eval_everywhere(Nodes, M, F) ->
    eval_everywhere(Nodes, M, F, [], undefined).

%% Evaluate {M, F, A} on connected nodes.
-spec eval_everywhere([node()], module(), atom()|function(), list()) -> abcast.
eval_everywhere(Nodes, M, F, A) ->
    eval_everywhere(Nodes, M, F, A, undefined).

%% Evaluate {M, F, A} on connected nodes.
-spec eval_everywhere([node()], module(), atom()|function(), list(), timeout() | undefined) -> abcast.
eval_everywhere(Nodes, M, F, A, SendTO) when is_list(Nodes), is_atom(M), is_atom(F), is_list(A),
                                             SendTO =:= undefined orelse ?is_timeout(SendTO) ->
    [cast(Node, M, F, A, SendTO) || Node <- Nodes],
    abcast.

%% Simple server async_call with no args
-spec async_call(Node::node(), M::module(), F::atom()|function()) -> term() | {badrpc, term()} | {badtcp | term()}.
async_call(Node, M, F)->
    async_call(Node, M, F, []).

%% Simple server async_call with args
-spec async_call(Node::node(), M::module(), F::atom()|function(), A::list()) -> term() | {badrpc, term()} | {badtcp | term()}.
async_call(Node, M, F, A) when is_atom(Node), is_atom(M), is_atom(F), is_list(A) ->
    Ref = erlang:make_ref(),
    Pid = erlang:spawn(?MODULE, async_call_worker, [Node, M, F, A, Ref]),
    {Pid, Ref}.

%% Simple server yield with key. Delegate to nb_yield. Default timeout form configuration.
-spec yield(tuple()) -> term() | {badrpc, term()}.
yield(Key) ->
    {value,Result} = nb_yield(Key, infinity),
    Result.

%% Simple server non-blocking yield with key, default timeout value of 0
-spec nb_yield(tuple()) -> {value, term()} | {badrpc, term()}.
nb_yield(Key)->
    nb_yield(Key, 0).

%% Simple server non-blocking yield with key and custom timeout value
-spec nb_yield(tuple(), timeout()) -> {value, term()} | {badrpc, term()}.
nb_yield({Pid,Ref}, Timeout) when is_pid(Pid), is_reference(Ref), ?is_timeout(Timeout) ->
    Pid ! {self(), Ref, yield},
    receive
        {Pid, Ref, async_call, Result} ->
            {value,Result}
    after
        Timeout ->
            ok = lager:debug("event=nb_yield_timeout async_call_pid=\"~p\" async_call_ref=\"~p\"", [Pid, Ref]),
            timeout
    end.

%% "Concurrent" call to a set of servers
-spec multicall(module(), atom(), list()) -> {list(), list()}.
multicall(M, F, A) when is_atom(M), is_atom(F), is_list(A) ->
    multicall([node()|gen_rpc:nodes()], M, F, A).

-spec multicall(list() | module(), module() | atom(), atom() | list(), list() | timeout()) -> {list(), list()}.
multicall(M, F, A, Timeout) when is_atom(M), is_atom(F), is_list(A), ?is_timeout(Timeout) ->
    multicall([node()|gen_rpc:nodes()], M, F, A, Timeout);

multicall(Nodes, M, F, A) when is_list(Nodes), is_atom(M), is_atom(F), is_list(A) ->
    Keys = [async_call(Node, M, F, A) || Node <- Nodes],
    parse_multicall_results(Keys, Nodes, undefined).

-spec multicall(list(), module(), atom(), list(), timeout()) -> {list(), list()}.
multicall(Nodes, M, F, A, Timeout) when is_list(Nodes), is_atom(M), is_atom(F), is_list(A), ?is_timeout(Timeout) ->
    Keys = [async_call(Node, M, F, A) || Node <- Nodes],
    parse_multicall_results(Keys, Nodes, Timeout).

%%% ===================================================
%%% Behaviour callbacks
%%% ===================================================
init({Node}) ->
    _OldVal = erlang:process_flag(trap_exit, true),
    TTL = gen_rpc_helper:get_inactivity_timeout(?MODULE),
    ConnTO = gen_rpc_helper:get_connect_timeout(),
    ok = lager:info("event=initializing_client node=\"~s\" connect_timeout=~B inactivity_timeout=\"~p\"", [Node, ConnTO, TTL]),
    case connect_to_tcp_server(Node) of
        {ok, IpAddress, Port} ->
            ok = lager:debug("event=remote_server_started_successfully server_node=\"~s\" remote_port=\"~B\"", [Node, Port]),
            case gen_tcp:connect(IpAddress, Port, gen_rpc_helper:default_tcp_opts(?DEFAULT_TCP_OPTS), ConnTO) of
                {ok, Socket} ->
                    ok = lager:debug("event=connecting_to_server server_node=\"~s\" peer=\"~s\" result=success",
                                     [Node, gen_rpc_helper:peer_to_string({IpAddress, Port})]),
                    {ok, #state{socket=Socket}, TTL};
                {error, Reason} ->
                    ok = lager:error("event=connecting_to_server server_node=\"~s\" server_ip=\"~s:~B\" result=failure reason=\"~p\"",
                                     [Node, gen_rpc_helper:peer_to_string({IpAddress, Port}), Reason]),
                    {stop, {badtcp,Reason}}
            end;
        {error, Reason} ->
            {stop, {badrpc,Reason}}
    end.

%% This is the actual CALL handler
handle_call({{call,_M,_F,_A} = PacketTuple, SendTO}, Caller, #state{socket=Socket} = State) ->
    Packet = erlang:term_to_binary({PacketTuple, Caller}),
    ok = lager:debug("message=call event=constructing_call_term socket=\"~p\" caller=\"~p\"", [Socket, Caller]),
    ok = inet:setopts(Socket, [{send_timeout, gen_rpc_helper:get_send_timeout(SendTO)}]),
    case gen_tcp:send(Socket, Packet) of
        {error, timeout} ->
            ok = lager:error("message=call event=transmission_failed socket=\"~p\" caller=\"~p\" reason=\"timeout\"", [Socket, Caller]),
            {stop, {badtcp,send_timeout}, {badtcp,send_timeout}, State};
        {error, Reason} ->
            ok = lager:error("message=call event=transmission_failed socket=\"~p\" caller=\"~p\" reason=\"~p\"", [Socket, Caller, Reason]),
            {stop, {badtcp,Reason}, {badtcp,Reason}, State};
        ok ->
            ok = lager:debug("message=call event=transmission_succeeded socket=\"~p\" caller=\"~p\"", [Socket, Caller]),
            %% We need to enable the socket and perform the call only if the call succeeds
            ok = inet:setopts(Socket, [{active, once}]),
            {noreply, State, gen_rpc_helper:get_inactivity_timeout(?MODULE)}
    end;

%% Gracefully terminate
handle_call(stop, _Caller, State) ->
    ok = lager:debug("event=stopping_client socket=\"~p\"", [State#state.socket]),
    {stop, normal, ok, State};

%% Catch-all for calls - die if we get a message we don't expect
handle_call(Msg, _Caller, State) ->
    ok = lager:critical("event=uknown_call_received socket=\"~p\" message=\"~p\" action=stopping", [State#state.socket, Msg]),
    {stop, {unknown_call, Msg}, {unknown_call, Msg}, State}.

%% This is the actual CAST handler for CAST
handle_cast({{cast,_M,_F,_A} = PacketTuple, SendTO}, #state{socket=Socket} = State) ->
    %% Cast requests do not need a reference
    Packet = erlang:term_to_binary(PacketTuple),
    ok = lager:debug("message=cast event=constructing_cast_term socket=\"~p\"", [Socket]),
    %% Set the send timeout and do not run in active mode - we're a cast!
    ok = inet:setopts(Socket, [{send_timeout, gen_rpc_helper:get_send_timeout(SendTO)}]),
    case gen_tcp:send(Socket, Packet) of
        {error, timeout} ->
            %% Terminate will handle closing the socket
            ok = lager:error("message=cast event=transmission_failed socket=\"~p\" reason=\"timeout\"", [Socket]),
            {stop, {badtcp,send_timeout}, State};
        {error, Reason} ->
            ok = lager:error("message=cast event=transmission_failed socket=\"~p\" reason=\"~p\"", [Socket, Reason]),
            {stop, {badtcp,Reason}, State};
        ok ->
            ok = lager:debug("message=cast event=transmission_succeeded socket=\"~p\"", [Socket]),
            {noreply, State, gen_rpc_helper:get_inactivity_timeout(?MODULE)}
    end;

%% This is the actual ASYNC CALL handler
handle_cast({{async_call,_M,_F,_A} = PacketTuple, Caller, Ref}, #state{socket=Socket} = State) ->
    Packet = erlang:term_to_binary({PacketTuple, {Caller,Ref}}),
    ok = lager:debug("message=call event=constructing_async_call_term socket=\"~p\" worker_pid=\"~p\" async_call_ref=\"~p\"",
                     [Socket, Caller, Ref]),
    ok = inet:setopts(Socket, [{send_timeout, gen_rpc_helper:get_send_timeout(undefined)}]),
    case gen_tcp:send(Socket, Packet) of
        {error, timeout} ->
            ok = lager:error("message=async_call event=transmission_failed socket=\"~p\" worker_pid=\"~p\" call_ref=\"~p\" reason=\"timeout\"",
                             [Socket, Caller, Ref]),
            {stop, {badtcp,send_timeout}, {badtcp,send_timeout}, State};
        {error, Reason} ->
            ok = lager:error("message=async_call event=transmission_failed socket=\"~p\" worker_pid=\"~p\" call_ref=\"~p\" reason=\"~p\"",
                             [Socket, Caller, Ref, Reason]),
            {stop, {badtcp,Reason}, {badtcp,Reason}, State};
        ok ->
            ok = lager:debug("message=async_call event=transmission_succeeded socket=\"~p\" worker_pid=\"~p\" call_ref=\"~p\"",
                             [Socket, Caller, Ref]),
            %% We need to enable the socket and perform the call only if the call succeeds
            ok = inet:setopts(Socket, [{active, once}]),
            %% Reply will be handled from the worker
            {noreply, State, gen_rpc_helper:get_inactivity_timeout(?MODULE)}
    end;

%% Catch-all for casts - die if we get a message we don't expect
handle_cast(Msg, State) ->
    ok = lager:critical("event=uknown_cast_received socket=\"~p\" message=\"~p\" action=stopping", [State#state.socket, Msg]),
    {stop, {unknown_cast, Msg}, State}.

%% Handle any TCP packet coming in
handle_info({tcp,Socket,Data}, #state{socket=Socket} = State) ->
    _Reply = try erlang:binary_to_term(Data) of
        {call, Caller, Reply} ->
            ok = lager:debug("message=tcp event=call_reply_received caller=\"~p\" action=sending_reply", [Caller]),
            gen_server:reply(Caller, Reply);
        {async_call, {Caller, Ref}, Reply} ->
            ok = lager:debug("message=tcp event=async_call_reply_received caller=\"~p\" action=sending_reply", [Caller]),
            Caller ! {self(), Ref, async_call, Reply};
        OtherData ->
            ok = lager:error("message=tcp event=erroneous_reply_received socket=\"~p\" data=\"~p\" action=ignoring", [Socket, OtherData])
    catch
        error:badarg ->
            ok = lager:error("message=tcp event=corrupt_data_received socket=\"~p\" action=ignoring", [Socket])
    end,
    ok = inet:setopts(Socket, [{active, once}]),
    {noreply, State, gen_rpc_helper:get_inactivity_timeout(?MODULE)};

handle_info({tcp_closed, Socket}, #state{socket=Socket} = State) ->
    ok = lager:warning("message=tcp_closed event=tcp_socket_closed socket=\"~p\" action=stopping", [Socket]),
    {stop, normal, State};

handle_info({tcp_error, Socket, Reason}, #state{socket=Socket} = State) ->
    ok = lager:warning("message=tcp_error event=tcp_socket_error socket=\"~p\" reason=\"~p\" action=stopping", [Socket, Reason]),
    {stop, normal, State};

%% Handle the inactivity timeout gracefully
handle_info(timeout, State) ->
    ok = lager:info("message=timeout event=client_inactivity_timeout socket=\"~p\" action=stopping", [State#state.socket]),
    {stop, normal, State};

%% Catch-all for info - our protocol is strict so die!
handle_info(Msg, State) ->
    ok = lager:critical("event=uknown_message_received socket=\"~p\" message=\"~p\" action=stopping", [State#state.socket, Msg]),
    {stop, {unknown_info, Msg}, State}.

%% Stub functions
code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

terminate(_Reason, #state{socket=Socket}) ->
    ok = lager:debug("socket=\"~p\"", [Socket]),
    ok.

%%% ===================================================
%%% Private functions
%%% ===================================================
connect_to_tcp_server(Node) ->
    Host = gen_rpc_helper:host_from_node(Node),
    Port = gen_rpc_helper:get_tcp_server_port(),
    case gen_tcp:connect(Host, Port, gen_rpc_helper:default_tcp_opts(?DEFAULT_TCP_OPTS), ?TCP_SERVER_CONN_TIMEOUT) of
        {ok, Socket} ->
            ok = lager:debug("event=connecting_to_server peer=\"~s\" socket=\"~p\" result=success", [Node, Socket]),
            {ok, {IpAddress, _Port}} = inet:peername(Socket),
            get_node_port(Socket, IpAddress);
        {error, Reason} ->
            ok = lager:error("event=connecting_to_server peer=\"~s\" result=failure reason=\"~p\"", [Node, Reason]),
            {error, Reason}
    end.

get_node_port(Socket, IpAddress) ->
    Cookie = erlang:get_cookie(),
    Packet = erlang:term_to_binary({start_gen_rpc_server, Cookie}),
    ok = inet:setopts(Socket, [{send_timeout, ?TCP_SERVER_SEND_TIMEOUT}]),
    case gen_tcp:send(Socket, Packet) of
        {error, Reason} ->
            ok = lager:error("event=transmission_failed socket=\"~p\" reason=\"~p\"", [Socket, Reason]),
            ok = gen_tcp:close(Socket),
            {error, Reason};
        ok ->
            ok = lager:debug("event=transmission_succeeded socket=\"~p\"", [Socket]),
            case gen_tcp:recv(Socket, 0, ?TCP_SERVER_RECV_TIMEOUT) of
                {ok, RecvPacket} ->
                    try erlang:binary_to_term(RecvPacket) of
                        {gen_rpc_server_started, Port} ->
                            ok = gen_tcp:close(Socket),
                            {ok, IpAddress, Port};
                        {connection_rejected, invalid_cookie} ->
                            ok = lager:debug("event=reception_failed socket=\"~p\" reason=\"invalid_cookie\"", [Socket]),
                            ok = gen_tcp:close(Socket),
                            {error, badrpc};
                        _Else ->
                            ok = lager:debug("event=reception_failed socket=\"~p\" reason=\"invalid_payload\"", [Socket]),
                            ok = gen_tcp:close(Socket),
                            {error, badrpc}
                    catch
                        error:badarg ->
                            ok = gen_tcp:close(Socket),
                            ok = lager:debug("event=reception_failed socket=\"~p\" reason=\"invalid_erlang_term\"", [Socket]),
                            {error, badrpc}
                    end;
                {error, Reason} ->
                    ok = lager:debug("event=reception_failed socket=\"~p\" reason=\"~p\"", [Socket, Reason]),
                    ok = gen_tcp:close(Socket),
                    {error, Reason}
            end
    end.

do_call(Pid, M, F, A, RecvTO, SendTO) ->
    try
        gen_server:call(Pid, {{call,M,F,A}, SendTO}, gen_rpc_helper:get_receive_timeout(RecvTO))
    catch
        exit:{timeout,_Reason} ->
            {badrpc,timeout}
    end.

async_call_worker(Node, M, F, A, Ref) ->
    TTL = gen_rpc_helper:get_async_call_inactivity_timeout(),
    PidName = gen_rpc_helper:make_process_name("client", Node),
    SrvPid = case whereis(PidName) of
        undefined ->
            ok = lager:info("event=client_process_not_found server_node=\"~s\" action=spawning_client", [Node]),
            case gen_rpc_dispatcher:start_client(Node) of
                {ok, NewPid} ->
                    ok = gen_server:cast(NewPid, {{async_call,M,F,A}, self(), Ref}),
                    NewPid;
                {error, {badrpc, _} = RpcError} ->
                    RpcError
            end;
        Pid ->
            ok = lager:debug("event=client_process_found pid=\"~p\" server_node=\"~s\"", [Pid, Node]),
            ok = gen_server:cast(Pid, {{async_call,M,F,A}, self(), Ref}),
            Pid
    end,
    case SrvPid of
        SrvPid when is_pid(SrvPid) ->
            receive
                %% Wait for the reply from the node's gen_rpc client process
                {SrvPid,Ref,async_call,Reply} ->
                    %% Wait for a yield request from the caller
                    receive
                        {YieldPid,Ref,yield} ->
                            YieldPid ! {self(), Ref, async_call, Reply}
                    after
                        TTL ->
                            exit({error, async_call_cleanup_timeout_reached})
                    end
            after
                TTL ->
                    exit({error, async_call_cleanup_timeout_reached})
            end;
        TRpcError ->
            %% Wait for a yield request from the caller
            receive
                {YieldPid,Ref,yield} ->
                    YieldPid ! {self(), Ref, async_call, TRpcError}
            after
                TTL ->
                    exit({error, async_call_cleanup_timeout_reached})
            end
    end.

parse_multicall_results(Keys, Nodes, undefined) ->
    parse_multicall_results(Keys, Nodes, infinity);

parse_multicall_results(Keys, Nodes, Timeout) ->
    AsyncResults = [nb_yield(Key, Timeout) || Key <- Keys],
    {RealResults, RealBadNodes, _} = lists:foldl(fun
        ({value, {BadReply, _Reason}}, {Results, BadNodes, [Node|RestNodes]})
        when BadReply =:= badrpc; BadReply =:= badtcp ->
            {Results, [Node|BadNodes], RestNodes};
        ({value, Value}, {Results, BadNodes, [_Node|RestNodes]}) ->
            {[Value|Results], BadNodes, RestNodes};
        (timeout, {Results, BadNodes, [Node|RestNodes]}) ->
            {Results, [Node|BadNodes], RestNodes}
    end, {[], [], Nodes}, AsyncResults),
    {RealResults, RealBadNodes}.