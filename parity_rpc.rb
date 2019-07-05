require "httparty"
require "json"

class ParityRPCError < StandardError
end

class ParityRPC
  def initialize(opts)
    @id = 0
    @url = opts[:url]
  end

  def next_id
    @id += 1
  end

  def call(method, *params)
    rpc_call = {method: method, params: params, id: next_id, jsonrpc: "2.0"}
    body = rpc_call.to_json
    headers = {"Content-Type" => "application/json"}
    r = HTTParty.post(@url, body: body, headers: headers, format: :plain)
    j = JSON.parse(r, symbolize_names: true)
    raise ParityRPCError.new(j[:error][:message]) if j[:error]
    j[:result]
  end

  def get_block_number
    call("eth_blockNumber").to_i(16)
  end

  def get_block_by_hash(block_hash)
    decode(call("eth_getBlockByHash", block_hash, true))
  end

  def get_block_by_number(block_number)
    decode(call("eth_getBlockByNumber", "0x%x" % block_number, true))
  end

  def get_transaction_receipt(tx_hash)
    decode(call("eth_getTransactionReceipt", tx_hash))
  end

  def encode_num(b)
    return "0x%x" % b if b.is_a?(Integer)
    b
  end

  def get_erc20_balance(contract, address, at="latest")
    addr = "%040x" % address.to_i(16)
    call("eth_call", {to: contract, data: "0x70a08231000000000000000000000000#{addr}"}, encode_num(at)).to_i(16)
  end

  def get_logs(from_block="earliest", to_block="latest", address, topics)
    decode_array(call("eth_getLogs", fromBlock: encode_num(from_block), toBlock: encode_num(to_block), address: address, topics: topics))
  end

  DECODE_HEX = Set[:nonce, :transactionIndex, :gas, :blockNumber, :cumulativeGasUsed, :gasUsed, :logIndex, :number]
  DECODE_ETH = Set[:gasPrice, :value]
  DECODE_TOL = Set[:from, :to] # downcase paranoia
  def decode(data)
    data.each do |k, v|
      if v.is_a?(String)
        data[k] = v.to_i(16) if DECODE_HEX.include?(k)
        data[k] = BigDecimal(v.to_i(16))/1e18 if DECODE_ETH.include?(k)
        data[k] &&= v.downcase if DECODE_TOL.include?(k)
        data[k] = data[k] == "0x1" if k == :status
        data[k] = Time.at(v.to_i(16)).utc if k == :timestamp
      end
      if k == :transactions
        data[k] = data[k].collect { |t| decode(t) }
      end
    end
  end

  def decode_array(ary)
    ary.collect { |a| decode(a) }
  end
end
