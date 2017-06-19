state :initial do
  in_action {
    @t_stat = 20
    @t_pull = 30

    @n_uplink = 0
    @n_downlink = 0

    transit :main
  }
end


state :main do
  in_action {
    start_timer :stat, @t_stat
    start_timer :pull, @t_pull
  }

  expire( :stat ) {
    @stat.head.random_token = Random.rand(0xffff)
    @stat.payload['stat']['time'] = Time.now.strftime("%F %T %Z")
    @stat.payload['stat']['rxnb'] = @n_uplink
    @stat.payload['stat']['rxok'] = @n_uplink
    @stat.payload['stat']['rxfw'] = @n_uplink
    @stat.payload['stat']['dwnb'] = @n_downlink

    send @stat.encode

    start_timer :stat, @t_stat
  }


  # push
  receive(->{true}, :lorasim) {
    @push_data.head.random_token = Random.rand(0xffff)
    @push_data.payload['rxpk'][0]['time'] = Time.now.strftime("%FT%T.%L000Z")
    @push_data.payload['rxpk'][0]['tmst'] = Time.now.to_i
    @push_data.payload['rxpk'][0]['data'] = @sig.value.encode64
    @push_data.payload['rxpk'][0]['size'] = @sig.value.length

    send @push_data.encode

    @n_uplink += 1
  }

  receive(->{ @sig.head.push_ack? }) {
  }


  # pull
  expire( :pull ) {
    @pull_data.head.random_token = Random.rand(0xffff)

    send @pull_data.encode

    start_timer :pull, @t_pull
  }

  receive(->{ @sig.head.pull_ack? }) {
    @logger.info "receive pull ack."
  }

  receive(->{ @sig.head.pull_resp? }) {
    @n_downlink += 1

    @tx_ack.head.random_token = @sig.head.random_token

    send @tx_ack.encode

    data = @sig.payload['txpk']['data'].decode64
    send :lorasim, data
  }
end


#===========================================
define do
  gw_eui = ['DEADBEAFDEADBEBF'].pack('H*')

  @stat = PacketForwarder.new(
    head: PacketForwarder::Head.new(
      protocol_version: 1,
      identifier: PacketForwarder::Head::PushData,
    ),
    guid: gw_eui,
    payload: {
      'stat' => {
        'time' => nil,    # Time.now.strftime("%F %T %Z")
        'lati' => 35.2442,
        'long' => 139.6794,
        'alti' => 0,
        'rxnb' => nil,    # rxnb
        'rxok' => nil,    # rxok
        'rxfw' => nil,    # rxfw
        'ackr' => 100.0,
        'dwnb' => nil,    # rxnb
        'txnb' => 0,
      }
    }
  )


  @push_data = PacketForwarder.new(
    head: PacketForwarder::Head.new(
      protocol_version: 1,
      identifier: PacketForwarder::Head::PushData,
    ),
    guid: gw_eui,
    payload: {
      'rxpk' => [
        {
          'time' => nil,   # Time.now.strftime("%FT%T.%L000Z"),
          'tmst' => nil,   # Time.now.to_i,
          'freq' => 923.2,
          'chan' => 2,
          'rfch' => 0,
          'stat' => 1,
          'modu' => "LORA",
          'datr' => "SF7BW125",
          'codr' => "4/5",
          'rssi' => -40,
          'lsnr' => 2.0,
          'size' => nil,  # data.length,
          'data' => nil,  # Base64.encode64(data)
        }
      ]
    }
  )

  @pull_data = PacketForwarder.new(
    head: PacketForwarder::Head.new(
      protocol_version: 1,
      identifier: PacketForwarder::Head::PullData,
    ),
    guid: gw_eui,
    payload: nil
  )

  @tx_ack = PacketForwarder.new(
    head: PacketForwarder::Head.new(
      protocol_version: 1,
      identifier: PacketForwarder::Head::TxAck,
    ),
    guid: gw_eui,
    payload: nil
  )

end


