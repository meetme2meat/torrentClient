class Piece
  PIECE_SIZE = 2**14
  extend Forwardable
  attr_accessor :blocks, :written
  attr_reader :piece_num, :piece_length , :piece_length, :piece_hash

  def initialize(metainfo, piece_num, piece_length, piece_hash)
    @metainfo     = metainfo
    @piece_num    = piece_num
    @piece_length = piece_length
    @piece_hash   = piece_hash
    @written      = false
    @blocks       = []
    #@stored_byte_size = 0
  end

  def complete?
    blocks.inject(0) { |total_length,block| total_length += block[:length] } == piece_length
  end

  def write_out
    #while stored_byte_size != piece_length
      @metainfo.file_handlers.find { |handler| handler.contain_piece?(self) }.write(self)
    #end
    #flush!
  end

  def valid_checksum?
    block_hash_value == piece_hash
  end

  def invalid_checksum?
    !valid_checksum?
  end

  def block_hash_value
    Digest::SHA1.new.digest(block_value)
  end

  def block_value
    blocks.sort_by { |block| block[:block_num] }.map { |block| block[:data] }.join
  end

  ## flush the piece so that we don't store block payload in our memory
  def flush!
    0.upto(blocks.length) { blocks.pop }
  end

  def start_byte
    PIECE_SIZE * piece_num
  end

  def end_byte
    (start_byte + piece_length) - 1
  end

  def seek_byte
    @start_byte + @stored_byte_size
  end
end