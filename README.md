# LoggerStreamingBackend

Backend for the Elixir `Logger` that streams logs over HTTP.

- Specify the log level with a `level` querystring param (and it will change the global log level if necessary to acommodate while the stream is open).
- Specify a `scope` to filter the log stream by metadata. E.g. in the below, adding `&scope=uuid:someuuid` would restrict the logs to only messages with that uuid in their custom metadata.

![log](https://cloud.githubusercontent.com/assets/5908687/26052912/d61bfdc6-395e-11e7-9a38-3cc146766271.png)

## Installation

To use, add to mix.exs:

```elixir
defp deps() do
  [{:logger_streaming_backend, "~> 0.1"}]
end
```

and run `mix deps.get`. Then add it as a `:logger` backend -- for example, in
`config/config.exs`:

```elixir
config :logger,
  backends: [:console, LoggerStreamingBackend]
```

You'll also need to add the http stream handler to your preferred webserver.
A cowboy handler is provided, for cowboy 1.x. To use, it, add

```elixir
{"/your/preferred/path", LoggerStreamingBackend.HttpStreamHandler, []}
```

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

```elixir
config :logger, LoggerStreamingBackend,
  metadata: [:module, :line, :some_custom_key]
```

The HttpStreamHandler supports an `:additional_headers` option if you'd like
to add your own headers to the defaults, or a `:headers` option to replace
the defaults. E.g.:

```elixir
{"/path", LoggerStreamingBackend.HttpStreamHandler, [additional_headers: [{"X-Custom-Header", "foo"}]]}
```

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

## License

This software is licensed under the GNU LGPL, version 3 or any later
version. This just ensures that if you improve it, you have to make your
improvements available to everyone -- Hopefully, you were going to
anyway :). See the LICENSE.md file for details.
