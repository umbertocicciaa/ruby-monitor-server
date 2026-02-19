require 'socket'
require 'openssl'
require 'digest/sha1'
require 'base64'
require 'securerandom'

class WebsocketServer
  GUID = '258EAFA5-E914-47DA-95CA-C5AB0DC85B11'

  def initialize(sock, client: false)
    @s = sock
    @client = client
    @frag_buffer = +''
    @frag_opcode = nil
  end

  def self.accept(server, tls: false, cert: nil, key: nil)
    sock = server.accept

    if tls
      ctx = OpenSSL::SSL::SSLContext.new
      ctx.cert = OpenSSL::X509::Certificate.new(File.read(cert))
      ctx.key  = OpenSSL::PKey::RSA.new(File.read(key))
      ssl = OpenSSL::SSL::SSLSocket.new(sock, ctx)
      ssl.sync_close = true
      ssl.accept
      sock = ssl
    end

    req = sock.readpartial(4096)
    ws_key = req[/Sec-WebSocket-Key: (.+)\r\n/, 1]
    return sock.close unless ws_key

    accept = Base64.strict_encode64(
      Digest::SHA1.digest(ws_key.strip + GUID)
    )

    sock.write "HTTP/1.1 101 Switching Protocols\r\n" \
               "Upgrade: websocket\r\n" \
               "Connection: Upgrade\r\n" \
               "Sec-WebSocket-Accept: #{accept}\r\n\r\n"

    new(sock)
  end

  def self.connect(host, port, path = '/', tls: false)
    tcp = TCPSocket.new(host, port)
    sock = tcp

    if tls
      ctx = OpenSSL::SSL::SSLContext.new
      ctx.verify_mode = OpenSSL::SSL::VERIFY_NONE
      ssl = OpenSSL::SSL::SSLSocket.new(tcp, ctx)
      ssl.sync_close = true
      ssl.connect
      sock = ssl
    end

    key = Base64.strict_encode64(SecureRandom.random_bytes(16))

    sock.write "GET #{path} HTTP/1.1\r\n" \
               "Host: #{host}:#{port}\r\n" \
               "Upgrade: websocket\r\n" \
               "Connection: Upgrade\r\n" \
               "Sec-WebSocket-Key: #{key}\r\n" \
               "Sec-WebSocket-Version: 13\r\n\r\n"

    sock.readpartial(4096)
    new(sock, client: true)
  end

  def send(data, opcode = 1, fragment: nil)
    payload = data.to_s.b
    frames = []

    if fragment && payload.bytesize > fragment
      first = true
      until payload.empty?
        chunk = payload.slice!(0, fragment)
        op = first ? opcode : 0
        fin = payload.empty?
        frames << build_frame(chunk, op, fin)
        first = false
      end
    else
      frames << build_frame(payload, opcode, true)
    end

    frames.each { |f| @s.write(f) }
  end

  def build_frame(payload, opcode, fin)
    header = []
    header << ((fin ? 0x80 : 0) | opcode)

    len = payload.bytesize
    mask_bit = @client ? 0x80 : 0

    if len < 126
      header << (mask_bit | len)
    elsif len < 65_536
      header << (mask_bit | 126)
      header += [len].pack('n').bytes
    else
      header << (mask_bit | 127)
      header += [len].pack('Q>').bytes
    end

    if @client
      mask = SecureRandom.random_bytes(4)
      header += mask.bytes
      payload = payload.bytes.each_with_index.map do |b, i|
        b ^ mask.getbyte(i % 4)
      end.pack('C*')
    end

    header.pack('C*') + payload
  end

  def receive
    loop do
      hdr = @s.read(2) or return nil
      b1, b2 = hdr.bytes

      fin = (b1 & 0x80) != 0
      opcode = b1 & 0x0F
      masked = (b2 & 0x80) != 0
      len = b2 & 0x7F

      len = @s.read(2).unpack1('n') if len == 126
      len = @s.read(8).unpack1('Q>') if len == 127

      mask = masked ? @s.read(4) : nil
      payload = len > 0 ? @s.read(len) : ''.b

      if masked
        payload = payload.bytes.each_with_index.map do |b, i|
          b ^ mask.getbyte(i % 4)
        end.pack('C*')
      end

      case opcode
      when 0x8
        send('', 0x8)
        close
        return :close
      when 0x9
        send(payload, 0xA)
        next
      when 0xA
        next
      when 0x0 # continuation
        @frag_buffer << payload
        if fin
          msg = @frag_buffer.dup
          @frag_buffer.clear
          return msg
        end
      else
        return payload if fin

        @frag_opcode = opcode
        @frag_buffer = payload

      end
    end
  end

  def close
    @s.close
  end
end
