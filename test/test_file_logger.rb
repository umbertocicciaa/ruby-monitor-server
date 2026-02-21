require 'minitest/autorun'
require 'tmpdir'
require 'fileutils'
require_relative '../file_logger'

class FileLoggerTest < Minitest::Test
  def setup
    @dir = Dir.mktmpdir
    @log_path = File.join(@dir, 'test.log')
  end

  def teardown
    FileUtils.rm_rf(@dir)
  end

  def test_creates_file_on_first_write
    refute File.exist?(@log_path)
    logger = FileLogger.new(@log_path)
    logger.write('hello')
    assert File.exist?(@log_path)
  end

  def test_appends_single_line
    logger = FileLogger.new(@log_path)
    logger.write('first')
    logger.write('second')
    lines = File.readlines(@log_path).map(&:chomp)
    assert_equal %w[first second], lines
  end

  def test_write_adds_trailing_newline
    logger = FileLogger.new(@log_path)
    logger.write('line')
    raw = File.read(@log_path)
    assert raw.end_with?("\n"), "expected trailing newline"
  end

  def test_does_not_double_newline
    logger = FileLogger.new(@log_path)
    logger.write("already\n")
    raw = File.read(@log_path)
    assert_equal "already\n", raw
  end

  def test_appends_to_existing_content
    File.write(@log_path, "old line\n")
    logger = FileLogger.new(@log_path)
    logger.write('new line')
    lines = File.readlines(@log_path).map(&:chomp)
    assert_equal ['old line', 'new line'], lines
  end

  def test_write_with_timestamp
    logger = FileLogger.new(@log_path)
    logger.write('event', timestamp: true)
    line = File.read(@log_path).chomp
    # ISO-8601-ish prefix:  [2026-02-21T...]
    assert_match(/\A\[\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}/, line)
    assert_includes line, 'event'
  end

  def test_concurrent_threads_no_lost_writes
    logger = FileLogger.new(@log_path)
    threads = 20
    writes_per_thread = 50

    (1..threads).map do |t|
      Thread.new do
        writes_per_thread.times do |i|
          logger.write("t#{t}-#{i}")
        end
      end
    end.each(&:join)

    lines = File.readlines(@log_path)
    assert_equal threads * writes_per_thread, lines.size,
                 "expected #{threads * writes_per_thread} lines, got #{lines.size}"
  end

  def test_concurrent_threads_no_interleaved_lines
    logger = FileLogger.new(@log_path)
    long_msg = 'X' * 500

    (1..10).map do
      Thread.new { 20.times { logger.write(long_msg) } }
    end.each(&:join)

    File.readlines(@log_path).each_with_index do |line, idx|
      assert_equal long_msg, line.chomp,
                   "line #{idx} was corrupted / interleaved"
    end
  end

  def test_concurrent_processes_no_lost_writes
    processes = 5
    writes_per_process = 40

    pids = (1..processes).map do |p|
      fork do
        logger = FileLogger.new(@log_path)
        writes_per_process.times do |i|
          logger.write("p#{p}-#{i}")
        end
      end
    end

    pids.each { |pid| Process.waitpid(pid) }

    lines = File.readlines(@log_path)
    assert_equal processes * writes_per_process, lines.size,
                 "expected #{processes * writes_per_process} lines, got #{lines.size}"
  end

  def test_concurrent_processes_no_interleaved_lines
    long_msg = 'Y' * 500
    processes = 5

    pids = (1..processes).map do
      fork do
        logger = FileLogger.new(@log_path)
        20.times { logger.write(long_msg) }
      end
    end

    pids.each { |pid| Process.waitpid(pid) }

    File.readlines(@log_path).each_with_index do |line, idx|
      assert_equal long_msg, line.chomp,
                   "line #{idx} was corrupted / interleaved across processes"
    end
  end

  def test_mixed_threads_and_processes
    process_count = 3
    thread_count = 5
    writes = 20

    pids = (1..process_count).map do |p|
      fork do
        logger = FileLogger.new(@log_path)
        threads = (1..thread_count).map do |t|
          Thread.new do
            writes.times do |i|
              logger.write("p#{p}-t#{t}-#{i}")
            end
          end
        end
        threads.each(&:join)
      end
    end

    pids.each { |pid| Process.waitpid(pid) }

    expected = process_count * thread_count * writes
    lines = File.readlines(@log_path)
    assert_equal expected, lines.size,
                 "expected #{expected} lines, got #{lines.size}"
  end

  def test_creates_intermediate_directories
    nested = File.join(@dir, 'a', 'b', 'c', 'deep.log')
    logger = FileLogger.new(nested)
    logger.write('deep')
    assert_equal "deep\n", File.read(nested)
  end

  def test_flush_does_not_raise
    logger = FileLogger.new(@log_path)
    logger.write('data')
    assert_nil logger.flush
  end

  def test_path_accessor
    logger = FileLogger.new(@log_path)
    assert_equal @log_path, logger.path
  end
end
