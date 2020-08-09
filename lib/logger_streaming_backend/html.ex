defmodule LoggerStreamingBackend.Html do
  use Temple
  require EEx

  log_message_template = temple do
    p class: level do
      span class: "time", do: timestamp
      span class: "level", do: level
      span class: "metadata", do: metadata
      br
      span class: "message colorlevel", do: message
    end
  end

  EEx.function_from_string(:def, :log_message, log_message_template, [:message, :level, :timestamp, :metadata])

  @spec format(atom(), String.t, {tuple(), tuple()}, Keyword.t) :: String.t
  def format(level, message, {_date, time}, metadata) do
    log_message(
      IO.chardata_to_string(message),
      Atom.to_string(level),
      Logger.Formatter.format_time(time) |> :erlang.list_to_binary,
      Logger.Formatter.format([:metadata], nil, nil, nil, metadata) |> :erlang.list_to_binary
    )
  end

  def header do
    # Can't use eml for this as need to open html and body tags without closing them
    """
    <html>
      <head>
        <style>
        p { font-family: sans-serif; margin-bottom: 1em; }
        span { margin-right: 0.5em }
        .error > .colorlevel { color: red; }
        .warn  > .colorlevel { color: darkorange; }
        .info  > .colorlevel { color: black; }
        .debug > .colorlevel { color: darkcyan; }
        .time { font-style: italic; font-size: 85%; }
        .level { font-size: 85%; }
        .metadata { font-style: italic; font-size: 85%; }
        </style>
      </head>
      <body>
    """
  end

  def footer do
    "</body></html>"
  end
end

