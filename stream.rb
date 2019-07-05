require "faye/websocket"
require "json"
require "redis"
require "./config"
require "./log"

ADDR_0xBITCOIN = "0xb6ed7644c69416d67b522e20bc294a9a9b405b31"
TRANSFER_TOPIC = "0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef"
NEW_TRANSFERS = "new_transfers" # redis queue

class Stream
  include Log
  def initialize(url:)
    @name = "ST" # for logging
    @url = url
    @redis = Redis.new
  end

  def start
    @ws = Faye::WebSocket::Client.new(@url)
    @subs = Hash.new
    @waiting_subs = Hash.new

    @ws.on :open do
      log "connected."
      do_pings
      subscribe
    end

    @ws.on :message do |event|
      process event.data
    end

    @ws.on :close do |event|
      log "connection closed. #{event.code} #{event.reason}"
      reconnect
    end
  end

  def subscribe
    log "subscribing."
    @ws.send rpc(
      "eth_subscribe",
      ["logs", {address: ADDR_0xBITCOIN, topics: [TRANSFER_TOPIC]}],
      id: create_subscription(:_0xbitcoin_transfers)
    )
  end

  def reconnect
    EM.add_timer(1) { start }
  end

  def create_subscription(name)
    new_id.tap { |id| @waiting_subs[id] = name }
  end

  def do_pings
    EM.cancel_timer @timer if @timer
    @timer = EM.add_periodic_timer(10) { @ws.send(rpc("eth_blockNumber", [])) }
  end

  def process(response_json)
    r = JSON.parse(response_json, symbolize_names: true)
    return on_confirm_sub(r) if waiting?(r[:id])
    if r[:method] == "eth_subscription"
      sub_id, result = parse(r)
      return unless sub_id == :_0xbitcoin_transfers
      return unless result[:topics].first == TRANSFER_TOPIC # paranoia
      return unless result[:address].casecmp?(ADDR_0xBITCOIN) # paranoia
      log "[#{sub_id.inspect}] " + result.inspect
      @redis.publish NEW_TRANSFERS, result.to_json
    end
  end

  def on_confirm_sub(r)
    if parity_sub_id = r[:result]
      sub_id = @waiting_subs[r[:id]]
      @subs[parity_sub_id] = sub_id
      @waiting_subs.delete r[:id]
      log "subscribed #{sub_id.inspect} (#{parity_sub_id})"
      log "all subscriptions confirmed" if @waiting_subs.empty?
    else
      raise "subscription failure: " + r.inspect
    end
  end

  def waiting?(id)
    @waiting_subs.include?(id)
  end

  def parse(r)
    [@subs[r[:params][:subscription]], result = r[:params][:result]]
  end

  def new_id
    @id_ = (@id_ || 0) + 1
  end

  def rpc(method, params, id: new_id)
    {method: method, params: params, id: id, jsonrpc: 2.0}.to_json
  end
end

begin
  config = Config::load_file("config.yml")[:stream]
  s = Stream.new(url: config[:provider])
  EM.run { s.start }
rescue Interrupt
  puts "quit."
end
