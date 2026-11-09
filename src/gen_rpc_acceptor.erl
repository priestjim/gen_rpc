%%% -*-mode:erlang;coding:utf-8;tab-width:4;c-basic-offset:4;indent-tabs-mode:()-*-
%%% ex: set ft=erlang fenc=utf-8 sts=4 ts=4 sw=4 et:
%%%
%%% Copyright 2015 Panagiotis Papadomitsos. All Rights Reserved.
%%%
%%% Original concept inspired and some code copied from
%%% https://erlangcentral.org/wiki/index.php?title=Building_a_Non-blocking_TCP_server_using_OTP_principles

-module(gen_rpc_acceptor).
-author("Panagiotis Papadomitsos <pj@ezgr.net>").

%%% Behaviour
-behaviour(gen_statem).

%%% Include the HUT library
-include_lib("hut/include/hut.hrl").
%%% Include the debug logging macros
-include("logging.hrl").

%%% Local state
-record(state, {socket = undefined :: port() | undefined,
        driver :: atom(),
        driver_mod :: atom(),
        driver_closed :: atom(),
        driver_error :: atom(),
        peer :: {inet:ip4_address(), inet:port_number()},
        control :: whitelist | blacklist | disabled,
        list :: sets:set() | undefined}).

%%% Ignore dialyzer warning for call_middleman
%%% The non-local return is deliberate
-dialyzer([{no_return, [call_middleman/3]}]).

%%% Server functions
-export([start_link/2, set_socket/2, stop/1]).

%% gen_statem callbacks
-export([init/1, callback_mode/0, terminate/3, code_change/4]).

%% State machine states
-export([waiting_for_socket/3, waiting_for_auth/3, waiting_for_data/3]).

%%% Process exports
-export([call_worker/6, call_middleman/3]).

%%% ===================================================
%%% Supervisor functions
%%% ===================================================
-spec start_link(atom(), {inet:ip4_address(), inet:port_number()}) -> gen_statem:start_ret().
start_link(Driver, Peer) when is_atom(Driver), is_tuple(Peer) ->
    case gen_rpc_helper:get_named_acceptors() of
        true ->
            Name = gen_rpc_helper:make_process_name("acceptor", Peer),
            gen_statem:start_link({local,Name}, ?MODULE, {Driver, Peer}, []);
        false ->
            gen_statem:start_link(?MODULE, {Driver, Peer}, [])
    end.

-spec stop(pid()) -> ok.
stop(Pid) when is_pid(Pid) ->
    gen_statem:stop(Pid, normal, infinity).

%%% ===================================================
%%% Server functions
%%% ===================================================
-spec set_socket(pid(), gen_tcp:socket()) -> ok.
set_socket(Pid, Socket) when is_pid(Pid) ->
    gen_statem:call(Pid, {socket_ready,Socket}, infinity).

%%% ===================================================
%%% Behaviour callbacks
%%% ===================================================
init({Driver, Peer}) ->
    ok = gen_rpc_helper:set_optimal_process_flags(true),
    {Control, ControlList} = gen_rpc_helper:get_rpc_module_control(),
    {DriverMod, _DriverPort, DriverClosed, DriverError} = gen_rpc_helper:get_server_driver_options(Driver),
    ?log(info, "event=start driver=~s peer=\"~s\"", [Driver, gen_rpc_helper:peer_to_string(Peer)]),
    {ok, waiting_for_socket, #state{driver=Driver,
                                    driver_mod=DriverMod,
                                    driver_error=DriverError,
                                    driver_closed=DriverClosed,
                                    peer=Peer,
                                    control=Control,
                                    list=ControlList}}.

callback_mode() ->
    state_functions.

waiting_for_socket({call,From}, {socket_ready,Socket}, #state{driver=Driver, driver_mod=DriverMod, peer=Peer} = State) ->
    % Now we own the socket
    ?log_debug("event=acquiring_socket_ownership driver=~s socket=\"~s\" peer=\"~p\"",
         [Driver, gen_rpc_helper:socket_to_string(Socket), gen_rpc_helper:peer_to_string(Peer)]),
    ok = DriverMod:set_acceptor_opts(Socket),
    ok = DriverMod:activate_socket(Socket),
    ok = gen_statem:reply(From, ok),
    {next_state, waiting_for_auth, State#state{socket=Socket}, gen_rpc_helper:get_authentication_timeout()}.

waiting_for_auth(info, {Driver,Socket,Data}, #state{socket=Socket, driver=Driver, driver_mod=DriverMod, peer=Peer} = State) ->
    case DriverMod:authenticate_client(Socket, Peer, Data) of
        {error, Reason} ->
            {stop, Reason, State};
        ok ->
            {next_state, waiting_for_data, State, gen_rpc_helper:get_server_inactivity_timeout()}
    end;

waiting_for_auth(timeout, _Timeout, #state{socket=Socket, driver=Driver, peer=Peer} = State) ->
    ?log(notice, "event=timed_out_waiting_for_auth driver=~s socket=\"~s\" peer=\"~s\"",
         [Driver, gen_rpc_helper:socket_to_string(Socket), gen_rpc_helper:peer_to_string(Peer)]),
    {stop, timed_out_waiting_for_auth, State};

waiting_for_auth(info, {DriverClosed, Socket} = Msg, #state{socket=Socket, driver_closed=DriverClosed} = State) ->
    handle_socket_event(Msg, State);

waiting_for_auth(info, {DriverError, Socket, _Reason} = Msg, #state{socket=Socket, driver_error=DriverError} = State) ->
    handle_socket_event(Msg, State).

waiting_for_data(info, {Driver,Socket,Data},
                 #state{socket=Socket, driver=Driver, driver_mod=DriverMod, peer=Peer, control=Control, list=List} = State) ->
    %% The meat of the whole project: process a function call and return
    %% the data
    try erlang:binary_to_term(Data) of
        {{CallType,M,F,A}, Caller} when CallType =:= call; CallType =:= async_call ->
            case authorize(M, Control, List) of
                {ok, RealM} ->
                    WorkerPid = erlang:spawn(?MODULE, call_worker, [self(), CallType, RealM, F, A, Caller]),
                    ?log_debug("event=call_received driver=~s socket=\"~s\" peer=\"~s\" caller=\"~p\" worker_pid=\"~p\"",
                         [Driver, gen_rpc_helper:socket_to_string(Socket), gen_rpc_helper:peer_to_string(Peer), Caller, WorkerPid]),
                    continue(DriverMod, Socket);
                {incompatible, RealM} ->
                    ?log_debug("event=incompatible_module_version driver=~s socket=\"~s\" method=~s module=~s",
                         [Driver, gen_rpc_helper:socket_to_string(Socket), CallType, RealM]),
                    ok = DriverMod:activate_socket(Socket),
                    waiting_for_data(info, {CallType, Caller, {badrpc,incompatible}}, State);
                {unauthorized, RealM} ->
                    ?log_debug("event=request_not_allowed driver=~s socket=\"~s\" control=~s method=~s module=~s",
                         [Driver, gen_rpc_helper:socket_to_string(Socket), Control, CallType, RealM]),
                    ok = DriverMod:activate_socket(Socket),
                    waiting_for_data(info, {CallType, Caller, {badrpc,unauthorized}}, State)
            end;
        {cast, M, F, A} ->
            _ = case authorize(M, Control, List) of
                {ok, RealM} ->
                    ?log_debug("event=cast_received driver=~s socket=\"~s\" peer=\"~s\" module=~s function=~s args=\"~p\"",
                         [Driver, gen_rpc_helper:socket_to_string(Socket), gen_rpc_helper:peer_to_string(Peer), RealM, F, A]),
                    erlang:spawn(RealM, F, A);
                {incompatible, RealM} ->
                    ?log_debug("event=incompatible_module_version driver=~s socket=\"~s\" module=~s",
                         [Driver, gen_rpc_helper:socket_to_string(Socket), RealM]);
                {unauthorized, RealM} ->
                    ?log_debug("event=request_not_allowed driver=~s socket=\"~s\" control=~s method=cast module=~s",
                         [Driver, gen_rpc_helper:socket_to_string(Socket), Control, RealM])
            end,
            continue(DriverMod, Socket);
        {abcast, Name, Msg} ->
            _ = case check_if_module_allowed(erlang, Control, List) of
                true ->
                    ?log_debug("event=abcast_received driver=~s socket=\"~s\" peer=\"~s\" process=~s message=\"~p\"",
                         [Driver, gen_rpc_helper:socket_to_string(Socket), gen_rpc_helper:peer_to_string(Peer), Name, Msg]),
                    send_to_registered(Name, Msg);
                false ->
                    ?log_debug("event=request_not_allowed driver=~s socket=\"~s\" control=~s method=~s",
                         [Driver, gen_rpc_helper:socket_to_string(Socket), Control, abcast])
            end,
            continue(DriverMod, Socket);
        {sbcast, Name, Msg, Caller} ->
            Reply = case check_if_module_allowed(erlang, Control, List) of
                true ->
                    ?log_debug("event=sbcast_received driver=~s socket=\"~s\" peer=\"~s\" process=~s message=\"~p\"",
                         [Driver, gen_rpc_helper:socket_to_string(Socket), gen_rpc_helper:peer_to_string(Peer), Name, Msg]),
                    case send_to_registered(Name, Msg) of
                        true -> success;
                        false -> error
                    end;
                false ->
                    ?log_debug("event=request_not_allowed driver=~s socket=\"~s\" control=~s method=~s",
                         [Driver, gen_rpc_helper:socket_to_string(Socket), Control, sbcast]),
                     error
            end,
            ok = DriverMod:activate_socket(Socket),
            waiting_for_data(info, {sbcast, Caller, Reply}, State);
        ping ->
            ?log_debug("event=ping_received driver=~s socket=\"~s\" peer=\"~s\" action=ignore",
                 [Driver, gen_rpc_helper:socket_to_string(Socket), gen_rpc_helper:peer_to_string(Peer)]),
            continue(DriverMod, Socket);
        OtherData ->
            ?log_debug("event=erroneous_data_received driver=~s socket=\"~s\" peer=\"~s\" data=\"~p\"",
                 [Driver, gen_rpc_helper:socket_to_string(Socket), gen_rpc_helper:peer_to_string(Peer), OtherData]),
            {stop, {badrpc,erroneous_data}, State}
    catch
        error:badarg ->
            {stop, {badtcp,corrupt_data}, State}
    end;

%% Handle a call worker message
waiting_for_data(info, {CallReply,_Caller,_Reply} = Payload, #state{socket=Socket, driver=Driver, driver_mod=DriverMod} = State)
when CallReply =:= call orelse CallReply =:= async_call orelse CallReply =:= sbcast ->
    Packet = erlang:term_to_binary(Payload),
    ?log_debug("message=call_reply event=call_reply_received driver=~s socket=\"~s\" type=~s",
         [Driver, gen_rpc_helper:socket_to_string(Socket), CallReply]),
    case DriverMod:send(Socket, Packet) of
        ok ->
            ?log_debug("message=call_reply event=call_reply_sent driver=~s socket=\"~s\"", [Driver, gen_rpc_helper:socket_to_string(Socket)]),
            {keep_state_and_data, gen_rpc_helper:get_server_inactivity_timeout()};
        {error, Reason} ->
            ?log(error, "message=call_reply event=failed_to_send_call_reply driver=~s socket=\"~s\" reason=\"~p\"",
                 [Driver, gen_rpc_helper:socket_to_string(Socket), Reason]),
            {stop, Reason, State}
    end;

%% Handle the inactivity timeout gracefully
waiting_for_data(timeout, _Undefined, #state{socket=Socket, driver=Driver} = State) ->
    ?log(info, "message=timeout event=server_inactivity_timeout driver=~s socket=\"~s\" action=stopping",
         [Driver, gen_rpc_helper:socket_to_string(Socket)]),
    {stop, normal, State};

waiting_for_data(info, {DriverClosed, Socket} = Msg, #state{socket=Socket, driver_closed=DriverClosed} = State) ->
    handle_socket_event(Msg, State);

waiting_for_data(info, {DriverError, Socket, _Reason} = Msg, #state{socket=Socket, driver_error=DriverError} = State) ->
    handle_socket_event(Msg, State).

terminate(_Reason, _StateName, _State) ->
    ok.

code_change(_OldVsn, StateName, State, _Extra) ->
    {ok, StateName, State}.

%%% ===================================================
%%% Private functions
%%% ===================================================
%% Handle the socket closing or failing
handle_socket_event({DriverClosed, Socket}, #state{socket=Socket, driver=Driver, driver_closed=DriverClosed, peer=Peer} = State) ->
    ?log(notice, "message=channel_closed driver=~s socket=\"~s\" peer=\"~s\" action=stopping",
         [Driver, gen_rpc_helper:socket_to_string(Socket), gen_rpc_helper:peer_to_string(Peer)]),
    {stop, normal, State};

handle_socket_event({DriverError, Socket, Reason}, #state{socket=Socket, driver=Driver, driver_error=DriverError, peer=Peer} = State) ->
    ?log(error, "message=channel_error driver=~s socket=\"~s\" peer=\"~s\" reason=\"~p\" action=stopping",
         [Driver, gen_rpc_helper:socket_to_string(Socket), gen_rpc_helper:peer_to_string(Peer), Reason]),
    {stop, normal, State}.

%% Re-enable the socket and wait for the next message
continue(DriverMod, Socket) ->
    ok = DriverMod:activate_socket(Socket),
    {keep_state_and_data, gen_rpc_helper:get_server_inactivity_timeout()}.

%% Process an RPC call request outside of the state machine
call_worker(Server, CallType, M, F, A, Caller) ->
    ?log_debug("event=call_received caller=\"~p\" module=~s function=~s args=\"~p\"", [Caller, M, F, A]),
    % If called MFA return exception, not of type term().
    % This fails term_to_binary coversion, crashes process
    % and manifest as timeout. Wrap inside anonymous function with catch
    % will crash the worker quickly not manifest as a timeout.
    % See call_MFA_undef test.
    {MPid, MRef} = erlang:spawn_monitor(?MODULE, call_middleman, [M,F,A]),
    receive
        {'DOWN', MRef, process, MPid, {call_middleman_result, Res}} ->
            Server ! {CallType, Caller, Res};
        {'DOWN', MRef, process, MPid, AbnormalExit} ->
            Server ! {CallType, Caller, {badrpc, AbnormalExit}}
    end.

call_middleman(M, F, A) ->
    Res = try
            erlang:apply(M, F, A)
          catch
               throw:Term -> Term;
               exit:Reason -> {badrpc, {'EXIT', Reason}};
               error:Reason:Stacktrace -> {badrpc, {'EXIT', {Reason, Stacktrace}}}
          end,
    erlang:exit({call_middleman_result, Res}),
    ok.

%% Send a message to a locally registered process, returns whether the process exists.
%% A missing process must not crash the acceptor, abcast and sbcast are fire and forget
send_to_registered(Name, Msg) when is_atom(Name) ->
    case erlang:whereis(Name) of
        undefined ->
            false;
        Pid ->
            _ = erlang:send(Pid, Msg),
            true
    end;

send_to_registered(_Name, _Msg) ->
    false.

%% Check if a call to a module (or a {Module, Version} tuple) is allowed. The module
%% is checked against the module control list before its version is checked
authorize(M, Control, List) ->
    {ModVsnAllowed, RealM} = check_module_version_compat(M),
    case check_if_module_allowed(RealM, Control, List) of
        false -> {unauthorized, RealM};
        true when ModVsnAllowed -> {ok, RealM};
        true -> {incompatible, RealM}
    end.

%% Check if the function is RPC-enabled
check_if_module_allowed(_Module, disabled, _List) ->
    true;

check_if_module_allowed(Module, whitelist, List) ->
    sets:is_element(Module, List);

check_if_module_allowed(Module, blacklist, List) ->
    not sets:is_element(Module, List).

%% Check if the module version called is compatible with the one
%% requested by the caller
check_module_version_compat({M, Version}) ->
    try
        Attrs = M:module_info(attributes),
        {vsn, VsnList} = lists:keyfind(vsn, 1, Attrs),
        case VsnList of
            [Vsn] when Vsn =:= Version ->
                {true, M};
            Vsn when Vsn =:= Version ->
                {true, M};
            _Else ->
                {false, M}
        end
    catch
        error:undef ->
            ?log_debug("event=module_not_found module=~s", [M]),
            {false, M};
        error:badarg ->
            ?log_debug("event=invalid_module_definition module=\"~p\"", [M]),
            {false, M}
    end;

check_module_version_compat(M) ->
    {true, M}.
