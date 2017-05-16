use Mix.Config

# chosen randomly, likely to be unused
config :logger_streaming_backend, port: 3796

config :logger,
  backends: [LoggerStreamingBackend],
  level: :debug
