#!/usr/bin/env ruby

require "sinatra"
require "sinatra/streaming"
require "json"
require_relative "furnace"

class FurnaceViewer < Sinatra::Base
 using Rainbow
 helpers Sinatra::Streaming

  set :furnace, Furnace.new

  set :public_folder, File.dirname(__FILE__) + '/static'
  set :views, File.dirname(__FILE__) + '/views'

  # Custom SSE Event Logger
  class SSELogger < Furnace::EventLogger
    def initialize(stream)
      super(mode: :events, output: StringIO.new)
      @stream = stream
    end

    def log_event(type, data = {})
      timestamp = Time.now
      event = {
        type: type,
        timestamp: timestamp.iso8601,
        elapsed: ((timestamp - @start_time) * 1000).round(2),
        **data
      }

      @events << event

      # Stream to SSE
      @stream.puts "data: #{event.to_json}\n\n"
      @stream.flush if @stream.respond_to?(:flush)
    end
  end

  get "/" do
    erb :index
  end

  get "/random" do
    cards = settings.furnace.random_cards(2)
    stream_combat cards, furnace: settings.furnace
  end

  get "/fight/:card1/:card2" do
    card1 = params[:card1]
    card2 = params[:card2]

    cards = settings.furance.find_cards_by_name(card1, card2)
    stream_combat cards, furnace: settings.furnace
  end

  def stream_combat(cards, furnace:)
    content_type "text/event-stream"
    headers "Cache-Control" => "no-cache",
            "Access-Control-Allow-Origin" => "*"

    stream(:keep_open) do |out|
      begin
        spatial = true

        # Create SSE logger
        logger = SSELogger.new(out)

        # Run combat
        combat = Furnace::Combat.new(cards, spatial:, logger:)
        combat.run_combat

        out.puts "data: {\"type\":\"stream_end\"}\n\n"
      rescue => e
        out.puts "data: {\"type\":\"error\",\"message\":\"#{e.message}\"}\n\n"
      ensure
        out.close
      end
    end
  end

  run! if app_file == $0
end
