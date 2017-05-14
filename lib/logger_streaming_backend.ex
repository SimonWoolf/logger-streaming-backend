defmodule LoggerStreamingBackend do
  use GenEvent
  defstruct default_level: nil, metadata: nil, separator: nil, handlers: nil, prior_global_level: nil, formatter: nil

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
       handlers: config[:handlers] || [],
       formatter: config[:formatter] || LoggerStreamingBackend.Html
     }
  end

  defp add_handler(opts, state = %{prior_global_level: nil}) do
    # First handler added. Store the prior log level.
    prior_global_level = Application.get_env(:logger, :level)
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
         {^key, ^value} -> true
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

  defp set_global_log_level(level) when is_atom(level) do
    # Need to do this in a task because Logger.Config.configure is part of the
    # same GenEvent that this handler is in -- if we do a call directly, we'll
    # be deadlocked
    Task.start(fn -> Logger.configure(level: level) end)
  end
end
