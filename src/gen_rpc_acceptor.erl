%%% -*-mode:erlang;coding:utf-8;tab-width:4;c-basic-offset:4;indent-tabs-mode:()-*-
%%% ex: set ft=erlang fenc=utf-8 sts=4 ts=4 sw=4 et:
%%%
%%% Copyright 2015 Panagiotis Papadomitsos, Inc. All Rights Reserved.
%%%
%%% Original concept inspired and some code copied from
%%% https://erlangcentral.org/wiki/index.php?title=Building_a_Non-blocking_TCP_server_using_OTP_principles

-module(gen_rpc_acceptor).
-author("Panagiotis Papadomitsos <pj@ezgr.net>").

%%% Debug printing messages
-include("include/debug.hrl").

%%% Behaviour
-behaviour(gen_fsm).

%% Local state
-record(state, {socket = undefined :: port() | undefined,
                client_ip :: tuple(),
                client_node :: atom()}).

%%% Server functions
-export([start_link/2, set_socket/2, stop/1]).

%% gen_fsm callbacks
-export([init/1, handle_event/3, handle_sync_event/4,
        handle_info/3, terminate/3, code_change/4]).

%% FSM States
-export([wait_for_socket/2, wait_for_data/2]).

%%% ===================================================
%%% Supervisor functions
%%% ===================================================
start_link(ClientIp, Node) when is_tuple(ClientIp), is_atom(Node) ->
    gen_fsm:start_link(?MODULE, {ClientIp, Node}, []).

stop(Pid) when is_pid(Pid) ->
     gen_fsm:sync_send_all_state_event(Pid, stop).

%%% ===================================================
%%% Server functions
%%% ===================================================
set_socket(Pid, Socket) when is_pid(Pid), is_port(Socket) ->
    gen_fsm:send_event(Pid, {socket_ready, Socket}).

%%% ===================================================
%%% Behaviour callbacks
%%% ===================================================
init({ClientIp, Node}) ->
    ?debug("Initializing acceptor for node [~s] with IP [~w]", [Node, ClientIp]),
    process_flag(trap_exit, true),
    %% Store the client's IP and the node in our state
    {ok, wait_for_socket, #state{client_ip = ClientIp, client_node = Node}}.

wait_for_socket({socket_ready, Socket},
                #state{client_ip = ClientIp} = State) when is_port(Socket) ->
    %% Filter the ports we're willing to accept connections from
    {ok, {Ip, _Port}} = inet:peername(Socket),
    if
        ClientIp =/= Ip ->
            ?debug("Rejecting connection from client IP [~w] as it is different from [~w]", [Ip, ClientIp]),
            {stop, {error, invalid_client_ip}, State};
        true ->
            % Now we own the socket
            ?debug("Acquiring ownership for socket [~p] from client IP [~w]", [Socket, ClientIp]),
            ok = inet:setopts(Socket, [{active, once}, {packet, 4}, binary]),
            {next_state, wait_for_data, State#state{socket=Socket}}
    end;

wait_for_socket(Other, State) ->
    error_logger:error_msg("State: wait_for_socket. Unexpected message: ~p\n", [Other]),
    %% Allow to receive async messages
    {next_state, wait_for_socket, State}.

%% Notification event coming from client
wait_for_data({data, Data}, #state{socket=Socket, client_node = Node} = State) ->
    %% The meat of the whole project: process a function call and return
    %% the data
    ?debug("Received request from node [~s]. Processing.", [Node]),
    try erlang:binary_to_term(Data) of
        {Node, {call, M, F, A}} ->
            ?debug("Received CALL request from node [~s] with [M:~s][F:~s][A:~p].", [Node, M, F, A]),
            Result = erlang:apply(M, F, A),
            Packet = erlang:term_to_binary(Result),
            case gen_tcp:send(Socket, Packet) of
                ok ->
                    ?debug("Replied to CALL request from node [~s] with [M:~s][F:~s][A:~p].", [Node, M, F, A]),
                    ok = inet:setopts(Socket, [{active, once}]),
                    {next_state, wait_for_data, State};
                {error, Reason} ->
                    ?debug("Failed to reply to CALL request from node [~s] with [M:~s][F:~s][A:~p] with reason [~w]", [Node, M, F, A, Reason]),
                    {stop, {badtcp, Reason}, State}
            end;
        {Node, {cast, M, F, A}} ->
            ?debug("Received CAST request from node [~s] with [M:~s][F:~s][A:~p].", [Node, M, F, A]),
            _Pid = erlang:spawn(M, F, A),
            ok = inet:setopts(Socket, [{active, once}]),
            {next_state, wait_for_data, State};
        OtherData ->
            ?debug("Received erroneous request from node [~s] with payload [~p]", [Node, OtherData]),
            error_logger:error_msg("Bad data protocol data received: ~p", [OtherData]),
            ok = inet:setopts(Socket, [{active, once}]),
            {next_state, wait_for_data, State}
    catch
        error:badarg ->
            {stop, {badtcp, corrupt_data}, State}
    end;

wait_for_data(timeout, State) ->
    error_logger:error_msg("~p Client connection timeout - closing.\n", [self()]),
    {stop, normal, State};

wait_for_data(Data, State) ->
    io:format("~p Ignoring data: ~p\n", [self(), Data]),
    {next_state, wait_for_data, State}.

handle_event(Event, StateName, State) ->
    {stop, {StateName, undefined_event, Event}, State}.

%% Gracefully terminate
handle_sync_event(stop, _From, _StateName, State) ->
    {stop, normal, ok, State};

handle_sync_event(Event, _From, StateName, State) ->
    {stop, {StateName, undefined_event, Event}, State}.

%% Incoming data handlers
handle_info({tcp, Socket, Dat}, wait_for_data, #state{socket=Socket} = State) when Socket =/= undefined ->
    wait_for_data({data, Dat}, State);

handle_info({tcp_closed, Socket}, _StateName,
            #state{client_ip= ClientIp, client_node = Node, socket=Socket} = State) ->
    error_logger:info_msg("~p Client ~p with remote IP ~p and node name ~s disconnected.\n", [self(), Socket, ClientIp, Node]),
    {stop, normal, State};
handle_info({tcp_error, Socket, Reason}, _StateName,
            #state{client_ip= ClientIp, client_node = Node, socket=Socket} = State) ->
    error_logger:info_msg("~p Error while receiving from client ~p with remote IP ~p and node name ~s: ~p .\n", [self(), Socket, ClientIp, Node, Reason]),
    {stop, normal, State};

handle_info(_Info, _StateName, State) ->
    {stop, {error, unknown_message}, State}.

code_change(_OldVsn, StateName, State, _Extra) ->
    {ok, StateName, State}.

%% Terminate normally if we haven't received the socket yet
terminate(_Reason, _StateName, #state{socket=undefined}) ->
    ok;
%% Terminate by closing the socket
terminate(_Reason, _StateName, #state{socket=Socket}) ->
    (catch gen_tcp:close(Socket)),
    ok.
