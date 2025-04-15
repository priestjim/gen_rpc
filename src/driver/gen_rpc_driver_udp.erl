%%% -*-mode:erlang;coding:utf-8;tab-width:4;c-basic-offset:4;indent-tabs-mode:()-*-
%%% ex: set ft=erlang fenc=utf-8 sts=4 ts=4 sw=4 et:
%%%
%%% Driver UDP para gen_rpc

-module(gen_rpc_driver_udp).
-author("Matheus de Camargo Marques <matheuscamarques@gmail.com>").

%%% Behaviour
-behaviour(gen_rpc_driver).

%%% Include the HUT library
-include_lib("hut/include/hut.hrl").
%%% Include this library's name macro
-include("app.hrl").
%%% Include helpful guard macros
-include("guards.hrl").

-define(UDP_DEFAULT_OPTS, [binary, {active, once}, {reuseaddr, true}]).

%%% Public API
-export([connect/2,
         listen/1,
         accept/1,
         get_peer/1,
         send/2,
         activate_socket/1,
         authenticate_server/1,
         authenticate_client/3,
         copy_sock_opts/2,
         set_controlling_process/2,
         set_send_timeout/2,
         set_acceptor_opts/1]).

%%% ===================================================
%%% Public API
%%% ===================================================

%% Conecta a um nó via UDP (pseudo-conexão)
-spec connect(atom(), inet:port_number()) -> {ok, socket()} | {error, term()}.
connect(Node, Port) when is_atom(Node) ->
    Host = gen_rpc_helper:host_from_node(Node),
    ConnTO = gen_rpc_helper:get_connect_timeout(),
    case gen_udp:open(0, [binary, {active, false}]) of
        {ok, Socket} ->
            case gen_udp:connect(Socket, Host, Port) of
                ok ->
                    ?log(debug, "udp_connect_success node=~p socket=~p", [Node, Socket]),
                    {ok, Socket};
                {error, Reason} ->
                    gen_udp:close(Socket),
                    ?log(error, "udp_connect_failed node=~p reason=~p", [Node, Reason]),
                    {error, {badudp, Reason}}
            end;
        {error, Reason} ->
            ?log(error, "udp_socket_create_failed reason=~p", [Reason]),
            {error, {badudp, Reason}}
    end.

-spec listen(inet:port_number()) -> {ok, socket()} | {error, term()}.
listen(Port) ->
    gen_udp:open(Port, ?UDP_DEFAULT_OPTS).

-spec accept(socket()) -> {ok, socket()} | {error, term()}.
accept(Socket) ->
    {ok, Socket}.  

-spec activate_socket(socket()) -> ok.
activate_socket(Socket) ->
    inet:setopts(Socket, [{active, once}]),
    ok.

-spec send(socket(), binary()) -> ok | {error, term()}.
send(Socket, Data) ->
    case gen_udp:send(Socket, Data) of
        ok -> 
            ?log(debug, "udp_send_success socket=~p", [Socket]),
            ok;
        {error, Reason} ->
            ?log(error, "udp_send_failed socket=~p reason=~p", [Socket, Reason]),
            {error, {badudp, Reason}}
    end.

-spec authenticate_server(socket()) -> ok | {error, {badudp | badrpc, term()}}.
authenticate_server(Socket) ->
    Cookie = erlang:get_cookie(),
    Packet = erlang:term_to_binary({gen_rpc_authenticate_connection, Cookie}),
    RecvTO = gen_rpc_helper:get_call_receive_timeout(undefined),
    case send(Socket, Packet) of
        ok ->
            case gen_udp:recv(Socket, 0, RecvTO) of
                {ok, {_Addr, _Port, RecvPacket}} ->
                    case erlang:binary_to_term(RecvPacket) of
                        gen_rpc_connection_authenticated ->
                            ?log(debug, "udp_auth_success socket=~p", [Socket]),
                            ok;
                        {gen_rpc_connection_rejected, Reason} ->
                            {error, {badrpc, Reason}};
                        _ ->
                            {error, {badrpc, invalid_message}}
                    end;
                {error, Reason} ->
                    {error, {badudp, Reason}}
            end;
        Error -> Error
    end.

-spec authenticate_client(socket(), tuple(), binary()) -> ok | {error, {badudp | badrpc, term()}}.
authenticate_client(Socket, Peer, Data) ->
    Cookie = erlang:get_cookie(),
    try erlang:binary_to_term(Data) of
        {gen_rpc_authenticate_connection, Cookie} ->
            Packet = erlang:term_to_binary(gen_rpc_connection_authenticated),
            case send(Socket, Packet) of
                ok ->
                    ?log(debug, "udp_auth_client_success peer=~p", [Peer]),
                    ok;
                {error, Reason} ->
                    {error, {badudp, Reason}}
            end;
        {gen_rpc_authenticate_connection, _} ->
            {error, {badrpc, invalid_cookie}};
        _ ->
            {error, {badrpc, invalid_message}}
    catch
        error:badarg ->
            {error, {badudp, corrupt_data}}
    end.

-spec get_peer(socket()) -> {inet:ip4_address(), inet:port_number()}.
get_peer(Socket) ->
    {ok, Peer} = inet:peername(Socket),
    Peer.

-spec copy_sock_opts(term(), term()) -> ok | {error, any()}.
copy_sock_opts(_ListenSocket, _AccSocket) -> ok.

-spec set_controlling_process(socket(), pid()) -> ok | {error, term()}.
set_controlling_process(Socket, Pid) ->
    gen_udp:controlling_process(Socket, Pid).

-spec set_send_timeout(socket(), timeout() | undefined) -> ok.
set_send_timeout(Socket, Timeout) ->
    inet:setopts(Socket, [{send_timeout, Timeout}]).

-spec set_acceptor_opts(socket()) -> ok.
set_acceptor_opts(Socket) ->
    inet:setopts(Socket, [{active, once}]).