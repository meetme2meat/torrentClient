require 'bitfield'
class Peer < EM::Connection
  extend Forwardable
  KEEP_ALIVE_INTERVAL    = 60
  HANDSHAKE_PAYLOAD_SIZE = 68
  PROTOCOL = 'BitTorrent protocol'.freeze
  KEEP_ALIVE_MESSAGE = "\x00\x00\x00\x00".freeze

  def Peer.connect(ip, port, client)
    EventMachine::connect ip, port , self, {client: client, port: port, ip: ip} rescue return
  end

  attr_reader :client, :ip , :port, :payload, :keep_alive
  attr_accessor :state
  def initialize(args)
    @ip                 =    args[:ip]
    @port               =    args[:port]
    @client             =    args[:client]
    @metainfo           =    client.metainfo
    @state              =    :unchoke
    @payload            =    String.new
    @have_handshake     =    false
    @disconnecting      =    false
    @interested         =    false
    subscribe!
  end
  def_delegators :@metainfo, :connected_peers , :connected? , :add , :remove, :info_hash, :pieces
  def_delegators :@client, :id, :request_channel, :response_channel, :scheduler_queue

  def subscribe!
    request_channel.subscribe do |data|
      if data[:peer] == self
        send_block(data) do
          show_interest!
        end
      end
    end
  end

  def post_init
    puts '-- post init'
    send_data(handshake)
  end

  def set_keep_alive=(value)
    @keep_alive = value
  end

  def disconnect!
    @disconnecting = true
    close_connection
  end

  # def send_block
  #   send_data(packed_string(p))
  # end
  def connection_completed
    ## start sending KEEP_ALIVE_MESSAGE
    puts "sending keep_alive sending ..."
    EM::PeriodicTimer.new(KEEP_ALIVE_INTERVAL) { send_data KEEP_ALIVE_MESSAGE }
  end

  def receive_data(data)
    @payload << data
    parse_data!
  end


  def send_block(payload)
    puts "sending block -- #{payload[:index]}"
    msg_len = "\x00\x00\x00\x0d"
    msg_id  = "\x06"
    index   = [payload[:index]].pack('N')
    offset  = [payload[:offset]].pack('N')
    length  = [payload[:length]].pack('N')
    yield if block_given?
    send_data(msg_len << msg_id << index << offset << length)
  end

  def parse_data!
    catch(:unwind) do
      return if disconnecting?
      parse_handshake unless have_handshake?
      delegate_message_to_handler
    end
  end

  def show_interest!
    send_interest unless @interested
    @interested = true
  end

  def send_interest
    send_data("\0\0\0\1\2")
  end

  def delegate_message_to_handler
    response_channel.push(self)
  end

  def disconnecting?
    !!@disconnecting
  end

  def parse_handshake
    data = payload.byteslice(0,HANDSHAKE_PAYLOAD_SIZE)
    throw(:unwind) unless data.size.eql?(HANDSHAKE_PAYLOAD_SIZE)
    payload.slice!(0,HANDSHAKE_PAYLOAD_SIZE)
    process_handshake(data)
  end

  def have_handshake?
    !!@have_handshake
  end

  def process_handshake(data)
    StringIO.open(data) do |io|
      len = io.getbyte
      protocol = io.read(len)
      reserved = io.read(8)
      obtained_infohash = io.read(20)
      obtained_peerid = io.read(20)
      validate_handshake(protocol, obtained_infohash, obtained_peerid)
      set_have_handshake!
    end
  end

  def set_have_handshake!
    @have_handshake = true
  end

  def validate_handshake(protocol, obtained_infohash, obtained_peerid)
    if not handshake_valid?(protocol, obtained_infohash, obtained_peerid)
      initiate_disconnect!
    end
    # ... throw
    add_peer_to_connected_pool
  end

  def handshake_valid?(protocol, obtained_infohash, obtained_peerid)
    [PROTOCOL, info_hash, obtained_peerid] == [protocol, obtained_infohash, obtained_peerid]
  end

  def initiate_disconnect!
    disconnect! and throw(:unwind)
  end

  def add_peer_to_connected_pool
    add(self)
  end

  def unbind
    teardown!
  end

  def teardown!
    uninterested!
    remove(self)
  end

  def reconnect!(port)
    # set as uninterested
    uninterested!
    @port = port
    ## ask event machine to reconnect
    reconnect @host, @port
  end

  def uninterested!
    @interested = false
  end

  def handshake
    "\x13BitTorrent protocol\x00\x00\x00\x00\x00\x00\x00\x00#{info_hash}#{id}"
  end

  def store_bitfield(data)
    @bitfield = BitField.new(data.unpack('B8' * data.length))
  end

  def set_bitfield(data)
    @bitfield.set_bit(data)
  end

  def have_block_num?(block)
    @bitfield.have_bit?(block)
  end

  def write_out(data)
    piece_num, block_num, data = dissect_payload!(data)
    piece = find_piece(piece_num)
    return unless piece
    return if piece.written
    piece.blocks << initialize_block_info(piece_num, block_num, data)
    process(piece) if piece.complete?
  end

  def process(piece)
    piece.invalid_checksum? ? enqueue(piece) : piece.write_out
  end

  def enqueue(piece)
    # if the piece is invalid we reschedule it back
    while(!piece.blocks.empty?)
      blockInfo = piece.blocks.pop
      scheduler_queue.push build_block(blockInfo)
    end
  end

  def build_block(blockInfo)
    {
      index:  blockInfo[:index],
      offset: blockInfo[:offset],
      length: blockInfo[:length]
    }
  end

  def initialize_block_info(index, offset, data)
    {
      index:  index,
      offset: offset,
      data:   data,
      length: data.size,
    }
  end

  def find_piece(piece_num)
    pieces.find { |piece| piece.piece_num == piece_num }
  end

  def dissect_payload!(payload)
    length = payload.size
    piece_num = payload.slice!(0,4).unpack('N').first
    block_num = payload.slice!(0,4).unpack('N').first
    data = payload.slice!(0, length-8)
    [ piece_num, block_num, data ]
  end

  def has_more_payload?
    not payload.empty?
  end
end