require 'fileutils'
require 'time'


class FileLogger
  attr_reader :path

  def initialize(path)
    @path = File.expand_path(path)
    @mutex = Mutex.new          # guards threads inside one process
    FileUtils.mkdir_p(File.dirname(@path))
  end

  def write(message, timestamp: false)
    line = build_line(message, timestamp)

    @mutex.synchronize do
      File.open(@path, 'a') do |f|
        f.flock(File::LOCK_EX)
        f.write(line)
        f.flush
      end
    end
  end

  # Explicitly flush the OS buffer (no-op for safety but kept for API symmetry).
  def flush
    nil
  end

  private

  def build_line(message, timestamp)
    msg = message.to_s
    msg = "[#{Time.now.iso8601}] #{msg}" if timestamp
    msg.end_with?("\n") ? msg : "#{msg}\n"
  end
end
