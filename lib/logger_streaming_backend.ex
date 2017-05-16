defmodule LoggerStreamingBackend do
  @moduledoc """
  `Logger` backend that streams logs over HTTP.

  ## Installation

  To use, add to mix.exs:

      defp deps() do
        [{:logger_streaming_backend, "~> 0.1"}]
      end

  and run `mix deps.get`. Then add it as a `:logger` backend -- for example, in
  `config/config.exs`:

      config :logger,
        backends: [:console, LoggerStreamingBackend]

  You'll also need to add the http stream handler to your preferred webserver.
  A cowboy handler is provided, for cowboy 1.x. To use, it, add

      {"/your/preferred/path", LoggerStreamingBackend.HttpStreamHandler, []},

  to your cowboy routes.

  Currently only cowboy 1.x is supported, as that's what I use. If you'd like
  to add a handler for other versions of cowboy / other webservers / Plug
  middleware etc., please feel free to submit a pull request.

  ## Configuration

  `LoggerStreamingBackend` supports the following configuration options:

    * `:metadata` - (list of atoms) list of metadata to be attached to the
      reported message. Defaults to `[]`. See the `Logger` docs for list of
      builtins and details of how to use custom metadata.
    * `:separator` - (String) separates the key from value in the scope
      querystring param, e.g. in "file:foobar.ex". Defaults to ":", (since
      equals is already part of the querystring syntax).
    * `:default_level` - (atom) The log level to use if none is specified in
      the querystring params. Defalts to `:debug`.
    * `:formatter` - (atom) Defaults to `LoggerStreamingBackend.Html`. With
      HTML output, custom formats can be a lot more flexible than with plain
      text. To customise it, you can supply your own HTML formatter backend,
      that implements the same format() function.

  To configure these (similarly in e.g. `config/config.exs`):

      config :logger, LoggerStreamingBackend,
        metadata: [:module, :line, :some_custom_key]

  The HttpStreamHandler supports the following options:

   * `:additional_headers` (list of 2-tuples), if you'd like to add your own
      headers to the defaults
   * `:headers` (list of 2-tuples), to completely replace the defaults
   * `:basic` (tuple of username and password) to use basic auth on the log
      endpoint
   * `:req_filter` (tuple of fn : req -> bool, and msg to return on failure)
      for customisable auth

  E.g.

      {"/path", LoggerStreamingBackend.HttpStreamHandler, [
        additional_headers: [{"X-Custom-Header", "foo"}],
        basic: {"username", "password"}
      ]},

  Note that log level (and the metadata filter feature) are not part of the
  configuration. This is because they're passed as querystring params, so they
  can be different for each stream.

  ## Usage

  Visit the path you configured, with some querystring parameters: `level`, and
  `scope`. The `level` is a log level, the `scope` is for setting a metadata
  filter, of the form `key:value`. For example, if you have some custom
  metadata called "appid", to only show logs for which that metadata has been
  set and equals "foo", you can do:

      http://localhost:4000/log?level=debug&scope=appid:foo

  Metadata values are matched as strings. Note that that means that if you want
  all log lines from a specific mdoule, you need to specify the 'expanded'
  version of the module name atom. For example, `MyApp.Foo` is really
  `:"Elixir.MyApp.Foo"`, so you should do:

      http://localhost:4000/log?level=debug&scope=module:Elixir.MyApp.Foo

  (Don't forget, any metadata you want to filter on needs to have been
  configured for the backend using `config :logger, LoggerStreamingBackend,
  metadata: [...]`.)

  If the `:logger` log level is higher than the level you request, it will
  temporarily lower it, then raise it again when you close the stream. This
  should all just work with multiple streams, with the level being set to the
  lowest of any of the streams currently open.

  Make sure you don't have a `compile_time_purge_level` set, or this won't work
  below that level, as all the logger calls below that level will have been
  removed at compile time. If you have expensive debug-level logging, you may
  wish to consider wrapping them in zero-arity fns -- see the `Logger` docs for
  more information.
  """

  use GenEvent
  defstruct default_level: nil, metadata: nil, separator: nil, handlers: [], prior_global_level: nil, formatter: nil

  def init(__MODULE__) do
    {:ok, configure_defaults([])}
  end

  # GenServer callbacks
  #####################

  def handle_call({:configure, [add_handler: opts]}, state) do
    {:ok, :ok, add_handler(opts, state)}
  end

  def handle_call({:configure, [remove_handler: pid]}, state) do
    {:ok, :ok, remove_handler(pid, state)}
  end

  def handle_call({:configure, opts}, state) do
    {:ok, :ok, configure_defaults(opts, state)}
  end

  def handle_event({_level, gl, _event}, state) when node(gl) != node() do
    # Ignore non-local
    {:ok, state}
  end

  def handle_event({level, _gl, {Logger, msg, timestamp, metadata}}, state = %{handlers: handlers, metadata: keys, formatter: formatter}) do
    for handler <- handlers do
      if should_log(level, handler.level, metadata, handler.metadata_filter) do
        message = formatter.format(level, msg, timestamp, take_metadata(metadata, keys))
        send(handler.pid, {:log, message})
      end
    end
    {:ok, state}
  end

  def handle_event(:flush, state) do
    # We're not buffering anything so this is a no-op
    {:ok, state}
  end

  # Helpers
  #########

  defp should_log(level, handler_level, metadata, metadata_filter) do
    meet_level?(level, handler_level) &&
    (!metadata_filter || metadata_filter.(metadata))
  end

  defp configure_defaults(opts, state \\ %__MODULE__{}) do
    config =
      Application.get_env(:logger, __MODULE__, [])
      |> Keyword.merge(opts)
    Application.put_env(:logger, __MODULE__, config)

    %__MODULE__{state |
       default_level: config[:level] || :debug,
       metadata: config[:metadata] || [],
       separator: config[:separator] || ":",
       formatter: config[:formatter] || LoggerStreamingBackend.Html
     }
  end

  defp add_handler(opts, state = %{prior_global_level: nil}) do
    # First handler added. Store the prior log level.
    prior_global_level = Application.get_env(:logger, :level, :debug)
    add_handler(opts, %__MODULE__{state | prior_global_level: prior_global_level})
  end

  defp add_handler(opts, state = %{handlers: handlers, metadata: metadata}) do
    pid = opts[:pid]
    level = process_level(opts[:level]) || state.default_level
    metadata_filter = metadata_filter_from_scope(opts[:scope], metadata)

    new_handler = %{pid: pid,
       level: level,
       metadata_filter: metadata_filter
     }
    %__MODULE__{state | handlers: [new_handler | handlers]}
    |> set_global_log_level()
  end

  defp remove_handler(pid_to_remove, state = %{handlers: handlers}) do
    index_of_removed = Enum.find_index(handlers, fn(%{pid: pid}) ->
      pid == pid_to_remove
    end)
    handlers = List.delete_at(handlers, index_of_removed)

    %__MODULE__{state | handlers: handlers}
    |> set_global_log_level()
  end

  # Taken from Logger.Backends.Console
  defp take_metadata(metadata, :all), do: metadata
  defp take_metadata(metadata, keys) do
    Enum.reduce keys, [], fn key, acc ->
      case Keyword.fetch(metadata, key) do
        {:ok, val} -> [{key, val} | acc]
        :error     -> acc
      end
    end
  end

  defp process_level(requested_level) do
    case requested_level do
      "debug" -> :debug
      "info"  -> :info
      "warn"  -> :warn
      "error" -> :error
      _ -> nil
    end
  end

  defp metadata_filter_from_scope(nil, _), do: nil
  defp metadata_filter_from_scope(scope, metadata_keys) do
    split = String.split(scope, ":")
    if match?([_, _], split) do
      [strkey, value] = split

      # A bit roundabout, but avoids converting potentially untrusted strings to atoms
      key = Enum.find(metadata_keys, fn(m) ->
        to_string(m) == strkey
      end)

      key && fn(metadata) ->
        Enum.any?(metadata, fn
           {^key, v} ->
             to_string(v) == value
         _ -> false
        end)
      end
    end
  end

  defp meet_level?(lvl, min) do
    Logger.compare_levels(lvl, min) != :lt
  end

  defp set_global_log_level(state = %{handlers: [], prior_global_level: prior_global_level}) do
    # No more handlers; restore global log level to whatever it was before
    set_global_log_level(prior_global_level)
    state
  end

  defp set_global_log_level(state = %{handlers: handlers, prior_global_level: prior_global_level}) do
    # Set to the lowest of the levels required by current handlers (or the
    # prior global level if that's lower than any of them)
    all_levels = [prior_global_level | Enum.map(handlers, &(&1[:level]))]
    required_level = Enum.reduce(all_levels, fn(level, current_lowest) ->
      if meet_level?(level, current_lowest) do
        current_lowest
      else
        level
      end
    end)

    set_global_log_level(required_level)
    state
  end

  defp set_global_log_level(nil), do: nil
  defp set_global_log_level(level) when is_atom(level) do
    # Need to do this in a task because Logger.Config.configure is part of the
    # same GenEvent that this handler is in -- if we do a call directly, we'll
    # be deadlocked
    Task.start(fn -> Logger.configure(level: level) end)
  end
end
