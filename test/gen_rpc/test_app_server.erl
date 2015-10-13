%%% ex: set ft=erlang fenc=utf-8 sts=4 ts=4 sw=4 et:
%%%
%%% Copyright 2015 Panagiotis Papadomitsos. All Rights Reserved.
%%%
%%% Use a gen_server to hold states between test calls.

-module(test_app_server).
-author("Panagiotis Papadomitsos <pj@ezgr.net>").

%%% CT Macros
%-include_lib("test/gen_rpc/include/ct.hrl").

-beahviour(gen_server).

-export([start_link/1, terminate/2]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2]).
-export([code_change/3]).

-export([start_link/0, store/1, ping/0, retrieve/0, retrieve/1]).
-export([stop/0]).

-record(state, {entry :: map()}).

start_link() ->
    Opts = [{'id', node()}
            ,{'from', 0}
            ,{'test_case', null}
            ,{'sent_time', 0}
            ,{'update_time', 0}
            ,{'data', <<"">>}],
    start_link(Opts).

start_link(Opts) ->
    Name = make_process_name(),
    gen_server:start_link({local, Name}, ?MODULE, Opts, [{debug, [trace]}]).

stop() ->
    Name = make_process_name(),
    Ret = gen_server:stop({Name, node()}),
    {ok, Ret}.

store(Data) ->
    Name = make_process_name(),
    {ok, 'set'} = gen_server:call({Name, node()}, {'set', Data}).

retrieve() ->
    Name = make_process_name(),
    gen_server:call({Name, node()}, 'retrieve').

ping() ->
    Name = make_process_name(),
    {ok, 'pong'} = gen_server:call({Name, node()}, 'ping'),
    {'pong', Name}.

%% rpc:multicall on assumes MFA
retrieve(_)-> retrieve().

init(Opts) ->
    process_flag(trap_exit, true),
    {ok, #state{entry=[maps:from_list(Opts)]}}.

handle_call('ping', _From, State) ->
    %This message shows up in trace.
    {reply, {ok, 'pong'}, State};
handle_call({'set', Data}, _From, State) ->
    Payload = store_state(Data),
    Payload0 = Payload ++ State#state.entry,
    {reply, {ok, 'set'}, State#state{entry = Payload0}};
handle_call('retrieve', _From, State) ->
    {reply, {ok, State#state.entry}, State};
handle_call(terminate, _From, State) ->
    {stop, normal, ok, State};
handle_call(Unknown, _From, State) ->
    {reply, {error, {'unknown_msg', Unknown}, State}}.

handle_cast(_Msg, State) ->
    {noreply, State}.

handle_info('EXIT', State) ->
    {noreply, State};
handle_info(_Msg, State) ->
    {noreply, State}.

terminate(_, _State) -> ok.

code_change(_OldVsn, State, _Extra) -> {ok, State}.

store_state(Data)->
    [{'from', From}
    ,{'test_case', Test}
    ,{'sent_time', SentTime}
    ,{'data', Payload}] = Data,
    [{'id', node()}
     ,{'from', From}
     ,{'test_case', Test}
     ,{'sent_time', SentTime}
     ,{'update_time', erlang:monotonic_time()}
     ,{'data', Payload}].

make_process_name() ->
    NodeBin = atom_to_binary(node(), latin1),
    binary_to_atom(<<"test_server_", NodeBin/binary>>, latin1).
