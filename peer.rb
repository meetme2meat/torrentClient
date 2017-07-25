require 'bitfield'

class Peer < EM::Connection
  extend Forwardable
  KEEP_ALIVE_INTERVAL    = 60
  HANDSHAKE_PAYLOAD_SIZE = 68
  PROTOCOL = 'BitTorrent protocol'.freeze
  KEEP_ALIVE_MESSAGE = "\x00\x00\x00\x00".freeze

  def self.connect(ip, port, client)
    EventMachine.connect ip, port, self, client: client, port: port, ip: ip
  rescue
    return
  end

  attr_reader :client, :ip, :port, :payload, :keep_alive, :bitfield, :handshaked
  attr_accessor :state
  def initialize(args)
    @ip                 =    args[:ip]
    @port               =    args[:port]
    @client             =    args[:client]
    @metainfo           =    client.metainfo
    @state              =    { am_choking: true, am_interested: false, peer_choking: true, peer_interested: false }
    @payload            =    ''
    @handshaked         =    false
    @disconnecting      =    false
    @interested         =    false
    @status             =    { downloading: true, uploading: true }
    @bitfield           =    BitField.new(Array.new(bitfield_length, 0))
  end
  def_delegators :@metainfo, :connected_peers, :connected?, :add, :remove, :info_hash, :pieces, :bitfield_length
  def_delegators :@client, :id, :request_channel, :response_channel, :scheduler_queue, :broadcast_channel

  alias handshaked? handshaked

  def post_init
    p '------- post init'
    send_data(handshake)
  end

  def disconnect!
    @disconnecting = true
    close_connection
  end

  def connection_completed
    puts '------- sending keepalive message'
    EM::PeriodicTimer.new(KEEP_ALIVE_INTERVAL) { send_data KEEP_ALIVE_MESSAGE }
  end

  def receive_data(data)
    @payload << data
    parse
  end

  def send_block(payload)
    msg_len = "\x00\x00\x00\x0d"
    msg_id  = "\x06"
    index   = [payload[:index]].pack('N')
    offset  = [payload[:offset]].pack('N')
    length  = [payload[:length]].pack('N')
    send_data(msg_len << msg_id << index << offset << length)
  end
  alias push send_block
  # alias just to avoid the stupid if/else conditions (probably redo this and remove alias)

  def parse
    catch(:unwind) do
      ## disconnecting is just a handler to notify that peer has failed and will not process any message
      ## and about to disconnect
      return if disconnecting?
      process_handshake unless handshaked?
      push_to_channel
    end
  end

  def send_interest
    send_data("\0\0\0\1\2")
  end

  def send_unchoke
    p '--- unchoking remote peer'
    send_data("\0\0\0\1\1")
    am_unchoking!
  end

  def received_unchoke_message
    @state[:peer_choking] = false
    puts "#{self} == #{state}"
  end

  def received_interested_message
    @state[:peer_interested] = true
  end

  def received_not_interested_message
    @state[:peer_interested] = false
  end

  def received_choke_message
    @state[:peer_choking] = true
  end

  def am_choking!
    @state[:am_choking] = true
  end

  def am_unchoking!
    @state[:am_choking] = false
  end

  def am_interested!
    @state[:am_interested] = true
    send_interest
  end

  def am_not_interested!
    puts "Sending I'm not interested ..."
    @state[:am_interested] = false
    # send_disinterest
  end

  def send_disinterest
    send_data("\0\0\0\1\3")
  end

  def push_to_channel
    response_channel.push(self)
  end

  def peer_unchoking?
    !@state[:peer_choking]
  end

  def peer_interested?
    @state[:peer_interested]
  end

  def choking?
    @state[:am_choking]
  end

  def unchoking?
    !choking?
  end

  def interested?
    @state[:am_interested]
  end

  def disconnecting?
    !!@disconnecting
  end

  def process_handshake
    data = payload.byteslice(0, HANDSHAKE_PAYLOAD_SIZE)
    throw(:unwind) unless data.size.eql?(HANDSHAKE_PAYLOAD_SIZE)
    payload.slice!(0, HANDSHAKE_PAYLOAD_SIZE)
    parse_handshake(data)
    puts "Adding peer #{self}"
    add(self) if handshaked?
    puts "Added peer #{self}"
    send_unchoke if choking?
    puts "am I a leecher #{leecher?} ====="
    am_interested! if leecher?
    puts "#{self} === #{state}"
  end

  def leecher?
    !client.seeder?
  end

  def seeder?
    client.seeder?
  end

  def parse_handshake(data)
    StringIO.open(data) do |io|
      len = io.getbyte
      protocol = io.read(len)
      reserved = io.read(8)
      obtained_infohash = io.read(20)
      obtained_peerid = io.read(20)
      validate_handshake(protocol, obtained_infohash, obtained_peerid)
      handshaked!
    end
  end

  def handshaked!
    @handshaked = true
  end

  def validate_handshake(protocol, obtained_infohash, obtained_peerid)
    return if handshake_valid?(protocol, obtained_infohash, obtained_peerid)
    initiate_disconnect!
  end

  def handshake_valid?(protocol, obtained_infohash, obtained_peerid)
    [PROTOCOL, info_hash, obtained_peerid] == [protocol, obtained_infohash, obtained_peerid]
  end

  def initiate_disconnect!
    disconnect! && throw(:unwind)
  end

  def unbind
    teardown!
  end

  def teardown!
    remove(self)
  end

  def reconnect!(port)
    # set as uninterested
    puts "#{self} reconnect .... "
    @port = port
    ## ask event machine to reconnect (be careful not to have duplicate connection)
    reconnect @host, @port
  end

  def handshake
    "\x13BitTorrent protocol\x00\x00\x00\x00\x00\x00\x00\x00#{info_hash}#{id}"
  end

  def store_bitfield(data)
    byte_array = data.unpack('B8' * data.length)
    bit_array  = byte_array.join.split('').map(&:to_i)
    bit_array.each_with_index do |bit, index|
      next if bit.zero?
      set_bitfield(index)
    end
  end

  def set_bitfield(index)
    @bitfield.set_bit(index)
  end

  def have_piece?(index)
    @bitfield.have_bit?(index)
  end

  def read_in(payload)
    piece_num, block_num, length = dissect_request_payload!(payload)
    puts "#{self} Got Request ....#{piece_num}"
    return unless client.has_piece?(piece_num)
    piece = find_piece(piece_num)
    data = piece.read(length) || ''
    return unless data.length == length
    return unless piece.matches_checksum?(data)
    puts "#{self} read the bytes"
    len = [9 + length].pack('N')
    msgId = "\7"
    index = [piece_num].pack('N')
    block_num = [block_num].pack('N')
    puts "#{self} Uploading ... #{piece_num}"
    send_data(len << msgId << index << block_num << data)
  end

  def sha1hash_for(data)
    Digest::SHA1.new.digest(data)
  end

  def dissect_request_payload!(payload)
    length = payload.size
    piece_num = payload.slice!(0, 4).unpack('N').first
    block_num = payload.slice!(0, 4).unpack('N').first
    dlen = payload.slice!(0, length - 8).unpack('N').first
    [piece_num, block_num, dlen]
  end

  def write_out(data)
    piece_num, block_num, data = dissect_payload!(data)
    piece = find_piece(piece_num)
    return unless piece
    return if piece.written
    ## If piece is already written no need to write again
    piece.blocks << initialize_block_info(piece_num, block_num, data)
    process(piece) if piece.complete?
  end

  def process(piece)
    piece.invalid_checksum? ? reprocess(piece) : write(piece)
  end

  def write(piece)
    piece.write
    return unless piece.written
    puts 'piece written'
    piece_num = piece.piece_num
    update_client_bitfield(piece_num)
  end

  def reprocess(piece)
    # if the piece is invalid we reschedule it back
    until piece.blocks.empty?
      block = piece.blocks.pop
      enqueue(block)
    end
  end

  def enqueue(_block)
    scheduler_queue.push build_block(blockInfo)
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
      length: data.size
    }
  end

  def find_piece(piece_num)
    pieces.find { |piece| piece.piece_num == piece_num }
  end

  def send_have(piece_num)
    msg_len = "\0\0\0\5"
    id = "\4"
    piece_index = [piece_num].pack('N')
    puts "sending have message ...#{piece_num}"
    send_data(msg_len << id << piece_index)
  end

  def dissect_payload!(payload)
    length = payload.size
    piece_num = payload.slice!(0, 4).unpack('N').first
    block_num = payload.slice!(0, 4).unpack('N').first
    data = payload.slice!(0, length - 8)
    [piece_num, block_num, data]
  end

  def has_more_payload?
    !payload.empty?
  end

  def update_client_bitfield(piece_num)
    @client.update_bitfield(piece_num)
  end

  def to_s
    "#<Peer: #{ip}:#{port}>"
  end
end
