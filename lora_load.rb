
state :initial do
  in_action {
    transit :join
  }
end


state :join do
  in_action {
    @n_joined ||= 0

    @join_request.macpayload.deveui = @unjoined_devices[@n_joined][:deveui]
    @join_request.macpayload.devnonce = [Random.rand(65535)].pack('n')

    @logger.info "send!!!!"
    send @join_request.encode(appkey: @appkey)
    start_timer :wait_join_accept, 2
  }

  expire( :wait_join_accept ) {
    @logger.info 'any request timeout!!!'
  }

  receive(->{ @sig.mhdr.join_accept? }) {
    stop_timer :wait_join_accept

    nwkskey, appskey = KeyGenerator.new(@join_request, @sig, @appkey).get_keys
    decode_params = [{appkey: @appkey, nwkskey: nwkskey, appskey: appskey}]

    @devices[@sig.macpayload.devaddr] = {
      decode_params: decode_params,
      fcnt: 0
    }
    @logger.info "#{@devices[@sig.macpayload.devaddr][:decode_params].inspect}"

    @n_joined += 1
    if @n_joined == @n_devices
      @logger.info "all devices joined"
      transit :send_payload
    else
      transit :join
    end
  }
end


state :send_payload do
  in_action {
    @devices.each do |devaddr, params|
      @unconfirmed_data_up.macpayload.fhdr.devaddr = devaddr
      @unconfirmed_data_up.macpayload.fhdr.fcnt = params[:fcnt]

      send @unconfirmed_data_up.encode(* params[:decode_params])

      params[:fcnt] += 1
    end

    start_timer :cyclic_data_send, 0.01
  }

  expire( :cyclic_data_send ) {
    transit :send_payload
  }

  receive(->{ true }) {
    @logger.info @sig
  }
end



#===================================================
define do

@n_devices = 4

@unjoined_devices = []
@deveui = ['1112131415161718'].pack('H*')
appeui = ['0102030405060708'].pack('H*')
deveui = ['0000000000000000'].pack('H*')

@n_devices.times do |i|
  @unjoined_devices[i] = {}
  @unjoined_devices[i][:deveui] = deveui.dup
  @unjoined_devices[i][:appeui] = appeui.dup
  deveui = deveui.succ
end

@devices = {}


@appkey = ["01010101010101010101010101010101"].pack('H*')
@nwkskey = ["30C8294FFA0B1DBBBD9FC329872EFDD8"].pack('H*')
@appskey = ["19DA2FDABBFD96D86D54903353BEDCF2"].pack('H*')

@decode_params = [{appkey: @appkey, nwkskey: @nwkskey, appskey: @appskey}]


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


