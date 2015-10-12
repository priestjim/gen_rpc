%%% ex: set ft=erlang fenc=utf-8 sts=4 ts=4 sw=4 et:
%%%
%%% Copyright 2015 Panagiotis Papadomitsos. All Rights Reserved.
%%%
%%% Use a gen_server to hold states between test calls.

-module(test_app_server).
-author("Panagiotis Papadomitsos <pj@ezgr.net>").

%%% CT Macros
-include_lib("test/gen_rpc/include/ct.hrl").

-beahviour(gen_server).

-export([start_link/1, terminate/2]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2]).
-export([code_change/3]).

-export([start_link/0, set/1, get/0]).

-record(state, {entry :: map()}).

-define(log, ct:pal).
-define(LogFmt(Func, Event), io_lib:format("module=\"~p\" function=\"~p\" event=\"~p\"",[?MODULE, Func, Event])).

start_link() ->
    Opts = [{'from', 0},
     {'id', node()},
     {'sent_time', 0},
     {'update_time', 0},
     {'data', <<"">>}],
    start_link(Opts).

start_link(Opts) ->
    ok = ?log(?LogFmt('start_link', 'start_link')),
    gen_server:start_link({local, node()}, ?MODULE, Opts, []).

set(Data) ->
    ok = ?log(?LogFmt('set', 'set_data')),
    gen_server:call('set', Data).  

get()->
    ok = ?log(?LogFmt('get', 'get_data')),
    gen_server:call('get').

init(Opts) ->
    ok = ?log(?LogFmt('init', 'init_state')),
    {ok, #state{entry=maps:from_list(Opts)}}.

handle_call({'set', Data}, _From, State) ->
    ok = ?log(?LogFmt('handle_call', 'set_data')),
    State  = store_state(State, Data),
    {reply, {ok, 'set'}, State};
handle_call('get', _From, State) ->
    ok = ?log(?LogFmt('handle_call', 'get_query')),
    {reply, {ok, State#state.entry, State}};
handle_call(terminate, _From, State) ->
    ok = ?log(?LogFmt('handle_call', 'terminate')),
    {stop, normal, ok, State};
handle_call(Unknown, _From, State) ->
    ok = ?log(?LogFmt('handle_call', 'unknown_msg')),
    {reply, {error, {'unknown_msg', Unknown}, State}}.

handle_cast({set, Data}, State) ->
    ok = ?log(?LogFmt('handle_cast', 'set_data')),
    State  = store_state(State, Data),
    {noreply, State};
handle_cast(_Msg, State) ->
    ok = ?log(?LogFmt('handle_cast', 'unknown_msg')),
    {noreply, State}.

handle_info('EXIT', State) ->
    ok = ?log(?LogFmt('handle_info', 'exit_signal')),
    {noreply, State};
handle_info(_Msg, State) ->
    ok = ?log(?LogFmt('handle_info', 'unknown_msg')),
    {noreply, State}.

terminate(_, _State) -> 
    ok = ?log(?LogFmt('terminate', 'terminate')),
    ok.

code_change(_OldVsn, State, _Extra) ->
    ok = ?log(?LogFmt('code_change', 'code_change')),
    {ok, State}.

store_state(State, Data)->
    Data0 = maps:put('update_time', os:timestamp(), Data), 
    State#state{ entry=maps:from_list(Data0)}.
