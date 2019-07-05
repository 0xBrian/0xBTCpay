require "haml"
require "sinatra"
require "sinatra/reloader"

class String
  def en0xify
    gsub("0xBTC", "<var>0</var>xBTC").gsub("0xBitcoin", "<var>0</var>xBitcoin")
  end
end

get "/" do
  haml(:"0xbtcpay.io/index", layout: :"0xbtcpay.io/layout")
end
