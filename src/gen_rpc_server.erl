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

%%% Include this library's name macro
-include("app.hrl").

%%% Local state
-record(state, {client_ip :: tuple(),
        client_node :: node(),
        socket :: port(),
        acceptor_pid :: pid(),
        acceptor :: non_neg_integer()}).

%%% The TCP options that should be copied from the listener to the acceptor
-define(ACCEPTOR_TCP_OPTS, [nodelay,
        send_timeout_close,
        delay_send,
        linger,
        reuseaddr,
        keepalive,
        tos,
        active]).

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
    Name = gen_rpc_helper:make_process_name(<<"gen_rpc_server_">>, Node),
    gen_server:start_link({local,Name}, ?MODULE, {Node}, [{spawn_opt, [{priority, high}]}]).

stop(Pid) when is_pid(Pid) ->
    gen_server:call(Pid, stop).

%%% ===================================================
%%% Server functions
%%% ===================================================
-spec get_port(pid()) -> {'ok', inet:port_number()} | {'error', term()} | term(). %dialyzer complains without term().
get_port(Pid) when is_pid(Pid) ->
    gen_server:call(Pid, get_port).

%%% ===================================================
%%% Behaviour callbacks
%%% ===================================================
init({Node}) ->
    ok = lager:info("function=init client_node=\"~s\"", [Node]),
    process_flag(trap_exit, true),
    ClientIp = get_remote_node_ip(Node),
    case gen_tcp:listen(0, gen_rpc_helper:default_tcp_opts(?DEFAULT_TCP_OPTS)) of
        {ok, Socket} ->
            ok = lager:info("function=init event=listener_started_successfully client_node=\"~s\"", [Node]),
            {ok, Ref} = prim_inet:async_accept(Socket, -1),
            {ok, #state{client_ip = ClientIp,
                        client_node = Node,
                        socket = Socket,
                        acceptor = Ref}};
        {error, Reason} ->
            ok = lager:critical("function=init event=failed_to_start_listener client_node=\"~s\" reason=\"~p\"", [Node, Reason]),
            {stop, Reason}
    end.

%% Returns the dynamic port the current TCP server listens to
handle_call(get_port, _From, #state{socket=Socket} = State) ->
    {ok, Port} = inet:port(Socket),
    ok = lager:debug("function=handle_call message=get_port socket=\"~p\" port=~B", [Socket,Port]),
    {reply, {ok, Port}, State};

%% Gracefully stop
handle_call(stop, _From, State) ->
    ok = lager:debug("function=handle_call message=stop event=stopping_server socket=\"~p\"", [State#state.socket]),
    {stop, normal, ok, State};

%% Catch-all for calls - die if we get a message we don't expect
handle_call(Msg, _From, State) ->
    ok = lager:critical("function=handle_call event=unknown_call_received socket=\"~p\" message=\"~p\" action=stopping", [State#state.socket, Msg]),
    {stop, {unknown_call, Msg}, {unknown_call, Msg}, State}.

%% Catch-all for casts - die if we get a message we don't expect
handle_cast(Msg, State) ->
    ok = lager:critical("function=handle_cast event=unknown_cast_received socket=\"~p\" message=\"~p\" action=stopping", [State#state.socket, Msg]),
    {stop, {unknown_cast, Msg}, State}.

handle_info({inet_async, ListSock, Ref, {ok, AccSocket}},
            #state{client_ip=ClientIp, client_node=Node, socket=ListSock, acceptor=Ref} = State) ->
    try
        ok = lager:info("function=handle_info event=client_connection_received client_ip=\"~p\" client_node=\"~s\" socket=\"~p\" action=starting_acceptor",
                          [ClientIp, Node, ListSock]),
        %% Start an acceptor process. We need to provide the acceptor
        %% process with our designated node IP and name so enforcement
        %% of those attributes can be made for security reasons.
        {ok, AccPid} = gen_rpc_acceptor_sup:start_child(ClientIp, Node),
        %% Link to acceptor, if they die so should we, since we are single-receiver
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
            {ok, NewRef} -> {noreply, State#state{acceptor=NewRef,acceptor_pid=AccPid}, hibernate};
            {error, NewRef} -> exit({async_accept, inet:format_error(NewRef)})
        end
    catch
        exit:ExitReason ->
            ok = lager:error("function=handle_info message=inet_async event=unknown_error socket=\"~p\" error=\"~p\" action=stopping",
                            [ListSock, ExitReason]),
            {stop, ExitReason, State}
    end;

%% Handle async socket errors gracefully
handle_info({inet_async, ListSock, Ref, Error}, #state{socket=ListSock,acceptor=Ref} = State) ->
    ok = lager:error("function=handle_info message=inet_async event=listener_error socket=\"~p\" error=\"~p\" action=stopping",
                    [ListSock, Error]),
    {stop, Error, State};

%% Handle exit messages from our acceptor gracefully
handle_info({'EXIT', AccPid, Reason}, #state{socket=Socket,acceptor_pid=AccPid} = State) ->
    ok = lager:notice("function=handle_info message=acceptor_exit socket=\"~p\" acceptor_pid=\"~p\" reason=\"~p\" action=stopping",
                    [Socket, AccPid, Reason]),
    {stop, Reason, State};

%% Catch-all for info - our protocol is strict so die!
handle_info(Msg, State) ->
    ok = lager:critical("function=handle_info event=uknown_message_received socket=\"~p\" message=\"~p\" action=stopping", [State#state.socket, Msg]),
    {stop, {unknown_message, Msg}, State}.

%% Terminate cleanly by closing the listening socket
terminate(_Reason, #state{socket=Socket}) ->
    ok = lager:debug("function=terminate socket=\"~p\"", [Socket]),
    _Pid = erlang:spawn(gen_rpc_server_sup, stop_child, [self()]),
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%%% ===================================================
%%% Private functions
%%% ===================================================

acceptor_tcp_opts() ->
    case gen_rpc_helper:otp_release() >= 18 of
        true ->
            [show_econnreset|?ACCEPTOR_TCP_OPTS];
        false ->
            ?ACCEPTOR_TCP_OPTS
    end.

%% Taken from prim_inet.  We are merely copying some socket options from the
%% listening socket to the new acceptor socket.
set_sockopt(ListSock, AccSocket) ->
    true = inet_db:register_socket(AccSocket, inet_tcp),
    case prim_inet:getopts(ListSock, acceptor_tcp_opts()) of
        {ok, Opts} ->
            case prim_inet:setopts(AccSocket, Opts) of
                ok    -> ok;
                Error -> gen_tcp:close(AccSocket), Error
            end;
        Error ->
            (catch gen_tcp:close(AccSocket)),
            Error
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
