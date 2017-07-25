require 'pry'
require 'piece'
require 'file_handler'
require 'digest/sha1'
require 'em-http-request'
require 'peer_list'
class Metainfo
  attr_accessor :announce, :piece_length, :info_hash, :connected_peers, :pieces, :client
  attr_reader :file_handlers
  def initialize(torrent_file)
    @pieces           = []
    @file_handlers    = []
    @connected_peers  = PeerList.new
    @torrent_file     = torrent_file
    load_torrent_file!
    set_metainfo
    build_pieces
  end

  def add(peer)
    connected_peers << peer
  end

  def remove(peer)
    connected_peers.delete(peer)
  end

  def connected?(peer_info)
    connected_peers.contain?(peer_info)
  end

  def load_torrent_file!
    @metainfo = BEncode::Parser.new(File.open(@torrent_file)).parse!
  end

  def set_metainfo
    @announce       = @metainfo['announce']
    @announce_lists = @metainfo['announce_lists']
    @created_by     = @metainfo['created by']
    @created_date   = @metainfo['creation date']
    @piece_length   = @metainfo['info']['piece length']
    @pieces_hashes  = @metainfo['info']['pieces']
    @total_length   = total_length
    @info_hash      = Digest::SHA1.new.digest(@metainfo['info'].bencode)
  end

  def build_pieces
    build_full_piece
    build_last_piece
  end

  def build_full_piece
    0.upto(total_pieces - 2) do |piece_num|
      piece_hash = get_piece_hash(piece_num)
      @pieces << Piece.new(self, piece_num, @piece_length, piece_hash)
    end
  end

  def build_last_piece
    @pieces << Piece.new(self, total_pieces - 1, last_piece_length, get_piece_hash(total_pieces - 1))
  end

  def get_piece_hash(piece_num)
    @pieces_hashes[(20 * piece_num)..(20 * (piece_num + 1) - 1)]
  end

  def total_pieces
    (total_length.to_f / @piece_length).ceil
  end

  def last_piece_length
    total_length - (total_pieces - 1) * piece_length
    # total_length.remainder(piece_length)
  end

  def total_length
    if multi?
      @metainfo['info']['files'].inject(0) { |size, file| size + file['length'] }
    else
      @metainfo['info']['length']
    end
  end

  def build_file_handlers(directory)
    if multi?
      puts 'we current do not support multi file upload/download'
      @metainfo['info']['files'].inject(0) do |start_byte, file_hash|
        file_name = File.expand_path(directory, file_hash['path'].join(seperator))
        length    = file_hash['length']
        end_byte  = start_byte + (length - 1)
        @file_handlers << initialize_file_handler(file_name, length, start_byte, end_byte)
        start_byte = end_byte + 1
      end
    else
      file_name = File.expand_path(directory, @metainfo['info']['name'])
      @file_handlers << initialize_file_handler(file_name, total_length, 0, total_length - 1)
    end
  end

  def initialize_file_handler(file_name, size, start_byte, end_byte)
    FileHandler.new(file_name, size, start_byte, end_byte).tap do |file_handler|
      file_handler.read_handler  = get_read_handle_for(file_handler)
      file_handler.write_handler = get_write_handle_for(file_handler)
    end
  end

  def get_read_handle_for(handler)
    File.open(handler.file_name, handler.class::READ_MODE)
  end

  def get_write_handle_for(handler)
    if handler.file_exist?
      find_write_handle_for(handler)
    else
      new_write_handle_for(handler)
    end
  end

  def find_write_handle_for(handler)
    piece_written_on?(handler) ? old_write_handle_for(handler) : new_write_handle_for(handler)
  end

  def old_write_handle_for(handler)
    read_h = handler.read_handler
    pieces.each do |piece|
      read_h.seek(piece.start_byte)
      data = read_h.read(piece.piece_length) || ''
      next unless piece.matches_checksum?(data)
      client.update_bitfield(piece.piece_num)
      piece.written = true
    end
    File.open(handler.file_name, handler.class::APPEND_MODE)
  end

  def new_write_handle_for(handler)
    File.open(handler.file_name, handler.class::WRITE_MODE)
  end

  def piece_written_on?(handler)
    read_h = handler.read_handler
    pieces.any? do |piece|
      read_h.seek(piece.start_byte)
      data = _read_h.read(piece.piece_length) || ''
      piece.matches_checksum?(data)
    end
  end

  def multi?
    @metainfo['info']['files']
  end

  def seperator
    RUBY_PLATFORM =~ /window/ ? '\\' : '/'
  end

  def bitfield_length
    (total_pieces / 8.0).ceil * 8
  end

  def observe_file_handlers
    timer = EM::PeriodicTimer.new(10) do
      puts 'using timer for handler '
      if file_handlers.all?(&:finished?)
        client.enter_super_seeder
        timer.cancel
      end
    end
  end
end
