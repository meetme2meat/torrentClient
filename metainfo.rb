require 'pry'
require 'piece'
require 'file_handler'
require 'digest/sha1'
require 'em-http-request'
class Metainfo
  attr_accessor :client_id, :announce, :piece_length,:info_hash, :connected_peers, :pieces, :client
  attr_reader :file_handlers
  def initialize(torrent_file, download_path)
    @connected_peers  = []
    @pieces           = []
    @file_handlers    = []
    @torrent_file     = torrent_file
    load_torrent_file!
    set_metainfo
    build_pieces
    build_file_handlers(download_path)
    observe_file_handlers
  end


  def add(peer)
    @connected_peers << peer
  end

  def remove(peer)
    connected_peers.delete(peer)
  end

  def connected?(ip, port)
    connected_peers.detect do |peer|
      [peer.ip, peer.port] == [ip, port]
    end
  end

  def load_torrent_file!
    @metainfo = BEncode::Parser.new(File.open(@torrent_file)).parse!
  end

  def set_metainfo
    @announce       = @metainfo['announce']
    @announce_lists = @metainfo['announce_lists']
    @created_by     = @metainfo['created by']
    @created_date   = @metainfo['creation date']
    @info_hash      = Digest::SHA1.new.digest(@metainfo['info'].bencode)
    @piece_length   = @metainfo['info']['piece length']
    @pieces_hashes  = @metainfo['info']['pieces']
    @total_length   = total_length
  end

  def build_pieces
    build_piece_but_last_piece
    build_last_piece
  end

  def build_piece_but_last_piece
    0.upto(total_pieces - 2) do |piece_num|
      piece_hash = get_piece_hash(piece_num)
      @pieces  << Piece.new(self , piece_num, @piece_length, piece_hash)
    end
  end

  def build_last_piece
    @pieces << Piece.new(self , total_pieces-1, last_piece_length, get_piece_hash(total_pieces-1))
  end

  def get_piece_hash(piece_num)
    @pieces_hashes[(20*piece_num)..(20*(piece_num+1)-1)]
  end

  def total_pieces
    (total_length.to_f / @piece_length).ceil
  end

  def last_piece_length
    total_length.remainder(@piece_length)
  end

  def total_length
    if multi?
      @metainfo['info']['files'].inject(0) {|size, file| size + file['length'] }
    else
      @metainfo['info']['length']
    end
  end

  def build_file_handlers(directory)
    if multi?
      @metainfo['info']['files'].inject(0) do |start_byte,file_hash|
        file_name = File.expand_path(directory, file_hash['path'].join(seperator))
        length    = file_hash['length']
        end_byte  = start_byte + (length - 1)
        @file_handlers << initialize_file_handler(file_name, length, start_byte, end_byte)
        start_byte = end_byte + 1
      end
    else
      file_name = File.expand_path(directory, @metainfo['info']['name'])
      @file_handlers << initialize_file_handler(file_name, total_length, 0 ,total_length - 1)
    end
  end

  def initialize_file_handler(file_name, size, start_byte, end_byte)
    FileHandler.new(file_name, size, start_byte , end_byte)
  end

  def multi?
    @metainfo['info']['files']
  end

  def seperator
    RUBY_PLATFORM =~ /window/ ? '\\' : '/'
  end

  def observe_file_handlers
    timer = EM::PeriodicTimer.new(10) do 
      if file_handlers.all? { |handler| handler.finished? }
        puts "--- Client entering super seeding mode."
        client.enter_super_seeder
        timer.cancel
      end
    end
  end
end
