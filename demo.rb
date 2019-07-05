require "haml"
require "httparty"
require "sinatra"

set(:port, 8000)

get "/" do
  @shirts = rand(3) + 1
  @price = 0.001
  @total = @price * @shirts
  haml :demo
end

post "/" do
  headers = {"Content-Type" => "application/json"}
  body = {
    method: "start_payment",
    params: {
      amount: params["total"],
      data: {order_id: rand(2**16)}
    },
    id:1,
    jsonrpc:"2.0"
  }.to_json
  r = HTTParty.post("http://localhost:8888", body: body, headers: headers)
  if id = r.parsed_response["result"]["id"]
    redirect "/#{id}"
  else
    halt 500
  end
end

get %r(/(\h{16})) do
  @id = params["captures"].first
  haml :payment
end
