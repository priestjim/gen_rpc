%%% -*-mode:erlang;coding:utf-8;tab-width:4;c-basic-offset:4;indent-tabs-mode:()-*-
%%% ex: set ft=erlang fenc=utf-8 sts=4 ts=4 sw=4 et:
%%%
%%% Copyright 2015 Panagiotis Papadomitsos. All Rights Reserved.
%%%

-module(gen_rpc_driver).
-author("Panagiotis Papadomitsos <pj@ezgr.net>").

%%% Include the HUT library
-include_lib("hut/include/hut.hrl").
%%% Include the debug logging macros
-include("logging.hrl").

%%% Authentication handshake shared by all drivers
-export([authenticate_to_server/3, authenticate_client/4]).

-ifdef(TEST).
-export([stub/0]).
-endif.

-callback connect(atom(), inet:port_number()) -> {ok, term()} | {error, term()}.

-callback listen(inet:port_number()) -> {ok, term()} | {error, term()}.

-callback accept(term()) -> {ok, inet:socket() | ssl:sslsocket()} | {error, term()}.

-callback activate_socket(term()) -> ok.

-callback authenticate_to_server(atom(), term()) -> ok | {error, {badtcp | badrpc, term()}}.

-callback authenticate_client(term(), tuple(), binary()) -> ok | {error, {badtcp | badrpc, term()}}.

-callback send(term(), binary()) -> ok | {error, term()}.

-callback recv(term(), timeout()) -> {ok, binary()} | {error, term()}.

-callback close(term()) -> ok.

%% Called on the server after the client's cookie has been validated,
%% allows a driver to apply further checks to the client's identity
-callback verify_peer(term(), atom()) -> ok | {error, atom()}.

-callback get_peer(term()) -> {inet:ip4_address(), inet:port_number()}.

-callback copy_sock_opts(term(), term()) -> ok | {error, any()}.

-callback set_controlling_process(term(), pid()) -> ok | {error, term()}.

-callback set_send_timeout(term(), timeout() | undefined) -> ok.

-callback set_acceptor_opts(term()) -> ok.

-callback getstat(term(), list()) -> {ok, list()} | {error, term()}.

%%% ===================================================
%%% Public API
%%% ===================================================
%% Authenticate to a server. The driver's authenticate_to_server/2 calls this
-spec authenticate_to_server(module(), atom(), term()) -> ok | {error, {badtcp | badrpc, term()}}.
authenticate_to_server(DriverMod, Node, Socket) ->
    Cookie = gen_rpc_helper:get_cookie_per_node(Node),
    Packet = erlang:term_to_binary({gen_rpc_authenticate_connection, node(), Cookie}),
    RecvTO = gen_rpc_helper:get_call_receive_timeout(undefined),
    ok = DriverMod:set_send_timeout(Socket, undefined),
    case DriverMod:send(Socket, Packet) of
        {error, Reason} ->
            ?log(error, "event=authentication_connection_failed socket=\"~s\" reason=\"~p\"",
                 [gen_rpc_helper:socket_to_string(Socket), Reason]),
            ok = DriverMod:close(Socket),
            {error, Reason};
        ok ->
            ?log_debug("event=authentication_connection_succeeded socket=\"~s\"", [gen_rpc_helper:socket_to_string(Socket)]),
            case DriverMod:recv(Socket, RecvTO) of
                {ok, RecvPacket} ->
                    receive_authentication_reply(DriverMod, Socket, RecvPacket);
                {error, Reason} ->
                    ?log(error, "event=authentication_reception_failed socket=\"~s\" reason=\"~p\"",
                         [gen_rpc_helper:socket_to_string(Socket), Reason]),
                    ok = DriverMod:close(Socket),
                    {error, {badtcp,Reason}}
            end
    end.

%% Authenticate a connected client. The driver's authenticate_client/3 calls this
-spec authenticate_client(module(), term(), tuple(), binary()) -> ok | {error, {badtcp | badrpc, term()}}.
authenticate_client(DriverMod, Socket, Peer, Data) ->
    try erlang:binary_to_term(Data) of
        {gen_rpc_authenticate_connection, Node, Cookie} when is_atom(Node), is_atom(Cookie) ->
            authenticate_node(DriverMod, Socket, Peer, Node, Cookie);
        OtherData ->
            ?log_debug("event=erroneous_data_received socket=\"~s\" peer=\"~s\" data=\"~p\"",
                 [gen_rpc_helper:socket_to_string(Socket), gen_rpc_helper:peer_to_string(Peer), OtherData]),
            {error, {badrpc,erroneous_data}}
    catch
        error:badarg ->
            {error, {badtcp,corrupt_data}}
    end.

%%% ===================================================
%%% Private functions
%%% ===================================================
receive_authentication_reply(DriverMod, Socket, RecvPacket) ->
    try erlang:binary_to_term(RecvPacket) of
        gen_rpc_connection_authenticated ->
            ?log_debug("event=connection_authenticated socket=\"~s\"", [gen_rpc_helper:socket_to_string(Socket)]),
            ok;
        {gen_rpc_connection_rejected, Reason} ->
            ?log(error, "event=authentication_rejected socket=\"~s\" reason=\"~p\"", [gen_rpc_helper:socket_to_string(Socket), Reason]),
            ok = DriverMod:close(Socket),
            {error, {badrpc,Reason}};
        _Else ->
            ?log(error, "event=authentication_reception_error socket=\"~s\" reason=\"invalid_payload\"",
                 [gen_rpc_helper:socket_to_string(Socket)]),
            ok = DriverMod:close(Socket),
            {error, {badrpc,invalid_message}}
    catch
        error:badarg ->
            ?log(error, "event=authentication_reception_error socket=\"~s\" reason=\"corrupt_data\"",
                 [gen_rpc_helper:socket_to_string(Socket)]),
            ok = DriverMod:close(Socket),
            {error, {badtcp,corrupt_data}}
    end.

%% Validate the cookie of a node and let the driver verify the client's identity.
%% The client is always told about the outcome
authenticate_node(DriverMod, Socket, Peer, Node, Cookie) ->
    Result = case gen_rpc_helper:get_cookie_per_node(Node) of
        Cookie ->
            DriverMod:verify_peer(Socket, Node);
        _InvalidCookie ->
            ?log(error, "event=invalid_cookie_received socket=\"~s\" peer=\"~s\" node=\"~s\"",
                 [gen_rpc_helper:socket_to_string(Socket), gen_rpc_helper:peer_to_string(Peer), Node]),
            {error, invalid_cookie}
    end,
    Response = case Result of
        ok -> gen_rpc_connection_authenticated;
        {error, Cause} -> {gen_rpc_connection_rejected, Cause}
    end,
    case {Result, DriverMod:send(Socket, erlang:term_to_binary(Response))} of
        {ok, ok} ->
            ?log_debug("event=transmission_succeeded socket=\"~s\" peer=\"~s\" node=\"~s\"",
                 [gen_rpc_helper:socket_to_string(Socket), gen_rpc_helper:peer_to_string(Peer), Node]),
            ok = DriverMod:activate_socket(Socket),
            ok;
        {ok, {error, SendReason}} ->
            ?log(error, "event=transmission_failed socket=\"~s\" peer=\"~s\" node=\"~s\" reason=\"~p\"",
                 [gen_rpc_helper:socket_to_string(Socket), gen_rpc_helper:peer_to_string(Peer), Node, SendReason]),
            {error, SendReason};
        {{error, Reason}, _SendResult} ->
            {error, {badrpc,Reason}}
    end.

-ifdef(TEST).
%% Stub function to fool code coverage
stub() -> ok.
-endif.
