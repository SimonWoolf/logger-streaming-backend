defmodule LoggerStreamingBackend.Html do
  use Eml
  use Eml.Language.HTML

  precompile log_template do
    p [class: :level] do
      span [class: "time"], :timestamp
      span [class: "level"], :level
      span [class: "metadata"], :metadata
      br []
      span [class: "message colorlevel"], :message
    end
  end

  @spec format(atom(), String.t, {tuple(), tuple()}, Keyword.t) :: String.t
  def format(level, message, {_date, time}, metadata) do
    bound_template = log_template(
      message: IO.chardata_to_string(message),
      level: Atom.to_string(level),
      timestamp: Logger.Formatter.format_time(time) |> :erlang.list_to_binary,
      metadata: Logger.Formatter.format([:metadata], nil, nil, nil, metadata) |> :erlang.list_to_binary
    )
    Eml.render(bound_template)
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

