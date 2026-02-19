require 'minitest/autorun'
require_relative '../websocket'
require 'tempfile'

class WebsocketServerTest < Minitest::Test
  def start_server(tls: false)
    port = rand(20_000..40_000)
    server = TCPServer.new(port)

    cert_file, key_file = nil

    if tls
      key = OpenSSL::PKey::RSA.new(2048)
      cert = OpenSSL::X509::Certificate.new
      cert.subject = cert.issuer = OpenSSL::X509::Name.parse('/CN=localhost')
      cert.public_key = key.public_key
      cert.not_before = Time.now
      cert.not_after = Time.now + 3600
      cert.serial = 1
      cert.version = 2
      cert.sign(key, OpenSSL::Digest.new('SHA256'))

      cert_file = Tempfile.new('cert')
      key_file = Tempfile.new('key')
      cert_file.write(cert.to_pem)
      cert_file.close
      key_file.write(key.to_pem)
      key_file.close
    end

    thr = Thread.new do
      ws = WebsocketServer.accept(server,
                                  tls: tls,
                                  cert: cert_file&.path,
                                  key: key_file&.path)
      while (msg = ws.receive)
        break if msg == :close

        ws.send(msg)
      end
    end

    [port, thr]
  end

  def test_plain_echo
    port, thr = start_server
    ws = WebsocketServer.connect('localhost', port)
    ws.send('hello')
    assert_equal 'hello', ws.receive
    ws.send('', 0x8)
    thr.kill
  end

  def test_fragmentation
    port, thr = start_server
    ws = WebsocketServer.connect('localhost', port)
    ws.send('abcdefghij', 1, fragment: 3)
    assert_equal 'abcdefghij', ws.receive
    ws.send('', 0x8)
    thr.kill
  end

  def test_large_payload
    port, thr = start_server
    ws = WebsocketServer.connect('localhost', port)
    big = 'a' * 100_000
    ws.send(big)
    assert_equal big, ws.receive
    ws.send('', 0x8)
    thr.kill
  end

  def test_tls_echo
    port, thr = start_server(tls: true)
    ws = WebsocketServer.connect('localhost', port, '/', tls: true)
    ws.send('secure')
    assert_equal 'secure', ws.receive
    ws.send('', 0x8)
    thr.kill
  end
end
