defmodule LoggerStreamingBackend.HttpStreamHandler do
  def init(_type, req, opts) do
    if credentials = opts[:basic] do
      if match?({:ok, {"basic", ^credentials}, _}, :cowboy_req.parse_header("authorization", req)) do
        do_init(req, opts)
      else
        {:ok, req, opts[:realm] || "log"}
      end
    else
      do_init(req, opts)
    end
  end

  # Only used when failed basic auth
  def handle(req, realm) do
    {:ok, reply} = :cowboy_req.reply(401, [
      {"Www-Authenticate", "Basic realm=\"#{realm}\""}
    ], "Unauthorized", req)
    {:ok, reply, nil}
  end

  def do_init(req, opts) do
    {level, req} = :cowboy_req.qs_val("level", req, nil)
    {scope, req} = :cowboy_req.qs_val("scope", req, nil)

    Logger.configure_backend(LoggerStreamingBackend, [add_handler: [pid: self(), level: level, scope: scope]])

    headers = opts[:headers] || ((opts[:additional_headers] || []) ++ [
      {"content-type", "text/html"},
      # connection: close is recommended by cowboy for http loop handlers, see https://ninenines.eu/docs/en/cowboy/1.0/guide/loop_handlers/#cleaning_up
      {"connection", "close"}
    ])
    {:ok, req} = :cowboy_req.chunked_reply(200, headers, req)

    # Sends html header, style, etc
    :cowboy_req.chunk(LoggerStreamingBackend.Html.header, req)

    {:loop, req, :added_handler}
  end

  def info({:log, message}, req, state) do
    :cowboy_req.chunk(message, req)
    {:loop, req, state}
  end

  def info(:eof, req, state) do
    :cowboy_req.chunk(LoggerStreamingBackend.Html.footer, req)
    {:ok, req, state}
  end

  def info(_, req, state) do
    {:loop, req, state}
  end

  def terminate(_reason, _req, :added_handler) do
    Logger.configure_backend(LoggerStreamingBackend, [remove_handler: self()])
    :ok
  end

  def terminate(_reason, _req, _), do: :ok
end

