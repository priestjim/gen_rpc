%%% -*-mode:erlang;coding:utf-8;tab-width:4;c-basic-offset:4;indent-tabs-mode:()-*-
%%% ex: set ft=erlang fenc=utf-8 sts=4 ts=4 sw=4 et:
%%%
%%% Copyright 2015 Panagiotis Papadomitsos. All Rights Reserved.
%%%
%%% Original concept inspired and some code copied from
%%% https://erlangcentral.org/wiki/index.php?title=Building_a_Non-blocking_TCP_server_using_OTP_principles

-module(gen_rpc_driver_ssl).
-author("Panagiotis Papadomitsos <pj@ezgr.net>").

%%% Behaviour
-behaviour(gen_rpc_driver).

%%% Include the HUT library
-include_lib("hut/include/hut.hrl").
%%% Include the debug logging macros
-include("logging.hrl").
%%% Include this library's name macro
-include("app.hrl").
%%% Include SSL macros
-include("ssl.hrl").
%%% Include TCP macros
-include("tcp.hrl").

%%% Public API
-export([connect/2,
        listen/1,
        accept/1,
        get_peer/1,
        send/2,
        activate_socket/1,
        recv/2,
        close/1,
        authenticate_to_server/2,
        authenticate_client/3,
        verify_peer/2,
        copy_sock_opts/2,
        set_controlling_process/2,
        set_send_timeout/2,
        set_acceptor_opts/1,
        getstat/2]).

%%% ===================================================
%%% Public API
%%% ===================================================
%% Connect to a node
-spec connect(atom(), inet:port_number()) -> {ok, ssl:sslsocket()} | {error, term()}.
connect(Node, Port) when is_atom(Node) ->
    Host = gen_rpc_helper:host_from_node(Node),
    ConnTO = gen_rpc_helper:get_connect_timeout(),
    SslOpts = merge_ssl_options(client, Node),
    case ssl:connect(Host, Port, SslOpts, ConnTO) of
        {ok, Socket} ->
            ?log_debug("event=connect_to_remote_server peer=\"~s\" socket=\"~s\" result=success",
                 [Node, gen_rpc_helper:socket_to_string(Socket)]),
            {ok, Socket};
        {error, Reason} ->
            ?log(error, "event=connect_to_remote_server peer=\"~s\" result=failure reason=\"~p\"", [Node, Reason]),
            {error, {badtcp,Reason}}
    end.


-spec listen(inet:port_number()) -> {ok, ssl:sslsocket()} | {error, term()}.
listen(Port) when is_integer(Port) ->
    SslOpts = merge_ssl_options(server, undefined),
    ssl:listen(Port, SslOpts).

-spec accept(ssl:sslsocket()) -> {ok, ssl:sslsocket()} | {error, term()}.
accept(Socket) when is_tuple(Socket) ->
    case ssl:transport_accept(Socket, infinity) of
        {ok, TSocket} ->
            %% A peer that fails or stalls the handshake must not take down the listener
            case ssl:handshake(TSocket, gen_rpc_helper:get_authentication_timeout()) of
                {ok, SslSocket} ->
                    {ok, SslSocket};
                {error, Reason} ->
                    ?log(error, "event=tls_handshake_failed reason=\"~p\"", [Reason]),
                    accept(Socket)
            end;
        {error, Reason} ->
            {error, Reason}
    end.

-spec send(ssl:sslsocket(), binary()) -> ok | {error, term()}.
send(Socket, Data) when is_tuple(Socket), is_binary(Data) ->
    case ssl:send(Socket, Data) of
        {error, timeout} ->
            ?log(error, "event=send_data_failed socket=\"~s\" reason=\"timeout\"", [gen_rpc_helper:socket_to_string(Socket)]),
            {error, {badtcp,send_timeout}};
        {error, Reason} ->
            ?log(error, "event=send_data_failed socket=\"~s\" reason=\"~p\"", [gen_rpc_helper:socket_to_string(Socket), Reason]),
            {error, {badtcp,Reason}};
        ok ->
            ?log_debug("event=send_data_succeeded socket=\"~s\"", [gen_rpc_helper:socket_to_string(Socket)]),
            ok
    end.

-spec activate_socket(ssl:sslsocket()) -> ok.
activate_socket(Socket) when is_tuple(Socket) ->
    ok = ssl:setopts(Socket, [{active,once}]),
    ok.

-spec recv(ssl:sslsocket(), timeout()) -> {ok, binary()} | {error, term()}.
recv(Socket, Timeout) when is_tuple(Socket) ->
    ssl:recv(Socket, 0, Timeout).

-spec close(ssl:sslsocket()) -> ok.
close(Socket) when is_tuple(Socket) ->
    ssl:close(Socket).

%% Authenticate to a server
-spec authenticate_to_server(atom(), ssl:sslsocket()) -> ok | {error, {badtcp | badrpc, term()}}.
authenticate_to_server(Node, Socket) ->
    gen_rpc_driver:authenticate_to_server(?MODULE, Node, Socket).

%% Authenticate a connected client
-spec authenticate_client(ssl:sslsocket(), tuple(), binary()) -> ok | {error, {badtcp | badrpc, term()}}.
authenticate_client(Socket, Peer, Data) ->
    gen_rpc_driver:authenticate_client(?MODULE, Socket, Peer, Data).

%% The certificate of the client must be valid for the node it claims to be
-spec verify_peer(ssl:sslsocket(), atom()) -> ok | {error, node_certificate_mismatch}.
verify_peer(Socket, Node) ->
    PeerCert = extract_peer_certificate(Socket),
    case ssl_verify_hostname:verify_cert_hostname(PeerCert, gen_rpc_helper:to_string(Node)) of
        {fail, Reason} ->
            ?log(error, "event=node_certificate_mismatch socket=\"~s\" node=\"~s\" reason=\"~p\"",
                 [gen_rpc_helper:socket_to_string(Socket), Node, Reason]),
            {error, node_certificate_mismatch};
        {valid, _Hostname} ->
            ?log_debug("event=certificate_validated socket=\"~s\" node=\"~s\"", [gen_rpc_helper:socket_to_string(Socket), Node]),
            ok
    end.

-spec copy_sock_opts(port(), port()) -> ok | {error, any()}.
copy_sock_opts(_ListSock, _AccSock) ->
    ok. % SSL copies the socket's options to the acceptor by default

-spec get_peer(ssl:sslsocket()) -> {inet:ip4_address(), inet:port_number()}.
get_peer(Socket) when is_tuple(Socket) ->
    {ok, Peer} = ssl:peername(Socket),
    Peer.

-spec set_controlling_process(ssl:sslsocket(), pid()) -> ok | {error, term()}.
set_controlling_process(Socket, Pid) when is_tuple(Socket), is_pid(Pid) ->
    ssl:controlling_process(Socket, Pid).

-spec set_send_timeout(ssl:sslsocket(), timeout() | undefined) -> ok.
set_send_timeout(Socket, SendTO) when is_tuple(Socket) ->
    ok = ssl:setopts(Socket, [{send_timeout, gen_rpc_helper:get_send_timeout(SendTO)}]),
    ok.

-spec set_acceptor_opts(ssl:sslsocket()) -> ok.
set_acceptor_opts(Socket) when is_tuple(Socket) ->
    ok = ssl:setopts(Socket, gen_rpc_helper:get_socket_keepalive_options()),
    ok = ssl:setopts(Socket, [{send_timeout, gen_rpc_helper:get_send_timeout(undefined)}]),
    ok.

-spec getstat(ssl:sslsocket(), list()) -> {ok, list()} | {error, term()}.
getstat(Socket, OptNames) ->
    ssl:getstat(Socket, OptNames).

%%% ===================================================
%%% Private functions
%%% ===================================================
merge_ssl_options(client, Node) ->
    {ok, ExtraOpts} = application:get_env(?APP, ssl_client_options),
    NodeStr = gen_rpc_helper:to_string(Node),
    DefaultOpts = lists:append(?SSL_DEFAULT_COMMON_OPTS, ?SSL_DEFAULT_CLIENT_OPTS),
    VerifyOpts = [{verify_fun, {fun ssl_verify_hostname:verify_fun/3,[{check_hostname,NodeStr}]}}|DefaultOpts],
    gen_rpc_helper:merge_sockopt_lists(ExtraOpts, VerifyOpts);

merge_ssl_options(server, _Node) ->
    {ok, ExtraOpts} = application:get_env(?APP, ssl_server_options),
    DefaultOpts = lists:append(?SSL_DEFAULT_COMMON_OPTS, ?SSL_DEFAULT_SERVER_OPTS),
    gen_rpc_helper:merge_sockopt_lists(ExtraOpts, DefaultOpts).

extract_peer_certificate(Socket) ->
    {ok, Cert} = ssl:peercert(Socket),
    public_key:pkix_decode_cert(Cert, otp).
