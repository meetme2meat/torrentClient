require 'message'
class MessageHandler
  MESSAGE_STATE = {
    0 => :choke,
    1 => :unchoke,
    2 => :interested,
    3 => :not_interested,
    4 => :have,
    5 => :bitfield,
    6 => :request,
    7 => :piece,
    8 => :cancel,
    9 => :port
  }.freeze

  attr_reader :response_channel
  def initialize(channel)
    @response_channel = channel
  end

  def start!
    response_channel.subscribe { |peer| parse_message(peer) }
  end

  def parse_message(peer)
    while peer.has_more_payload?
      len_prefix = peer.payload.byteslice(0, 4)
      # break
      break unless len_prefix.size.eql?(4)

      len = len_prefix.unpack('N').first

      if len.zero?
        ## Keep alive request
        peer.set_keep_alive = true
        peer.payload.slice!(0, 4)
        break
      end

      msg_id = peer.payload.slice(4, 1).bytes.first

      break unless msg_id

      break unless (1..9).cover?(msg_id)

      payload = if (0..3).cover?(msg_id)
                  peer.payload.slice!(0, 5)
                  nil
                else
                  payload = peer.payload.byteslice(5, len - 1)
                  break unless payload.size == (len - 1)
                  peer.payload.slice!(0, len + 4)
                  payload
      end
      Message.new(get_status(msg_id), payload, peer).parse!
    end
  end

  def get_status(message_id)
    MESSAGE_STATE[message_id]
  end
end
