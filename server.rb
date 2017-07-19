require 'utils'
class Server < EM::Connection
  PERIOD_KEEPALIVE_TIMER = 600
  KEEP_ALIVE_INTERVAL    = 60
  HANDSHAKE_PAYLOAD_SIZE = 68
  PROTOCOL = 'BitTorrent protocol'.freeze
  KEEP_ALIVE_MESSAGE = "\x00\x00\x00\x00".freeze
  extend Forwardable
  extend Utils
  @@connections = []

  def self.run(client)
    EM.start_server host, port, self, client: client
    # cron!
  end

  attr_reader :client, :handshaked, :ip, :port
  def initialize(args)
    @payload     =  ''
    @client      =  args[:client]
    @state       =  { interested: false, choking: true }
    @handshaked  =  false
  end
  def_delegators :@client, :super_seeder?, :bitfields

  def post_init
    @port, @ip = Socket.unpack_sockaddr_in(get_peername)
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
      len       = io.getbyte
      protocol  = io.read(len)
      reserved  = io.read(8)
      infohash  = io.read(20)
      peerid    = io.read(20)
      validate_handshake(protocol, infohash)
      send_handshake(peerid)
      send_bitfield if super_seeder?
      handshaked!
      store_connection(self)
    end
  end

  def validate_handshake(protocol, infohash)
    close! unless [protocol, infohash] == [PROTOCOL, client.info_hash]
  end

  def send_handshake(_peerid)
    send_data("\x13BitTorrent protocol\x00\x00\x00\x00\x00\x00\x00\x00#{client.info_hash}#{client.id}")
  end

  def handshaked!
    @handshaked = true
  end

  def handshaked?
    !!@handshaked
  end

  def unbind
    teardown!
    puts "Closing a connection with #{ip}:#{port}"
  end

  def teardown!
    @@connections.delete(self)
  end

  def process_message!
    @response_channel.push(self)
  end

  def sent_interest
    send_data("\0\0\0\1\2")
    interested!
  end

  def send_unchoke
    send_data("\0\0\0\1\1")
    unchoke!
  end

  def send_choke
    send_data("\0\0\0\1\0")
    choke!
  end

  def send_uninterest
    send_data("\0\0\0\1\3")
    uninterested!
  end

  def choke!
    @state[:choking] = true
  end

  def unchoke!
    @state[:choking] = false
  end

  def interested!
    @state[:interested] = true
  end

  def uninterested!
    @state[:interested] = false
  end

  def has_more_payload?
    !payload.empty?
  end

  def store_connection(connection)
    @@connections << connection
  end

  def keepalive!
    @stamped_at = Time.now
  end

  def close!
    close_connection
  end
  alias drop! close!

  def send_bitfield
    byte_array = bitfields.each_slice(8).map(&:join)
    data = byte_array.pack('B8' * byte_array.size)
    msg_id = "\5"
    len = [data.size + 1].pack('N')
    send_data(len << msg_id << data)
  end

  ## methods to remove idle connection that are just using resource for which we havent received
  ## any keep alive request under 10 minutes.
  class << self
    def cron!
      EM::PeriodicTimer.new(PERIOD_KEEPALIVE_TIMER) do
        close_idle_connection!
      end
    end

    def close_idle_connections!
      idle_connections.each do |connection|
        connection.close!
      end
      @@last_ran_at = Time.now
    end

    def idle_connections
      @@connections.find_all do |connection|
        !(last_ran_at..Time.now).cover?(connection.stamped_at) or connection.uninterested?
      end
    end

    def last_ran_at
      @@last_ran_at || PERIOD_KEEPALIVE_TIMER.seconds.ago
    end
  end
end
