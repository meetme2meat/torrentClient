$LOAD_PATH.push(Dir.pwd)
require 'eventmachine'
require 'bencode'
require 'metainfo'
require 'block_request_scheduler'
require 'tracker'
require 'peer'
require 'message_handler'
require 'signal_handler'
class Client
  extend Forwardable
  attr_reader :metainfo, :id, :response_channel, :request_channel, :scheduler_queue, :tick_loop, :broadcast_channel, :seeder, :bitfield
  def initialize(torrent_file, download_path)
    @response_channel   =   EM::Channel.new
    @request_channel    =   EM::Channel.new
    @scheduler_queue    =   EM::Queue.new
    @id                 =   gen_id
    @metainfo           =   get_metainfo(torrent_file)
    @tracker            =   get_tracker
    @message_handler    =   MessageHandler.new(@response_channel)
    @block_scheduler    =   BlockRequestScheduler.new(@metainfo, @request_channel, @scheduler_queue)
    @broadcast_channel  =   EM::Channel.new
    @bitfield           =   BitField.new(Array.new(bitfield_length, 0))
    @metainfo.client    =   self
    @tick_loop          =   EM::TickLoop.new { @block_scheduler.schedule! }
    @metainfo.build_file_handlers(download_path)
    @metainfo.observe_file_handlers
  end
  def_delegators :@metainfo, :file_handlers, :bitfield_length, :connected_peers, :total_pieces

  def get_tracker
    Tracker.new(@metainfo, self)
  end

  def seeder?
    @seeder
  end

  def run!
    # this start tracker HTTP cycle
    @tracker.start!(tracker_params)
    # start the subscriber for channel
    @message_handler.start!
    # # start sending block
    start_block_scheduling!

    start_broadcasting

    on_stop { cleanup! }
  end

  def start_block_scheduling!
    EM.add_timer(10) do
      @tick_loop.start
      @tick_loop.on_stop { puts 'Client enter super seeder ...' }
    end
  end

  def on_stop(&block)
    EM.add_shutdown_hook &block
  end

  def brodcast_not_interested
    puts 'broadcasting not interested'
    connected_peers.unchoking_remote_peers.interested_peers.all.each do |peer|
      peer.am_not_interested!
      puts "------ #{peer.state}"
    end
  end

  def close_write_handler
    return unless file_handlers.all?(&:finished?)
    puts 'closing all write handler'
    file_handlers.each do |i|
      puts "closing ... #{i.file_name}"
      i.close!
    end
  end

  def enter_super_seeder
    @seeder = true
    @tick_loop.stop
    brodcast_not_interested
    close_write_handler
  end

  def cleanup!
    file_handlers.each(&:cleanup!)
  end

  def tracker_params
    {
      info_hash:  @metainfo.info_hash,
      peer_id:    @client_id,
      port:       '6881',
      event:      'started',
      uploaded:   '0',
      downloaded: '0',
      left:       '10000',
      compact:    '0',
      no_peer_id: '0'
    }
  end

  def gen_id
    20.times.reduce('') { |str, _| str << rand(9).to_s }
  end

  def get_metainfo(torrent_file)
    Metainfo.new(torrent_file)
  end

  def update_bitfield(piece_index)
    bitfield.set_bit(piece_index)
  end

  def start_broadcasting
    puts 'BROADCASTIN ....'
    EM::PeriodicTimer.new(20) do
      if bitfield.set_bits.any?
        puts 'starting broadcasting ...'
        available_peers.each do |peer|
          pieces = piece_missing_for(peer)
          broadcast(peer, pieces)
        end
      end
    end
  end

  def available_peers
    connected_peers.unchoking_peers.interested_remote_peers.all
  end

  # #[p1, p2, p3]
  ##
  def broadcast(peer, pieces)
    pieces.each { |index| peer.send_have(index) }
  end

  def has_piece?(number)
    bitfield.has_bit?(number)
  end

  def piece_missing_for(peer)
    ## send only 5 piece every time to each peer
    ## instead of flooding them with have message
    peer.bitfield.unset_bits.lazy.select { |index| bitfield.has_bit?(index) }.first(35)
  end
end

EM.run do
  Client.new(ARGV[0], ARGV[1]).run!
  SignalHandler.trap!
end
