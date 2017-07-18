$LOAD_PATH.push(Dir.pwd)
require 'eventmachine'
require 'bencode'
require 'metainfo'
require 'block_request_scheduler'
require 'tracker'
require 'peer'
require 'message_handler'
require 'signal_handler'
require 'server'
class Client
  extend Forwardable
  attr_reader :metainfo, :id, :response_channel, :request_channel, :scheduler_queue, :tick_loop, :seeder
  attr_accessor :tracker_id
  def initialize(torrent_file, download_path)
    @metainfo           =   get_metainfo(torrent_file, download_path)
    @id                 =   gen_id
    @metainfo.client_id =   @id
    @tracker            =   get_tracker
    @response_channel   =   EM::Channel.new
    @request_channel    =   EM::Channel.new
    @scheduler_queue    =   EM::Queue.new
    @message_handler    =   MessageHandler.new(@response_channel)
    @block_scheduler    =   BlockRequestScheduler.new(@metainfo, @request_channel, @scheduler_queue)
    @metainfo.client    =   self
    ## store this in a db
    @bitfields          =   BitField.new(Array.new(bitfield_length,0))
    ## Uncomment this
    #@tick_loop          =   EM::TickLoop.new { @block_scheduler.schedule! }
    #rebuild_bitfield!
    start_tcp_server
  end
  def_delegators :@metainfo, :file_handlers, :total_pieces, :info_hash

  def get_tracker
    Tracker.new(@metainfo, self)
  end

  def run!
    # this start tracker HTTP cycle
    @tracker.start!

    ## start the subscriber for channel
    @message_handler.start!

    # # start sending block
    start_block_scheduling!

    ## on stop cleanup resources
    # on_stop { cleanup! }
  end

  def start_tcp_server
    Server.run(self)
  end

  def start_block_scheduling!
    @block_scheduler.schedule!
    # EM.add_timer(10) do
    #   @tick_loop.start
    #   @tick_loop.on_stop { puts 'Client entering super seeding mode .. ' }
    # end
  end

  def on_stop(&block)
    EM.add_shutdown_hook &block
  end

  def enter_super_seeder
    @seeder = true
    puts 'entering super seeding mode'
    @tick_loop.stop
  end

  def cleanup!
    file_handlers.each(&:cleanup!)
  end

  def tracker_params
    {
      info_hash:  @metainfo.info_hash,
      peer_id:    @metainfo.client_id,
      port:       '6881',
      event:      'started',
      uploaded:   '0',
      downloaded: '0',
      left:       '10000',
      compact:    '0',
      no_peer_id: '0'
      trackerid:   trackerid
    }.reject { |k,v| v.nil? }
  end

  def gen_id
    20.times.reduce('') { |str, _| str << rand(9).to_s }
  end

  def get_metainfo(torrent_file, download_path)
    Metainfo.new(torrent_file, download_path)
  end

  def broadcast
    @broadcast.subscribe do |piece_num|
      @metainfo.connected_peers.interested.all.each do |peer|
        peer.send_have(piece_num)
      end
    end
  end

  def super_seeder?
    !!seeder
  end

  def bitfield_length
    (total_pieces / 8).ceil * 8
  end

  # def rebuild_bitfields
  ## Take info from a stored file about bitfields and reset the bitfields
  # end
end

EM.run do
  Client.new(ARGV[0], ARGV[1]).run!
  SignalHandler.trap!
end
