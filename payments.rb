require "bigdecimal"
require "eth"
require "haml"
require "redis"
require "securerandom"
require "sinatra"
require "sinatra/reloader"
require "uri"
require "./config"
require "./db"
require "./log"

disable :dump_errors, :raise_errors

$redis = Redis.new
$config = Config::load_file("config.yml")[:payments]

set(:port, $config[:port] || 8888)

ZXB_TOTAL_SUPPLY = 20_999_984
def amount_is_valid?(amount)
  return false unless amount =~ /^[0-9]{1,8}(?:\.[0-9]{1,8})?$/
  n = BigDecimal(amount)
  n > 0 && n <= ZXB_TOTAL_SUPPLY
end
def postback_url_is_valid?(url)
  url =~ /\A#{URI::regexp}\z/
end

def generate_timestamp
  Time.now.strftime("%Y-%m-%d %H:%M:%S")
end
CHANNEL_NAME = "new_payments"
def publish(payment_id)
  $redis.publish(CHANNEL_NAME, payment_id)
  puts "#{generate_timestamp} #{payment_id}"
end

RPC_PARSE_ERROR      = -32700
RPC_INVALID_REQUEST  = -32600
RPC_METHOD_NOT_FOUND = -32601
RPC_INVALID_PARAMS   = -32602
MESSAGES = {
  RPC_PARSE_ERROR => "Parse error",
  RPC_INVALID_REQUEST => "Invalid request",
  RPC_METHOD_NOT_FOUND => "Method not found",
  RPC_INVALID_PARAMS => "Invalid params"
}

def halt_json(code, extra=nil, id=nil)
  message = MESSAGES[code]
  message += ": #{extra}" if extra
  halt 200, {jsonrpc: "2.0", id: id, error: {code: code, message: message}}.to_json
end

before do
  headers({
    "Access-Control-Allow-Origin" => "*",
    "Access-Control-Allow-Methods" => ["GET", "POST"]
  })
end

post "/" do
  unless $config[:ip_whitelist].include?(request.ip) || IPAddr.new(request.ip).loopback?
    halt 403
  end
  content_type :json
  begin
    rpc = JSON.parse(request.body.read, symbolize_names: true)
    unless rpc[:id] && rpc[:method] && rpc[:params] && rpc[:jsonrpc] == "2.0"
      halt_json RPC_INVALID_REQUEST
    end
  rescue
    halt_json RPC_PARSE_ERROR
  end
  halt_json RPC_METHOD_NOT_FOUND unless rpc[:method] == "start_payment"
  amount       = rpc[:params][:amount]
  postback_url = rpc[:params][:postback_url]
  data         = rpc[:params][:data].to_json
  halt_json RPC_INVALID_PARAMS, "missing amount" unless amount
  halt_json RPC_INVALID_PARAMS, "invalid amount" unless amount_is_valid?(amount)
  amount = BigDecimal(amount)
  halt_json RPC_INVALID_PARAMS, "invalid postback URL" if postback_url && !postback_url_is_valid?(postback_url)
  key = Eth::Key.new
  payment_id = Payment.generate_id
  payment = Payment.new(
    id: payment_id,
    amount: amount,
    address: key.address.downcase,
    private_key: key.private_hex,
    data: data,
    postback_url: postback_url
  )
  payment.save
  publish(payment_id)
  result = {id: payment.id, amount: payment.amount.to_s("F"), address: payment.address}
  halt 200, {jsonrpc: "2.0", result: result, id: rpc[:id]}.to_json
end

get %r(/(\h{16})/status.json) do
  content_type :json
  id = params["captures"].first
  payment = Payment[id]
  not_found unless payment
  {
    address: payment.address,
    amount: payment.amount.to_s("F"),
    seen_at: payment.seen_at&.to_i,
    paid_at: payment.paid_at&.to_i,
    tx_hash: payment.tx_hash
  }.to_json
end

get "/test/error" do
  1/0
end

error do
  "error"
end

not_found do
  "not found"
end
