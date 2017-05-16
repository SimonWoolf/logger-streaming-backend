use Mix.Config

# Only used for testing, don't incorporate these into your own project

# chosen randomly, likely to be unused
config :logger_streaming_backend, port: 3796

config :logger,
  backends: [LoggerStreamingBackend],
  level: :debug
