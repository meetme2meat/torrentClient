class Message
  attr_reader :status, :payload, :peer
  def initialize(status, payload, peer)
    @status   = status
    @peer     = peer
    @payload  = payload
  end

  ## this is pretty lame make it better
  def parse!
    case @status
    when :choke # 0
      puts '---choke'
      peer.received_choke_message
    when :unchoke # 1
      puts '---unchoke'
      peer.received_unchoke_message
    when :interested # 2
      puts '-- interested'
      peer.received_interested_message
    when :not_interested # 3
      puts '-- not interested'
      peer.received_not_interested_message
    when :have # 4
      puts '---have'
      index = payload.unpack('N').first
      peer.set_bitfield(index)
    when :bitfield # 5
      puts '---bitfield 5'
      peer.store_bitfield(payload)
    when :request # 6
      puts '-- request REQUEST ....'
      peer.read_in(payload)
    when :piece # 7
      puts '-- piece'
      peer.write_out(payload)
      ## act upon piece
    when :cancel # 8
      puts '-- cancel'
      peer.cancel_request(payload)
    when :port # 9
      puts '-- change port'
      port = payload.unpack('N')
      peer.reconnect(port)
    end
  end
end
