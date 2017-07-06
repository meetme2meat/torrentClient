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
  attr_reader :metainfo, :id, :response_channel, :request_channel, :scheduler_queue, :tick_loop
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
    @tick_loop          =   EM::TickLoop.new { @block_scheduler.schedule! }
  end
  def_delegator :@metainfo, :file_handlers

  def get_tracker
    Tracker.new(@metainfo, self)
  end

  def run!
    # this start tracker HTTP cycle
    @tracker.start!(tracker_params)

    # start the subscriber for channel
    @message_handler.start!

    # start sending block
    start_block_scheduling!

    on_stop { cleanup! }
  end

  def start_block_scheduling!
    EM.add_timer(10) do
      @tick_loop.start
      @tick_loop.on_stop { puts 'Client entering super seeding mode .. ' }
    end
  end

  def on_stop(&block)
    EM.add_shutdown_hook &block
  end

  def enter_super_seeder
    puts 'entering super seeding mode'
    @tick_loop.stop
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
      compact:    '1',
      no_peer_id: '0'
    }
  end

  def gen_id
    20.times.reduce('') { |str, _| str << rand(9).to_s }
  end

  def get_metainfo(torrent_file, download_path)
    Metainfo.new(torrent_file, download_path)
  end
end

EM.run do
  Client.new(ARGV[0], ARGV[1]).run!
  SignalHandler.trap!
end
