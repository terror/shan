-module(shan_ffi).
-export([get_line/1, open_url/1, get_home/0, system_time_seconds/0,
         start_listener/1, accept_callback/2, ensure_started/0,
         http_post/3, http_post_with_headers/4]).

ensure_started() ->
    application:ensure_all_started(inets),
    application:ensure_all_started(ssl),
    nil.

http_post(Url, ContentType, Body) ->
    UrlStr = binary_to_list(Url),
    CtStr = binary_to_list(ContentType),
    BodyStr = binary_to_list(Body),
    Headers = [{"Accept", "application/json"}],
    case httpc:request(post, {UrlStr, Headers, CtStr, BodyStr},
                       [{timeout, 30000},
                        {ssl, [{verify, verify_none}]}],
                       [{body_format, binary}]) of
        {ok, {{_, Status, _}, _, RespBody}} ->
            {ok, {Status, RespBody}};
        {error, Reason} ->
            Msg = list_to_binary(io_lib:format("~p", [Reason])),
            {error, Msg}
    end.

http_post_with_headers(Url, ExtraHeaders, ContentType, Body) ->
    UrlStr = binary_to_list(Url),
    CtStr = binary_to_list(ContentType),
    BodyStr = binary_to_list(Body),
    Headers = [{binary_to_list(K), binary_to_list(V)} || {K, V} <- ExtraHeaders],
    case httpc:request(post, {UrlStr, Headers, CtStr, BodyStr},
                       [{timeout, 120000},
                        {ssl, [{verify, verify_none}]}],
                       [{body_format, binary}]) of
        {ok, {{_, Status, _}, _, RespBody}} ->
            {ok, {Status, RespBody}};
        {error, Reason} ->
            Msg = list_to_binary(io_lib:format("~p", [Reason])),
            {error, Msg}
    end.

get_line(Prompt) ->
    case io:get_line(Prompt) of
        eof -> {error, nil};
        {error, _} -> {error, nil};
        Line -> {ok, string:trim(Line, trailing, "\n")}
    end.

open_url(Url) ->
    case os:type() of
        {unix, darwin} -> os:cmd("open '" ++ binary_to_list(Url) ++ "'");
        {unix, _} -> os:cmd("xdg-open '" ++ binary_to_list(Url) ++ "'");
        _ -> ok
    end,
    nil.

get_home() ->
    case os:getenv("HOME") of
        false -> {error, nil};
        Home -> {ok, list_to_binary(Home)}
    end.

system_time_seconds() ->
    erlang:system_time(second).

start_listener(Port) ->
    case gen_tcp:listen(Port, [binary, {active, false}, {reuseaddr, true},
                               {ip, {127,0,0,1}}]) of
        {error, Reason} ->
            Msg = list_to_binary(io_lib:format("failed to listen on port: ~p", [Reason])),
            {error, Msg};
        {ok, LSock} ->
            {ok, LSock}
    end.

accept_callback(LSock, TimeoutMs) ->
    Result = accept_one(LSock, TimeoutMs),
    gen_tcp:close(LSock),
    Result.

accept_one(LSock, TimeoutMs) ->
    case gen_tcp:accept(LSock, TimeoutMs) of
        {error, timeout} -> {error, <<"timeout waiting for callback">>};
        {error, _} -> {error, <<"accept failed">>};
        {ok, Sock} ->
            case read_raw_request(Sock) of
                {error, _} ->
                    gen_tcp:close(Sock),
                    accept_one(LSock, TimeoutMs);
                {ok, Path} ->
                    case extract_params(Path) of
                        {ok, Code, State} ->
                            send_success_response(Sock),
                            gen_tcp:close(Sock),
                            {ok, {Code, State}};
                        {error, _} ->
                            send_not_found(Sock),
                            gen_tcp:close(Sock),
                            accept_one(LSock, TimeoutMs)
                    end
            end
    end.

read_raw_request(Sock) ->
    case gen_tcp:recv(Sock, 0, 5000) of
        {ok, Data} ->
            case binary:split(Data, <<" ">>, [global]) of
                [_, Path | _] -> {ok, Path};
                _ -> {error, <<"could not parse request">>}
            end;
        {error, _} ->
            {error, <<"recv failed">>}
    end.

extract_params(Path) ->
    case binary:split(Path, <<"?">>) of
        [_, Query] ->
            Params = uri_string:dissect_query(Query),
            Code = proplists:get_value(<<"code">>, Params),
            State = proplists:get_value(<<"state">>, Params),
            case {Code, State} of
                {undefined, _} -> {error, <<"missing code parameter">>};
                {_, undefined} -> {error, <<"missing state parameter">>};
                {C, S} -> {ok, C, S}
            end;
        _ ->
            {error, <<"no query string in callback">>}
    end.

send_success_response(Sock) ->
    Body = <<"<!DOCTYPE html><html><body><h1>Authenticated!</h1>"
             "<p>You can close this tab and return to shan.</p>"
             "</body></html>">>,
    Resp = iolist_to_binary([
        <<"HTTP/1.1 200 OK\r\n"
          "Content-Type: text/html\r\n"
          "Connection: close\r\n"
          "Content-Length: ">>,
        integer_to_binary(byte_size(Body)),
        <<"\r\n\r\n">>,
        Body]),
    gen_tcp:send(Sock, Resp).

send_not_found(Sock) ->
    Resp = <<"HTTP/1.1 404 Not Found\r\nConnection: close\r\n\r\n">>,
    gen_tcp:send(Sock, Resp).
