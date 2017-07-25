class FileHandler
  WRITE_MODE = 'wb'.freeze
  READ_MODE = 'rb'.freeze
  APPEND_MODE = 'a+'.freeze
  attr_reader :file_name, :length, :start_byte, :end_byte
  attr_accessor :read_handler, :write_handler
  def initialize(file_name, length, start_byte, end_byte)
    @file_name     = file_name
    @length        = length
    @start_byte    = start_byte
    @end_byte      = end_byte
  end

  ## check last block
  def write(piece)
    puts "writing piece -> #{piece.piece_num}"
    # seek_at = piece.seek_byte - @start_byte
    seek_at = piece.start_byte
    @write_handler.seek(seek_at)
    # end_idx = end_byte - seek_at
    piece.blocks.sort { |blk| blk[:offset] }.each do |block|
      # next if block[:data].size == 0
      # data =  block[:data].slice!(0,end_idx)
      # @write_handler.write(data)
      # piece.stored_byte_size += data.size
      @write_handler.write(block[:data])
    end
    piece.written = true
    piece.flush!
  end

  def file_exist?
    File.exist?(file_name)
  end

  def read(piece, length = nil)
    puts "reading piece -> #{piece.piece_num}"
    seek_at = piece.start_byte
    @read_handler.seek(seek_at)
    byte_length = length || piece.piece_length
    @read_handler.read(byte_length)
  end

  def contain_piece?(piece)
    # piece.seek_byte.between?(@start_byte, @end_byte)
    # @start_byte <= piece.start_byte
    (@start_byte <= piece.start_byte && @end_byte > piece.start_byte)
  end

  def close!
    finished? ? @write_handler.close : nil
  end

  def finished?
    @write_handler.size == @length
  end

  def cleanup!
    @write_handler.closed? || @write_handler.close
    @read_handler.closed?  || @read_handler.close
  end
end
