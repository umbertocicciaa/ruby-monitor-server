#!/usr/bin/env ruby
require 'socket'
require_relative 'monitor_server'

DEFAULT_PORT = 9090
DEFAULT_LOG  = 'metrics.log'

port     = Integer(ENV.fetch('PORT', DEFAULT_PORT))
log_path = ENV.fetch('LOG_PATH', DEFAULT_LOG)

tcp = TCPServer.new('0.0.0.0', port)

puts "Monitor server listening on ws://0.0.0.0:#{port}"
puts "Logging metrics to #{File.expand_path(log_path)}"

MonitorServer.new(tcp, log_path: log_path).start
