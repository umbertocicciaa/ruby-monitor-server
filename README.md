# Monitor Server

A lightweight WebSocket server and client implementation in pure Ruby with optional TLS support. No external dependencies beyond the Ruby standard library.

## Features

- **RFC 6455 compliant** WebSocket handshake (server and client)
- **TLS/SSL** support for encrypted connections
- **Message fragmentation** — send large payloads in configurable chunk sizes
- **Ping/pong** handling built in
- **Client masking** per the WebSocket spec

## Requirements

- Ruby 2.7+

## Usage

### Server

```ruby
require_relative 'websocket'

server = TCPServer.new(8080)

loop do
  ws = WebsocketServer.accept(server)

  while (msg = ws.receive)
    break if msg == :close
    ws.send(msg) # echo
  end
end
```

### Server with TLS

```ruby
ws = WebsocketServer.accept(
  server,
  tls: true,
  cert: 'path/to/cert.pem',
  key: 'path/to/key.pem'
)
```

### Client

```ruby
ws = WebsocketServer.connect('localhost', 8080)
ws.send('hello')
puts ws.receive  # => "hello"
ws.send('', 0x8) # close frame
```

### Client with TLS

```ruby
ws = WebsocketServer.connect('localhost', 8080, '/', tls: true)
```

### Fragmentation

Send a message split into frames of at most `n` bytes:

```ruby
ws.send('large payload here', 1, fragment: 1024)
```

## Running Tests

```sh
rake test
```

## License

See the project root for license details.
