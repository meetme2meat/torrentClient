require 'utils'
class Server < EM::Connection
  KEEP_ALIVE_INTERVAL    = 60
  HANDSHAKE_PAYLOAD_SIZE = 68
  PROTOCOL = 'BitTorrent protocol'.freeze
  KEEP_ALIVE_MESSAGE = "\x00\x00\x00\x00".freeze

  extend Forwardable
  extend Utils
  def self.run(client)
    EM.start_server host, port, self, client: client
  end

  attr_reader :client, :handshaked, :ipaddrs, :port
  def initialize(args)
    @payload = String.new
    @client = args[:client]
    @handshaked = false
  end

  def post_init
    @port, @ipaddrs = Socket.unpack_sockaddr_in(get_peername)
    p "-- Initiated connection -- #{client.id}"
  end

  def receive_data(data)
    catch(:unwind) do
      @payload <<  data
      process!
    end
  end

  def process!
    process_handshake unless handshaked?
    process_message!
  end

  def process_handshake
    data = payload.byteslice(0, HANDSHAKE_PAYLOAD_SIZE)
    throw(:unwind) unless data.size.eql?(HANDSHAKE_PAYLOAD_SIZE)
    payload.slice!(0, HANDSHAKE_PAYLOAD_SIZE)

    StringIO.open(data) do |io|
      len = io.getbyte
      protocol = io.read(len)
      reserved = io.read(8)
      infohash = io.read(20)
      peerid   = io.read(20)
      validate_handshake(protocol, infohash)
      send_handshake(peerid)
      handshaked!
    end
  end

  def validate_handshake(protocol, infohash)
    close_connection unless [protocol, infohash] == [PROTOCOL, client.infohash]
  end

  def send_handshake(peerid)
    send_data("\x13BitTorrent protocol\x00\x00\x00\x00\x00\x00\x00\x00#{client.info_hash}#{@client.id}")
  end

  def handshaked!
    @handshaked = true
  end

  def handshaked?
    !!@handshaked
  end

  def unbind
    puts "Closing a connection with #{ipaddrs}:#{port}"
  end

  def process_message!
    binding.pry
    puts "Processing message ..."
  end
end
