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

  def start!(tracker_params)
    puts "... #{announce} .."
    begin
      http_client = EventMachine::HttpRequest.new(announce).get query: tracker_params
      http_client.errback do
        puts 'Got error response ...'
        retry!(RETRY_INTERVAL, tracker_params)
      end
      http_client.callback do
        puts 'Got response ...'
        evaluate_response!(http_client.response, tracker_params)
      end
    rescue StandardError => exception
      puts "... Got exception #{exception.message}"
    end

    # uri = URI(announce)
    # uri.query = URI.encode_www_form(tracker_params)

    # begin
    #   response = Net::HTTP.get_response(uri).body
    #   evaluate_response!(response, tracker_params)
    # rescue Errno::ECONNREFUSED
    #   puts "connection error"
    # end
  end

  def evaluate_response!(data, params)
    bencode_data = BEncode::Parser.new(data).parse!
    interval = fetch_interval(bencode_data)
    establish_connection(bencode_data['peers'])
    retry!(interval, params)
  end

  def retry!(interval, params)
    puts "retrying ...#{interval}"
    EventMachine.add_timer(interval) do
      start!(params)
    end
  end

  def fetch_interval(response)
    response.fetch('interval', RETRY_INTERVAL)
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
