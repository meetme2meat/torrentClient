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
    when :choke
      puts '---choke'
      peer.state = :choke
    when :unchoke
      puts '---unchoke'
      peer.state = :unchoke
    when :bitfield
      puts '---unchoke'
      peer.store_bitfield(payload)
    when :have
      puts '---have'
      peer.set_bitfield(payload)
    when :piece
      puts '-- piece'
      peer.write_out(payload)
      ## act upon piece
    when :port
      puts '-- change port'
      port = payload.unpack('N')
      peer.reconnect(port)
    end
  end
end
