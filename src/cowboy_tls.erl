%% Copyright (c) 2015-2017, Loïc Hoguin <essen@ninenines.eu>
%%
%% Permission to use, copy, modify, and/or distribute this software for any
%% purpose with or without fee is hereby granted, provided that the above
%% copyright notice and this permission notice appear in all copies.
%%
%% THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
%% WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
%% MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
%% ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
%% WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
%% ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
%% OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.

-module(cowboy_tls).
-behavior(ranch_protocol).

-export([start_link/4]).
-export([proc_lib_hack/5]).

-spec start_link(ranch:ref(), ssl:sslsocket(), module(), cowboy:opts()) -> {ok, pid()}.
start_link(Ref, Socket, Transport, Opts) ->
	Pid = proc_lib:spawn_link(?MODULE, proc_lib_hack, [self(), Ref, Socket, Transport, Opts]),
	{ok, Pid}.

-spec proc_lib_hack(pid(), ranch:ref(), ssl:sslsocket(), module(), cowboy:opts()) -> ok.
proc_lib_hack(Parent, Ref, Socket, Transport, Opts) ->
	try
		init(Parent, Ref, Socket, Transport, Opts)
	catch
		_:normal -> exit(normal);
		_:shutdown -> exit(shutdown);
		_:Reason = {shutdown, _} -> exit(Reason);
		_:Reason -> exit({Reason, erlang:get_stacktrace()})
	end.

-spec init(pid(), ranch:ref(), ssl:sslsocket(), module(), cowboy:opts()) -> ok.
init(Parent, Ref, Socket, Transport, Opts) ->
	ok = ranch:accept_ack(Ref),
	case ssl:negotiated_protocol(Socket) of
		{ok, <<"h2">>} ->
			init(Parent, Ref, Socket, Transport, Opts, cowboy_http2);
		_ -> %% http/1.1 or no protocol negotiated.
			init(Parent, Ref, Socket, Transport, Opts, cowboy_http)
	end.

init(Parent, Ref, Socket, Transport, Opts, Protocol) ->
	{Handler, Type} = maps:get(stream_handler, Opts, {cowboy_stream_h, supervisor}),
	_ = case Type of
		worker -> ok;
		supervisor -> process_flag(trap_exit, true)
	end,
	Protocol:init(Parent, Ref, Socket, Transport, Opts, Handler).
