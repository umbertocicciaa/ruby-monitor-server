require 'json'
require 'time'
require_relative 'websocket'
require_relative 'file_logger'

class MonitorServer
  attr_reader :log_path

  # @param tcp_server [TCPServer] a bound TCP server socket.
  # @param log_path   [String]    path to the metrics log file.
  def initialize(tcp_server, log_path:)
    @tcp_server = tcp_server
    @logger = FileLogger.new(log_path)
    @log_path = @logger.path
  end

  # Blocking – accepts connections in a loop, one thread per client.
  def start
    loop do
      begin
        ws = WebsocketServer.accept(@tcp_server)
      rescue StandardError
        next
      end

      Thread.new(ws) { |conn| handle_client(conn) }
    end
  end

  private

  def handle_client(ws)
    loop do
      msg = ws.receive
      break if msg.nil? || msg == :close

      record = build_record(msg)
      @logger.write(record.to_json)
    end
  rescue StandardError
    # client disconnected unexpectedly – nothing to do
  end

  def build_record(raw_message)
    record = begin
      parsed = JSON.parse(raw_message)
      parsed.is_a?(Hash) ? parsed : { 'raw' => raw_message }
    rescue JSON::ParserError
      { 'raw' => raw_message }
    end

    record['received_at'] = Time.now.iso8601
    record
  end
end
