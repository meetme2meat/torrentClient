require 'ipaddr'
require 'em-http-request'
class Tracker
  RETRY_INTERVAL = 60
  extend Forwardable
  attr_reader :metainfo, :announce, :channel, :client
  def initialize(metainfo, client)
    @metainfo = metainfo
    ## one can have multiple announce
    @announce = metainfo.announce
    @client   = client
  end
  def_delegators :@metainfo, :connected_peers, :connected?

  def start!(tracker_params)
    http_client = EventMachine::HttpRequest.new(announce).get query: tracker_params
    http_client.errback do
      retry!(RETRY_INTERVAL, tracker_params)
    end
    http_client.callback do
      evaluate_response!(http_client.response, tracker_params)
    end
  rescue StandardError => exception
    puts "... Got exception #{exception.message}"
    retry!(RETRY_INTERVAL, tracker_params)
  end

  def retry!(interval, tracker_params)
    EM.add_timer(interval) { start!(tracker_params) }
  end

  def evaluate_response!(data, params)
    bencode_data = BEncode::Parser.new(data).parse!
    interval = fetch_interval(bencode_data)

    ## display warning and failure messages
    warn(bencode_data['failure reason'])  if bencode_data['failure reason']
    warn(bencode_data['warning message']) if bencode_data['warning message']

    peers = bencode_data.fetch('peers', [])
    establish_connection(peers)
    retry!(interval, params)
  end

  def fetch_interval(response)
    response.fetch('interval', RETRY_INTERVAL)
  end

  def establish_connection(peer_details)
    return if peer_details.empty?
    peers = sanitize_peer_details(peer_details)
    get_unpacked_peers(peers).uniq.each do |peer|
      Peer.connect(*peer, client) unless connected?(peer)
    end
  end

  def sanitize_peer_details(peer_details)
    peer_details.unpack('C*').each_slice(6).map { |i| i.pack('C*') }
  end

  def get_unpacked_peers(peers)
    peers.map { |peer| peer.unpack('a4n') }.map { |peer| [IPAddr.new_ntoh(peer[0]).to_s, peer[1]] }
  end
end
