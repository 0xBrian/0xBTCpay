require "sequel"
require "securerandom"
Sequel::Model.plugin :timestamps, update_on_create: true
class Payment < Sequel::Model
  RE_ETH_ADDRESS = %r(^0x\h{40}$)
  unrestrict_primary_key
  def self.generate_id
    SecureRandom.hex(8)
  end
  def before_create
    raise "bad address format" unless values[:address].match(RE_ETH_ADDRESS)
    raise "address must be lowercase" unless values[:address].downcase == values[:address]
    super
  end
end
