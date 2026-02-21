require 'minitest/autorun'
require 'tmpdir'
require 'fileutils'
require 'json'
require 'socket'
require_relative '../monitor_server'
require_relative '../websocket'

class MonitorServerTest < Minitest::Test
  def setup
    @dir = Dir.mktmpdir
    @log_path = File.join(@dir, 'metrics.log')
    @port = rand(20_000..40_000)
  end

  def teardown
    @server_thread&.kill
    @tcp_server&.close rescue nil
    FileUtils.rm_rf(@dir)
  end

  def start_monitor_server
    @tcp_server = TCPServer.new(@port)
    monitor = MonitorServer.new(@tcp_server, log_path: @log_path)
    @server_thread = Thread.new { monitor.start }
    sleep 0.05 # let server bind
    monitor
  end

  # --- Construction ---

  def test_initialize_creates_log_file_directory
    nested = File.join(@dir, 'sub', 'metrics.log')
    tcp = TCPServer.new(0)
    MonitorServer.new(tcp, log_path: nested)
    assert Dir.exist?(File.join(@dir, 'sub'))
    tcp.close
  end

  def test_log_path_accessor
    tcp = TCPServer.new(0)
    monitor = MonitorServer.new(tcp, log_path: @log_path)
    assert_equal File.expand_path(@log_path), monitor.log_path
    tcp.close
  end

  # --- Single metric via WebSocket ---

  def test_receives_single_metric_and_logs_it
    start_monitor_server

    ws = WebsocketServer.connect('localhost', @port)
    metric = { name: 'cpu_usage', value: 72.5, host: 'srv1' }.to_json
    ws.send(metric)

    # Give server time to process
    sleep 0.1
    ws.send('', 0x8) # close

    lines = File.readlines(@log_path)
    assert_equal 1, lines.size
    logged = JSON.parse(lines.first)
    assert_equal 'cpu_usage', logged['name']
    assert_equal 72.5, logged['value']
    assert_equal 'srv1', logged['host']
    assert logged.key?('received_at'), 'expected received_at timestamp'
  end

  # --- Multiple metrics ---

  def test_receives_multiple_metrics_sequentially
    start_monitor_server

    ws = WebsocketServer.connect('localhost', @port)
    3.times do |i|
      ws.send({ name: "metric_#{i}", value: i }.to_json)
    end

    sleep 0.1
    ws.send('', 0x8)

    lines = File.readlines(@log_path)
    assert_equal 3, lines.size
    lines.each_with_index do |line, i|
      parsed = JSON.parse(line)
      assert_equal "metric_#{i}", parsed['name']
      assert_equal i, parsed['value']
    end
  end

  # --- Multiple concurrent clients ---

  def test_concurrent_clients
    start_monitor_server

    clients = 5
    msgs_per_client = 10

    threads = (1..clients).map do |c|
      Thread.new do
        ws = WebsocketServer.connect('localhost', @port)
        msgs_per_client.times do |i|
          ws.send({ name: "c#{c}_m#{i}", value: i }.to_json)
        end
        sleep 0.05
        ws.send('', 0x8)
      end
    end

    threads.each(&:join)
    sleep 0.1

    lines = File.readlines(@log_path)
    assert_equal clients * msgs_per_client, lines.size,
                 "expected #{clients * msgs_per_client} log lines, got #{lines.size}"

    # Every line is valid JSON
    lines.each_with_index do |line, idx|
      parsed = JSON.parse(line)
      assert parsed.key?('name'), "line #{idx} missing 'name'"
      assert parsed.key?('received_at'), "line #{idx} missing 'received_at'"
    end
  end

  # --- Invalid JSON is logged as raw ---

  def test_invalid_json_logged_as_raw
    start_monitor_server

    ws = WebsocketServer.connect('localhost', @port)
    ws.send('not valid json {{{')
    sleep 0.1
    ws.send('', 0x8)

    lines = File.readlines(@log_path)
    assert_equal 1, lines.size
    parsed = JSON.parse(lines.first)
    assert_equal 'not valid json {{{', parsed['raw']
    assert parsed.key?('received_at')
  end

  # --- Timestamp present ---

  def test_received_at_is_iso8601
    start_monitor_server

    ws = WebsocketServer.connect('localhost', @port)
    ws.send({ name: 'test' }.to_json)
    sleep 0.1
    ws.send('', 0x8)

    line = File.readlines(@log_path).first
    parsed = JSON.parse(line)
    ts = parsed['received_at']
    assert_match(/\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}/, ts)
  end

  # --- Graceful close ---

  def test_client_close_does_not_crash_server
    start_monitor_server

    ws = WebsocketServer.connect('localhost', @port)
    ws.send({ name: 'before_close' }.to_json)
    sleep 0.05
    ws.send('', 0x8)
    sleep 0.05

    # Server should still accept new connections
    ws2 = WebsocketServer.connect('localhost', @port)
    ws2.send({ name: 'after_close' }.to_json)
    sleep 0.05
    ws2.send('', 0x8)

    lines = File.readlines(@log_path)
    assert_equal 2, lines.size
    names = lines.map { |l| JSON.parse(l)['name'] }
    assert_includes names, 'before_close'
    assert_includes names, 'after_close'
  end

  # --- Plain-text metric (non-JSON) ---

  def test_plain_text_metric
    start_monitor_server

    ws = WebsocketServer.connect('localhost', @port)
    ws.send('cpu 42.0 1709000000')
    sleep 0.1
    ws.send('', 0x8)

    line = File.readlines(@log_path).first
    parsed = JSON.parse(line)
    assert_equal 'cpu 42.0 1709000000', parsed['raw']
  end

  # --- Metrics written with FileLogger concurrency guarantees ---

  def test_no_lost_writes_under_load
    start_monitor_server

    clients = 8
    msgs = 20

    threads = (1..clients).map do |c|
      Thread.new do
        ws = WebsocketServer.connect('localhost', @port)
        msgs.times do |i|
          ws.send({ name: "load_c#{c}", value: i }.to_json)
        end
        sleep 0.05
        ws.send('', 0x8)
      end
    end

    threads.each(&:join)
    sleep 0.2

    lines = File.readlines(@log_path)
    assert_equal clients * msgs, lines.size,
                 "expected #{clients * msgs} lines, got #{lines.size}"
  end
end
