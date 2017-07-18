require 'net/http'
require 'ipaddr'
require 'em-http-request'
class Tracker
  RETRY_INTERVAL = 60
  extend Forwardable
  attr_reader :metainfo, :announce, :channel, :client
  def initialize(metainfo, client)
    @metainfo = metainfo
    @announce = metainfo.announce
    @client = client
  end
  def_delegators :@metainfo, :connected_peers, :connected?
  def_delegator :@client, :tracker_params

  def start!
    http_client = EventMachine::HttpRequest.new(announce).get query: tracker_params
    http_client.errback do
      puts 'Got error response ...'
      retry!(RETRY_INTERVAL)
    end
    http_client.callback do
      puts 'Got response ...'
      evaluate_response!(http_client.response)
    end
  rescue StandardError => exception
    puts "... Got exception #{exception.message}"

    # uri = URI(announce)
    # uri.query = URI.encode_www_form(tracker_params)

    # begin
    #   response = Net::HTTP.get_response(uri).body
    #   evaluate_response!(response, tracker_params)
    # rescue Errno::ECONNREFUSED
    #   puts "connection error"
    # end
  end

  def evaluate_response!(data)
    bencode_data = BEncode::Parser.new(data).parse!
    interval = fetch_interval(bencode_data)

    unless bencode_data['failure reason']
      warn(bencode_data['warning message']) if bencode_data['warning message']
      establish_connection(bencode_data['peers'])
    end

    update_client_tracker_id(bencode_data['trackerid'])

    retry!(interval)
  end

  def retry!(interval)
    EventMachine.add_timer(60) do
      start!
    end
  end

  def fetch_interval(response)
    response.fetch('interval', RETRY_INTERVAL)
  end

  def update_client_tracker_id(tracker_id)
    client.tracker_id = tracker_id
  end

  def establish_connection(peer_details)
    return if peer_details.empty?
    peers = sanitize_peer_details(peer_details)

    get_unpacked_peers(peers).uniq.each do |peer|
      puts ' ...... geting unpacked peers'
      Peer.connect(*peer, client) unless connected?(*peer)
    end
  end

  def sanitize_peer_details(peer_details)
    peer_details.unpack('C*').each_slice(6).map { |i| i.pack('C*') }
  end

  def get_unpacked_peers(peers)
    peers.map { |peer| peer.unpack('a4n') }.map { |peer| [IPAddr.new_ntoh(peer[0]).to_s, peer[1]] }
  end
end
