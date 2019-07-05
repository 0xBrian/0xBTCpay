Sequel.migration do
  up do
    create_table(:payments) do
      String :id, primary_key: true
      BigDecimal :amount, size: [16,8] # up to 99999999.99999999
      String :address, index: true, unique: true
      String :private_key
      Time :paid_at
      Time :seen_at
      String :tx_hash, index: true
      String :from_address
      Integer :block_number
      Time :block_timestamp

      # shop data
      String :data
      String :postback_url

      Time :created_at, index: true
      Time :updated_at
    end
  end
  down do
    drop_table :payments
  end
end
