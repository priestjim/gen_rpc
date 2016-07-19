%%% -*-mode:erlang;coding:utf-8;tab-width:4;c-basic-offset:4;indent-tabs-mode:()-*-
%%% ex: set ft=erlang fenc=utf-8 sts=4 ts=4 sw=4 et:
%%%
%%% Copyright 2015 Panagiotis Papadomitsos. All Rights Reserved.
%%%

-module(gen_rpc_helper).
-author("Panagiotis Papadomitsos <pj@ezgr.net>").

%%% Include this library's name macro
-include("app.hrl").

%%% Public API
-export([otp_release/0,
        peer_to_string/1,
        host_from_node/1,
        set_sock_opt/2,
        make_process_name/2,
        extract_node_name/1,
	set_optimal_process_flags/0,
        get_remote_tcp_server_port/1,
        get_connect_timeout/0,
        get_send_timeout/1,
        get_call_receive_timeout/1,
        get_sbcast_receive_timeout/0,
        get_inactivity_timeout/1,
        get_async_call_inactivity_timeout/0]).

%%% ===================================================
%%% Public API
%%% ===================================================
-spec otp_release() -> integer().
otp_release() ->
    try
        erlang:list_to_integer(erlang:system_info(otp_release))
    catch
        error:badarg ->
            %% Before Erlang 17, R was included in the OTP release,
            %% which would make the list_to_integer call fail.
            %% Since we only use this function to test the availability
            %% of the show_econnreset feature, 16 is good enough.
            16
    end.

-spec set_optimal_process_flags() -> ok.
set_optimal_process_flags() ->
    _ = erlang:process_flag(trap_exit, true),
    _ = erlang:process_flag(priority, high),
    _ = erlang:process_flag(message_queue_data, off_heap),
    ok.

%% Return the connected peer's IP
-spec peer_to_string({inet:ip4_address(), inet:port_number()} | inet:ip4_address()) -> string().
peer_to_string({{A,B,C,D}, Port}) when is_integer(A), is_integer(B), is_integer(C), is_integer(D), is_integer(Port) ->
    lists:flatten([integer_to_list(A), ".",
    integer_to_list(B), ".",
    integer_to_list(C), ".",
    integer_to_list(D), ":",
    integer_to_list(Port)]);
peer_to_string({A,B,C,D} = IpAddress) when is_integer(A), is_integer(B), is_integer(C), is_integer(D) ->
    peer_to_string({IpAddress, 0}).

%% Return the remote Erlang hostname
-spec host_from_node(node()) -> string().
host_from_node(Node) when is_atom(Node) ->
    NodeStr = atom_to_list(Node),
    [_Name, Host] = string:tokens(NodeStr, [$@]),
    Host.

%% Taken from prim_inet.  We are merely copying some socket options from the
%% listening socket to the new acceptor socket.
-spec set_sock_opt(port(), port()) -> ok | {error, any()}.
set_sock_opt(ListSock, AccSock) when is_port(ListSock), is_port(AccSock) ->
    true = inet_db:register_socket(AccSock, inet_tcp),
    case prim_inet:getopts(ListSock, ?ACCEPTOR_TCP_OPTS) of
        {ok, Opts} ->
            case prim_inet:setopts(AccSock, Opts) of
                ok    -> ok;
                Error -> gen_tcp:close(AccSock), Error
            end;
        Error ->
            (try
                gen_tcp:close(AccSock)
            catch
                _:_ -> ok
            end),
            Error
        end.

%% Return an atom to identify gen_rpc processes
-spec make_process_name(list(), {inet:ip4_address(), inet:port_number()} | atom()) -> atom().
make_process_name("client", Node) when is_atom(Node) ->
    %% This function is going to be called enough to warrant a less pretty
    %% process name in order to avoid calling costly functions
    NodeStr = atom_to_list(Node),
    list_to_atom(lists:flatten(["gen_rpc.client.", NodeStr]));

make_process_name(Prefix, Peer) when is_list(Prefix), is_tuple(Peer) ->
    list_to_atom(lists:flatten(["gen_rpc.", Prefix, ".", peer_to_string(Peer)])).

%% Extract the node name from a gen_rpc client process name
-spec extract_node_name(atom()) -> atom().
extract_node_name(PidName) when is_atom(PidName) ->
    %% The process name follows the convention
    %% gen_rpc.client.(node name) which is 15 chars long
    PidStr = atom_to_list(PidName),
    list_to_atom(lists:nthtail(15, PidStr)).

%% Retrieves the default connect timeout
-spec get_connect_timeout() -> timeout().
get_connect_timeout() ->
    {ok, ConnTO} = application:get_env(?APP, connect_timeout),
    ConnTO.

%% Retrieves the specific TCP server port
-spec get_remote_tcp_server_port(atom()) -> inet:port_number().
get_remote_tcp_server_port(Node) ->
    case application:get_env(?APP, remote_tcp_server_ports) of
        {ok, []} ->
            {ok, Port} = application:get_env(?APP, tcp_server_port),
            Port;
        {ok, Ports} ->
            case lists:keyfind(Node, 1, Ports) of
                false ->
                    {ok, Port} = application:get_env(?APP, tcp_server_port),
                    Port;
                {Node, Port} ->
                    Port
            end
    end.

%% Merges user-defined receive timeout values with app timeout values
-spec get_call_receive_timeout(undefined | timeout()) -> timeout().
get_call_receive_timeout(undefined) ->
    {ok, RecvTO} = application:get_env(?APP, call_receive_timeout),
    RecvTO;

get_call_receive_timeout(Else) ->
    Else.

%% Merges user-defined send timeout values with app timeout values
-spec get_send_timeout(undefined | timeout()) -> timeout().
get_send_timeout(undefined) ->
    {ok, SendTO} = application:get_env(?APP, send_timeout),
    SendTO;
get_send_timeout(Else) ->
    Else.

%% Returns default inactivity timeouts for different modules
-spec get_inactivity_timeout(gen_rpc_client | gen_rpc_acceptor) -> timeout().
get_inactivity_timeout(gen_rpc_client) ->
    {ok, TTL} = application:get_env(?APP, client_inactivity_timeout),
    TTL;

get_inactivity_timeout(gen_rpc_acceptor) ->
    {ok, TTL} = application:get_env(?APP, server_inactivity_timeout),
    TTL.

-spec get_async_call_inactivity_timeout() -> timeout().
get_async_call_inactivity_timeout() ->
    {ok, TTL} = application:get_env(?APP, async_call_inactivity_timeout),
    TTL.

-spec get_sbcast_receive_timeout() -> timeout().
get_sbcast_receive_timeout() ->
    {ok, RecvTO} = application:get_env(?APP, sbcast_receive_timeout),
    RecvTO.

