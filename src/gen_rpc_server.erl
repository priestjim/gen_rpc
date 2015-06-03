%%% -*-mode:erlang;coding:utf-8;tab-width:4;c-basic-offset:4;indent-tabs-mode:()-*-
%%% ex: set ft=erlang fenc=utf-8 sts=4 ts=4 sw=4 et:
%%%
%%% Copyright 2015 Panagiotis Papadomitsos. All Rights Reserved.
%%%
%%% Original concept inspired and some code copied from
%%% https://erlangcentral.org/wiki/index.php?title=Building_a_Non-blocking_TCP_server_using_OTP_principles

-module(gen_rpc_server).
-author("Panagiotis Papadomitsos <pj@ezgr.net>").

%%% Behaviour
-behaviour(gen_server).

%%% Used for debug printing messages when in test
-include("include/debug.hrl").

%%% Local state
-record(state, {client_ip :: tuple(),
        client_node :: atom(),
        listener :: port(),
        acceptor_pid :: pid(),
        acceptor :: port()}).

%%% Default TCP options
-define(DEFAULT_TCP_OPTS, [binary, {packet,4}, {reuseaddr,true}, {send_timeout_close,true},
        {keepalive,true}, {backlog, 1024}, {active, false}]).

%%% Supervisor functions
-export([start_link/1, stop/1]).

%%% Server functions
-export([get_port/1]).

%%% Behaviour callbacks
-export([init/1, handle_call/3, handle_cast/2,
        handle_info/2, terminate/2, code_change/3]).

%%% ===================================================
%%% Supervisor functions
%%% ===================================================
start_link(Node) when is_atom(Node) ->
    gen_server:start_link(?MODULE, {Node}, []).

stop(Pid) when is_pid(Pid) ->
    gen_server:call(Pid, stop).

%%% ===================================================
%%% Server functions
%%% ===================================================
get_port(Pid) when is_pid(Pid) ->
    gen_server:call(Pid, get_port).

%%% ===================================================
%%% Behaviour callbacks
%%% ===================================================
init({Node}) ->
    ?debug("Initializing listener for node [~s]", [Node]),
    process_flag(trap_exit, true),
    ClientIp = get_remote_node_ip(Node),
    case gen_tcp:listen(0, ?DEFAULT_TCP_OPTS) of
        {ok, Socket} ->
            ?debug("Listener for node [~s] started successfully", [Node]),
            {ok, Ref} = prim_inet:async_accept(Socket, -1),
            {ok, #state{client_ip = ClientIp,
                        client_node = Node,
                        listener = Socket,
                        acceptor = Ref}};
        {error, Reason} ->
            {stop, Reason}
    end.

%% Returns the dynamic port the current TCP server listens to
handle_call(get_port, _From, #state{listener=Socket} = State) ->
    {ok, Port} = inet:port(Socket),
    ?debug("Port for socket [~p] is set to [~B]", [Socket, Port]),
    {reply, {ok, Port}, State};

%% Gracefully stop
handle_call(stop, _From, State) ->
    {stop, ok, State};

%% Stop on uknown message
handle_call(Request, _From, State) ->
    {stop, {unknown_call, Request}, State}.

%% Catch-all for cast messages
handle_cast(_Msg, State) ->
    {noreply, State}.

handle_info({inet_async, ListSock, Ref, {ok, AccSocket}},
            #state{client_ip=ClientIp, client_node=Node, listener=ListSock, acceptor=Ref} = State) ->
    try
        ?debug("Request received from node [~s] with IP [~w]. Starting acceptor process.", [Node, ClientIp]),
        %% Start an acceptor process. We need to provide the acceptor
        %% process with our designated node IP and name so enforcement
        %% of those attributes can be made for security reasons.
        %% We do NOT want to link to the process, if it dies, it's the
        %% client's responsibility to reconnect
        {ok, AccPid} = gen_rpc_acceptor_sup:start_child(ClientIp, Node),
        %% Link to acceptor, if they die so should we, since we a single-receiver
        %% to single-acceptor service
        true = erlang:link(AccPid),
        case set_sockopt(ListSock, AccSocket) of
            ok -> ok;
            {error, Reason} -> exit({set_sockopt, Reason})
        end,
        ok = gen_tcp:controlling_process(AccSocket, AccPid),
        ok = gen_rpc_acceptor:set_socket(AccPid, AccSocket),
        %% We want the acceptor to drop the connection, so we remain
        %% open to accepting new connections, otherwise
        %% passive connections will remain open and leave us prone to
        %% a DoS file descriptor depletion attack
        case prim_inet:async_accept(ListSock, -1) of
            {ok, NewRef} -> {noreply, State#state{acceptor=NewRef,acceptor_pid=AccPid}};
            {error, NewRef} -> exit({async_accept, inet:format_error(NewRef)})
        end
    catch
        exit:ExitReason ->
            {stop, ExitReason, State}
    end;

handle_info({inet_async, ListSock, Ref, Error}, #state{listener=ListSock, acceptor=Ref} = State) ->
    {stop, Error, State};

%% Handle exit messages from our acceptor gracefully
handle_info({'EXIT', AccPid, normal}, #state{listener=_Listener,acceptor_pid = AccPid} = State) ->
    ?debug("Server received Acceptor exit for socket [~p]. Exiting!", [_Listener]),
    {stop, normal, State};
%% Catch-all for info - ignore any message we don't care about
handle_info(_Info, State) ->
    {noreply, State}.

%% Terminate cleanly by closing the listening socket
%% TODO: Implement handling for exit signals from linked acceptor
%% process. We shoudn't die when they die but they should die when we
%% do.
terminate(_Reason, #state{listener=Listener}) ->
    ?debug("Server process for listener socket [~p] is exiting. Closing socket!", [Listener]),
    (catch gen_tcp:close(Listener)),
    _Pid = erlang:spawn(gen_rpc_server_sup, stop_child, [self()]),
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%%% ===================================================
%%% Private functions
%%% ===================================================
%% Taken from prim_inet.  We are merely copying some socket options from the
%% listening socket to the new acceptor socket.
set_sockopt(ListSock, AccSocket) ->
    true = inet_db:register_socket(AccSocket, inet_tcp),
    case prim_inet:getopts(ListSock, [active, nodelay, keepalive, delay_send, priority, tos]) of
    {ok, Opts} ->
        case prim_inet:setopts(AccSocket, Opts) of
            ok    -> ok;
            Error -> gen_tcp:close(AccSocket), Error
        end;
    Error ->
        gen_tcp:close(AccSocket), Error
    end.

%% For loopback communication and performance testing
get_remote_node_ip(Node) when Node =:= node() ->
    {127,0,0,1};
get_remote_node_ip(Node) ->
    {ok, NodeInfo} = net_kernel:node_info(Node),
    {address, AddressInfo} = lists:keyfind(address, 1, NodeInfo),
    {net_address, {Ip, _Port}, _Name, _Proto, _Channel} = AddressInfo,
    Ip.
