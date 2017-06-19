
state :initial do
  in_action {
    #require_relative '/home/ta_kondoh/work/simulator/signal/lora'

    @unconfirmed_data_up.macpayload.fhdr.fctrl.adr = true
    @fcnt = 0

    transit :send_payload
  }
end


state :join do
  in_action {
    @join_request.macpayload.devnonce = [Random.rand(65535)].pack('n')
    send @join_request.encode(appkey: @appkey)
    start_timer :wait_join_accept, 10
  }

  expire( :wait_join_accept ) {
    transit :join
  }

  receive(->{ @sig.mhdr.join_accept? }) {
    @nwkskey, @appskey = KeyGenerator.new(@join_request, @sig, @appkey).get_keys
    @decode_params = [{appkey: @appkey, nwkskey: @nwkskey, appskey: @appskey}]

    @unconfirmed_data_up.macpayload.fhdr.devaddr = @sig.macpayload.devaddr
    
    transit :send_payload
  }
end


state :send_payload do
  in_action {
    start_timer :send_uplink, 5
  }

  expire( :send_uplink ) {
    @unconfirmed_data_up.macpayload.fhdr.fcnt = (@fcnt += 1)

    send @unconfirmed_data_up.encode(*@decode_params)

    start_timer :send_uplink, 5
  }

  receive(->{ @sig.mhdr.unconfirmed_data_down? }) {
    if @sig.macpayload.fhdr.fctrl.foptslen > 0
      if @sig.macpayload.fhdr.fopts.cid. == MACCommand::LinkADR
        @logger.info "received ADR Req"
        send @unconfirmed_data_up_link_adr_ans.encode(*@decode_params)
      end
    else
      # do nothing
    end
  }
  
  receive(->{ @sig.mhdr.confirmed_data_down? }) {
    #@uplink_payload_empty.macpayload.fcnt = (@fcnt += 1)
    #@uplink_payload_empty.mhdr.mtype = MHDR::ConfirmedDataUp

    #send @uplink_payload_empty.encode(*@decode_params)
  }

  receive(->{ true }) {
    @logger.info @sig
  }
end



#===================================================
define do

@appkey = ["01010101010101010101010101010101"].pack('H*')
@nwkskey = ["30C8294FFA0B1DBBBD9FC329872EFDD8"].pack('H*')
@appskey = ["19DA2FDABBFD96D86D54903353BEDCF2"].pack('H*')

@decode_params = [{appkey: @appkey, nwkskey: @nwkskey, appskey: @appskey}]

appeui = ['0102030405060708'].pack('H*')
deveui = ['1112131415161718'].pack('H*')

nwkid   = 0b0010011
nwkaddr = 0b0_00000100_00010000_0110_1011

@join_request = 
  PHYPayload.new(
    mhdr: MHDR.new(
      mtype: MHDR::JoinRequest
    ),
    macpayload: JoinRequestPayload.new(
      appeui: appeui,
      deveui: deveui,
      devnonce: "\x21\x22"
    ),
    mic: '',
  )

@unconfirmed_data_up = 
  PHYPayload.new(
    mhdr: MHDR.new(
      mtype: MHDR::UnconfirmedDataUp
    ),
    macpayload: MACPayload.new(
      fhdr: FHDR.new(
        devaddr: DevAddr.new(
          nwkid:   nwkid,
          nwkaddr: nwkaddr
        ),
        fctrl: FCtrl.new(
          adr: false,
          adrackreq: false,
          ack: false
        ),
        fcnt: 0,
        fopts: nil
      ),
      fport: 1,
      frmpayload: FRMPayload.new("\x00\x00\x00\x14")
    ),
  )

@unconfirmed_data_up_link_adr_ans = 
  PHYPayload.new(
    mhdr: MHDR.new(
      mtype: MHDR::UnconfirmedDataUp
    ),
    macpayload: MACPayload.new(
      fhdr: FHDR.new(
        devaddr: DevAddr.new(
          nwkid:   nwkid,
          nwkaddr: nwkaddr
        ),
        fctrl: FCtrl.new(
          adr: true,
          adrackreq: false,
          ack: false,
          foptslen: 1
        ),
        fcnt: 0,
        fopts: MACCommand.new(
          cid: MACCommand::LinkADR,
          payload: LinkADRAns.new(
            powerack: true,
            datarateack: true,
            channelmaskack: true
          ),
        ),
      ),
      fport: 0,
      frmpayload: nil
    ),
  )

end


