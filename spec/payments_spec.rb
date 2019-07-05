require File.expand_path "../spec_helper.rb", __FILE__

describe "payments" do
  def post_json(data)
    post "/", data.to_json, format: :json
  end
  def rpc(method:"start_payment", params:{})
    {method: method, params: params, id:99, jsonrpc:"2.0"}
  end
  def valid_rpc
    rpc(params: {amount: "5.55", postback_url: "https://...", data: {order_id: rand(2**32)}})
  end

  it "should require valid json" do
    post_json "{zzz}"
    expect(last_response.body).to match("Parse error")
  end

  it "should require valid jsonrpc" do
    post_json({})
    expect(last_response.body).to match("Invalid request")
  end

  it "should require valid method" do
    post_json rpc(method: "do_stuff")
    expect(last_response.body).to match("Method not found")
  end

  it "should require amount" do
    post_json valid_rpc.
      tap { |rpc| rpc[:params].delete :amount}
    expect(last_response.body).to match("missing amount")
  end

  it "should require valid amount" do
    post_json valid_rpc.
      tap { |rpc| rpc[:params][:amount] = "x" }
    expect(last_response.body).to match("invalid amount")
  end

  it "should require valid postback url if one provided" do
    post_json valid_rpc.
      tap { |rpc| rpc[:params][:postback_url] = "z" }
    expect(last_response.body).to match("invalid postback URL")
  end

  it "should create a payment" do
    post "/", {
      method: "start_payment",
      params: {
        amount: "5.55",
        postback_url: "https://...",
        data: {order_id: rand(2**32)}
      },
      id:99,
      jsonrpc:"2.0"
    }.to_json, format: :json
    j = JSON.parse(last_response.body, symbolize_names: true)
    expect(last_response).to be_ok
    expect(j[:id]).to eq(99)
    expect(Payment.where(id: j[:result]).count).to eq(1)
  end

  it "should return generic not-found page" do
    get "/nonesuch"
    expect(last_response.body).to match("not found")
  end

  it "should return generic error page" do
    get "/test/error"
    expect(last_response.body).to match("error")
  end
end
