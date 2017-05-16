defmodule LoggerStreamingBackendTest do
  use ExUnit.Case, async: false # some tests change the global log level, so can't run in parallel
  require Logger
  doctest LoggerStreamingBackend

  setup_all do
    {:ok, _} = :cowboy.start_http(
      :logger_streaming_backend,
      10,
      [port: port()],
      [env: [dispatch: routes()]]
    )
    IO.puts "Started cowboy on port #{inspect port()}"

    :ok
  end

  test "Default headers, intro, basic functionality" do
    id = stream_log("log", [])
    assert_receive %HTTPoison.AsyncStatus{code: 200}

    # Check basic headers
    assert_receive %HTTPoison.AsyncHeaders{headers: headers}
    assert Enum.member? headers, {"transfer-encoding", "chunked"}
    assert Enum.member? headers, {"content-type", "text/html"}
    assert Enum.member? headers, {"connection", "close"}
    # Check additional header
    assert Enum.member? headers, {"X-Additional-Header", "foo"}

    # Check html intro
    assert_receive %HTTPoison.AsyncChunk{chunk: chunk}
    assert String.starts_with? chunk, "<html>"
    assert String.contains? chunk, "<head>"
    assert String.contains? chunk, "</head>"
    assert String.ends_with? String.trim(chunk), "<body>"

    # Send a log, check it's received
    Logger.configure_backend(LoggerStreamingBackend, metadata: [:some_metadata])
    Logger.error "error-log", some_metadata: "foo"

    assert_receive %HTTPoison.AsyncChunk{chunk: chunk}
    assert String.starts_with? chunk, "<p class='error'>"
    assert String.contains? chunk, "error-log"
    assert String.contains? chunk, "some_metadata=foo"

    stop_stream(id)
    flush()
  end

  test "Custom headers" do
    id = stream_log("log_custom_headers", [])
    assert_receive %HTTPoison.AsyncStatus{code: 200}

    assert_receive %HTTPoison.AsyncHeaders{headers: headers}
    # Check custom header
    assert Enum.member? headers, {"X-Header", "foo"}
    # Check do not have the default optional headers
    assert !Enum.member? headers, {"content-type", "text/html"}
    assert !Enum.member? headers, {"connection", "close"}
    # ... but do still have the essential (transfer-encoding) header
    assert Enum.member? headers, {"transfer-encoding", "chunked"}

    stop_stream(id)
    flush()
  end

  test "Basic auth, no auth creds" do
    # Without auth creds
    id = stream_log("log_basic_auth", [])
    assert_receive %HTTPoison.AsyncStatus{code: 401}
    assert_receive %HTTPoison.AsyncHeaders{headers: headers}
    assert Enum.member? headers, {"Www-Authenticate", "Basic realm=\"log\""}

    stop_stream(id)
    flush()
  end

  test "Basic auth, withauth creds" do
    id = stream_log("log_basic_auth", [], basic_creds())
    assert_receive %HTTPoison.AsyncStatus{code: 200}
    assert_receive %HTTPoison.AsyncHeaders{headers: headers}
    assert !Enum.member? headers, {"Www-Authenticate", "Basic realm=\"log\""}

    stop_stream(id)
    flush()
  end

  test "Only streams up to requested log level" do
    id = stream_log("log", [level: :warn])
    assert_receive %HTTPoison.AsyncStatus{code: 200}
    assert_receive %HTTPoison.AsyncHeaders{headers: _}
    assert_receive %HTTPoison.AsyncChunk{chunk: _}

    # Send log of each type, check only, check it's received
    Logger.error "error-log"
    Logger.warn "warn-log"
    Logger.info "info-log"
    Logger.debug "debug-log"

    #Only two should received
    assert_receive %HTTPoison.AsyncChunk{chunk: first_chunk}
    assert_receive %HTTPoison.AsyncChunk{chunk: second_chunk}
    refute_receive %HTTPoison.AsyncChunk{chunk: _}

    assert String.starts_with? first_chunk, "<p class='error'>"
    assert String.starts_with? second_chunk, "<p class='warn'>"

    stop_stream(id)
    flush()
  end

  test "metadata filter" do
    Logger.configure(level: :debug)
    Logger.configure_backend(LoggerStreamingBackend, metadata: [:uuid])
    Logger.metadata [uuid: "foo"]

    id_foo = stream_log("log", [level: :debug, scope: "uuid:foo"])
    id_bar = stream_log("log", [level: :debug, scope: "uuid:bar"])
    assert_receive %HTTPoison.AsyncStatus{code: 200, id: ^id_foo}
    assert_receive %HTTPoison.AsyncStatus{code: 200, id: ^id_bar}
    assert_receive %HTTPoison.AsyncHeaders{headers: _, id: ^id_foo}
    assert_receive %HTTPoison.AsyncHeaders{headers: _, id: ^id_bar}
    assert_receive %HTTPoison.AsyncChunk{chunk: _, id: ^id_foo}
    assert_receive %HTTPoison.AsyncChunk{chunk: _, id: ^id_bar}

    Logger.debug "success"

    assert_receive %HTTPoison.AsyncChunk{chunk: chunk, id: ^id_foo}
    refute_receive %HTTPoison.AsyncChunk{chunk: _, id: ^id_bar}

    assert String.contains? chunk, "success"

    stop_stream(id_foo)
    stop_stream(id_bar)
    flush()
  end

  # Helpers
  #########

  defp routes() do
    :cowboy_router.compile([
      { :_,
        [
          {"/log", LoggerStreamingBackend.HttpStreamHandler, [additional_headers: [{"X-Additional-Header", "foo"}]]},
          {"/log_custom_headers", LoggerStreamingBackend.HttpStreamHandler, [headers: [{"X-Header", "foo"}]]},
          {"/log_basic_auth", LoggerStreamingBackend.HttpStreamHandler, [basic: basic_creds()]},
        ]
      }
    ])
  end

  defp stream_log(path, params, creds \\ nil) do
    auth = case creds do
      {user, pass} -> "#{user}:#{pass}@"
      nil -> ""
    end

    uri = "http://#{auth}localhost:#{port()}/#{path}?#{URI.encode_query(params)}"
    %{id: id} = HTTPoison.get! uri, [], stream_to: self()
    id
  end

  defp stop_stream(id) do
    :hackney.stop_async(id)
  end

  defp port do
    Application.fetch_env!(:logger_streaming_backend, :port)
  end

  defp basic_creds do
    {"username", "password"}
  end

  defp flush do
    receive do
      _ -> flush()
    after
      0 -> nil
    end
  end
end
