#!/usr/bin/env ruby

require_relative "furnace_viewer"

puts "🔥 Starting Furnace Combat Viewer...".color(:green)
puts "🌐 Navigate to: http://localhost:4567".color(:cyan)
puts "⚡ Press Ctrl+C to stop".color(:yellow)

FurnaceViewer.run!