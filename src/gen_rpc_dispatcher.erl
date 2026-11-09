%%% -*-mode:erlang;coding:utf-8;tab-width:4;c-basic-offset:4;indent-tabs-mode:()-*-
%%% ex: set ft=erlang fenc=utf-8 sts=4 ts=4 sw=4 et:
%%%
%%% Copyright 2015 Panagiotis Papadomitsos. All Rights Reserved.
%%%
%%% Dispatcher is a serialization trick to prevent starting up
%%% multiple children for one connection. Starting a client means connecting
%%% to a node, which can take a while, so each client is started in its own
%%% process and the requests for the same client wait for the same result

-module(gen_rpc_dispatcher).

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

%%% Supervisor functions
-export([start_link/0, stop/0]).

%%% Server functions
-export([start_client/1]).

%%% Behaviour callbacks
-export([init/1, handle_call/3, handle_cast/2,
        handle_info/2, terminate/2, code_change/3]).

%%% Process exports
-export([start_worker/3]).

%%% ===================================================
%%% Public API
%%% ===================================================
-spec start_link() -> gen_server:start_ret().
start_link() ->
    gen_server:start_link({local,?MODULE}, ?MODULE, [], []).

-spec stop() -> ok.
stop() ->
    gen_server:stop(?MODULE, normal, infinity).

-spec start_client(node_or_tuple()) -> {ok, pid()} | {error, any()}.
start_client(NodeOrTuple) when ?is_node_or_tuple(NodeOrTuple) ->
    gen_server:call(?MODULE, {start_client,NodeOrTuple}, infinity).

%%% ===================================================
%%% Behaviour callbacks
%%% ===================================================
%% The state is a map of the clients that are being started, the key is the
%% name of the client process and the value is the monitor reference of the
%% process that starts the client and the callers that wait for it
init([]) ->
    ?log(info, "event=start"),
    {ok, #{}}.

%% Launch a connection to a node through the appropriate supervisor, unless
%% there is one or it is already being launched. This is a serialization
%% interface so that we do not start more than one client for each node
handle_call({start_client, NodeOrTuple}, Caller, Starting) ->
    PidName = gen_rpc_helper:make_process_name("client", NodeOrTuple),
    case erlang:whereis(PidName) of
        undefined ->
            case maps:find(PidName, Starting) of
                {ok, {Ref, Callers}} ->
                    ?log_debug("message=start_client event=client_server_starting target=\"~p\"", [NodeOrTuple]),
                    {noreply, maps:put(PidName, {Ref, [Caller|Callers]}, Starting)};
                error ->
                    ?log_debug("message=start_client event=starting_client_server target=\"~p\"", [NodeOrTuple]),
                    {_WorkerPid, Ref} = erlang:spawn_monitor(?MODULE, start_worker, [self(), PidName, NodeOrTuple]),
                    {noreply, maps:put(PidName, {Ref, [Caller]}, Starting)}
            end;
        Pid ->
            ?log_debug("message=start_client event=node_already_started target=\"~p\"", [NodeOrTuple]),
            {reply, {ok, Pid}, Starting}
    end;

%% Catch-all for calls - die if we get a message we don't expect
handle_call(Msg, _Caller, Starting) ->
    ?log(error, "event=unknown_call_received message=\"~p\" action=stopping", [Msg]),
    {stop, {unknown_call, Msg}, Starting}.

%% Catch-all for casts - die if we get a message we don't expect
handle_cast(Msg, Starting) ->
    ?log(error, "event=unknown_cast_received message=\"~p\" action=stopping", [Msg]),
    {stop, {unknown_cast, Msg}, Starting}.

%% A client has been started or failed to start, tell everyone who waits for it
handle_info({client_started, PidName, Reply}, Starting) ->
    {Ref, Callers} = maps:get(PidName, Starting),
    true = erlang:demonitor(Ref, [flush]),
    ok = reply_to_callers(Callers, Reply),
    {noreply, maps:remove(PidName, Starting)};

%% The process that starts a client died before it could report back
handle_info({'DOWN', Ref, process, _Pid, Reason}, Starting) ->
    case [PidName || {PidName, {StartRef, _Callers}} <- maps:to_list(Starting), StartRef =:= Ref] of
        [PidName] ->
            ?log(error, "event=start_client_failed client=~s reason=\"~p\"", [PidName, Reason]),
            {_Ref, Callers} = maps:get(PidName, Starting),
            ok = reply_to_callers(Callers, {error, {badrpc, {unknown_error, Reason}}}),
            {noreply, maps:remove(PidName, Starting)};
        [] ->
            {noreply, Starting}
    end;

%% Catch-all for info - our protocol is strict so die!
handle_info(Msg, Starting) ->
    ?log(error, "event=unknown_message_received message=\"~p\" action=stopping", [Msg]),
    {stop, {unknown_info, Msg}, Starting}.

code_change(_OldVersion, Starting, _Extra) ->
    {ok, Starting}.

terminate(_Reason, _Starting) ->
    ok.

%%% ===================================================
%%% Private functions
%%% ===================================================
%% Starts a client and reports the result to the dispatcher
start_worker(Dispatcher, PidName, NodeOrTuple) ->
    Dispatcher ! {client_started, PidName, gen_rpc_client:start(NodeOrTuple)},
    ok.

reply_to_callers(Callers, Reply) ->
    lists:foreach(fun(Caller) -> gen_server:reply(Caller, Reply) end, Callers).
