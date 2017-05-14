defmodule LoggerStreamingBackend.Html do
  use Eml
  use Eml.HTML

  template log_template do
    p [class: @level] do
      span [class: "time"], @timestamp
      span [class: "level"], @level
      span [class: "metadata"], @metadata
      br()
      span [class: "message colorlevel"], @message
    end
  end

  def format(level, message, {_date, time}, metadata) do
    {:safe, msg} = log_template(
      message: message,
      level: Atom.to_string(level),
      timestamp: Logger.Utils.format_time(time) |> :erlang.list_to_binary,
      metadata: Logger.Formatter.format([:metadata], nil, nil, nil, metadata) |> :erlang.list_to_binary
    )
    msg
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

