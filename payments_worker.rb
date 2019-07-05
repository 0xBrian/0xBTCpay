require "json"
require "redis"
require "yaml"
require "./config"
require "./db"
require "./log"
require "./parity_rpc"

# requirements
# - it should immediately see new transfers pushed via stream.rb and process
#   the associated payments right away
# - from a cold startup with unpaid payments in the database, it should see and
#   process them all

# notes
# - if someone mines enough 0xbtc to the payment address, we will mark it as
#   paid, but there will be no transfer, so tx_hash etc. will be stored as nil

# todo
# - confirmations
# - stop checking old payments after a while, or do backoff
# - add uniqueness constraint to Payment.address in the db

class PaymentsWorker < Thread
  CONFIRMATIONS = 2 # TODO
  include Log

  def initialize(parity:, every: 10, threads: 10)
    @name = "PL"
    log "PaymentsWorker starting up."

    @parity = parity
    @work = Queue.new
    @doing = Set.new
    @checkers = launch_checker_threads(threads)
    @transfer_watcher = TransferWatcher.new(doing: @doing, work: @work)

    super do
      loop do
        begin
          poll
        rescue => e
          log e, e.backtrace
        end
        sleep every
      end
    end
  end

  def launch_checker_threads(count)
    count.times.collect do |i|
      Checker.new(doing: @doing, work: @work, id: i, parity: @parity)
    end
  end

  def unpaid_payments(exclude:[])
    Payment.where(paid_at: nil).exclude(id: exclude.to_a)
  end

  def poll
    unpaid = unpaid_payments(exclude: @doing).to_a
    log "polling for unpaid payments. total: #{unpaid_payments.count} / adding: #{unpaid.count} / excluded (already doing): #{@doing.length}"
    unpaid.shuffle.each do |p|
      @doing.add p.id
      @work.push p
    end
  end
end

module ParseLogs
  def parse_transfer_log(log)
    {
      block_number: log[:blockNumber],
      tx_hash: log[:transactionHash],
      from: topic_to_address(log[:topics][1]),
      to: topic_to_address(log[:topics][2]),
      tokens: BigDecimal(log[:data].to_i(16)) / 1e8
    }
  end

  def address_to_topic(address)
    "0x%064x" % address.to_i(16)
  end

  def topic_to_address(topic)
    "0x%040x" % topic.to_i(16)
  end
end

# watch redis `new_transfers` queue for 0xBitcoin Transfer() logs (pushed by
# stream.rb), find and push any matching Payments onto Checker work queue.
class TransferWatcher < Thread
  NEW_TRANSFERS = "new_transfers" # redis queue
  include ParseLogs
  include Log

  def initialize(doing:,work:)
    @name = "TW"
    @doing, @work = doing, work
    super do
      redis = Redis.new
      redis.subscribe(NEW_TRANSFERS) do |r|
        r.message do |q, json|
          process_transfer_log JSON.parse(json, symbolize_names: true)
        end
      end
    end
  end

  def process_transfer_log(log)
    tr = parse_transfer_log(log)
    log "saw new transfer #{tr.inspect}"
    payment = find_waiting_payment(to: tr[:to])
    if payment && !already_processing?(payment)
      log "transfer `to` address matches payment #{payment.id}."
      payment.update(seen_at: Time.now) unless payment.seen_at
      @doing.add payment.id
      @work.push payment
    else
      # 99.99% of the time, the Transfer() is just some random person sending
      # 0xBitcoin somewhere, not one we care about.
      log "transfer `to` address doesn't match any pending payments."
    end
  rescue => e
    log e, e.backtrace
  end

  def already_processing?(payment)
    @doing.include?(payment.id)
  end

  def find_waiting_payment(to:)
    Payment.where(paid_at: nil).where(address: to).exclude(id: @doing.to_a).first
  end
end

# monitor work queue, get payments to check, mark them paid if paid.
class Checker < Thread
  # "0x" + Digest::SHA3.hexdigest("Transfer(address,address,uint256)", 256)
  TRANSFER_TOPIC = "0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef"
  ADDR_0xBITCOIN = "0xb6ed7644c69416d67b522e20bc294a9a9b405b31"

  include ParseLogs
  include Log

  def initialize(doing:,work:,id:nil,parity:)
    @name = "CK"
    @doing, @work, @id, @parity = doing, work, id, parity
    super do
      loop do
        begin
          payment = @work.pop
          check payment
        rescue => e
          log e, e.backtrace
        ensure
          @doing.delete payment.id if payment
        end
      end
    end
  end

  def check(payment)
    retries_with_backoff(payment) do
      bal = balance(payment.address)
      log "  bal=#{bal}"
      payment.update(seen_at: payment.seen_at || Time.now) if bal > 0
      if bal >= payment.amount
        tr = fetch_tx_data(payment)
        payment.update(
          paid_at: Time.now,
          tx_hash: tr[:tx_hash],
          from_address: tr[:from],
          block_number: tr[:block_number],
          block_timestamp: tr[:block_timestamp]
        )
        log "  doing postback"
        begin
          body = {
            id: payment.id,
            data: payment.data,
            tx_hash: payment.tx_hash,
          }
          log "    url=#{payment.postback_url}"
          log "    body=#{body.inspect}"
          r = HTTParty.post(
            payment.postback_url,
            body: body.to_json,
            headers: {"Content-Type" => "application/json"},
            format: :plain
          )
        rescue => e
          log "ERROR trying to do postback", e, e.backtrace
        end
        log "  #{payment.id} is paid!"
        break
      end
    end
  end

  # depending on EVM RPC endpoint, balances might take a while to catch up to
  # new transfer activity that `streams.rb` has detected (erc20 Transer()
  # logs), especially with Infura where each RPC call might hit a different EVM
  def retries_with_backoff(payment)
    times = payment.seen_at ? 5 : 1
    times.times do |i|
      log "checking #{payment.id} (try #{i})"
      yield
      sleep 2**i
    end
  end

  def balance(address)
    BigDecimal(@parity.get_erc20_balance(ADDR_0xBITCOIN, address)) / 1e8
  end

  def fetch_tx_data(payment)
    filter = [TRANSFER_TOPIC, nil, address_to_topic(payment.address)]
    logs = @parity.get_logs(ADDR_0xBITCOIN, filter)
    bal = BigDecimal(0)
    # consider the first transfer that brought the balance high enough, to be
    # the one that paid the order, in case payer does multiple small transfers
    logs.each do |log|
      tr = parse_transfer_log(log)
      bal += tr[:tokens]
      if bal >= payment.amount
        bts = fetch_block_timestamp(tr[:block_number])
        return tr.merge(block_timestamp: bts)
      end
    end
    {}
  end

  def fetch_block_timestamp(block_number)
    @parity.get_block_by_number(block_number).dig(:timestamp)
  end
end

if $0 == __FILE__
  config = Config::load_file("config.yml")[:payments_worker]
  parity = ParityRPC.new(url: config[:provider])
  pw = PaymentsWorker.new(parity: parity, every: config[:every], threads: config[:threads])
  begin
    sleep
  rescue Interrupt
  end
end
