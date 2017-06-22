class FileHandler
  def initialize(file_name, length, start_byte, end_byte)
    @file_name     = file_name
    @length        = length
    @start_byte    = start_byte
    @end_byte      = end_byte
    @write_handler = File.open(file_name, 'wb')
    @read_handler  = File.open(file_name, 'rb')
  end


  ## check last block
  def write(piece)
    puts "writing piece -> #{piece.piece_num}"
    #seek_at = piece.seek_byte - @start_byte
    seek_at = piece.start_byte
    @write_handler.seek(seek_at)
    #end_idx = end_byte - seek_at
    piece.blocks.sort {|blk| blk[:offset] }.each do |block|
      #next if block[:data].size == 0
      #data =  block[:data].slice!(0,end_idx)
      #@write_handler.write(data)
      #piece.stored_byte_size += data.size
      @write_handler.write(block[:data])
    end

    piece.written = true
    piece.flush! && close!
  end

  def contain_piece?(piece)
    # piece.seek_byte.between?(@start_byte, @end_byte)
    # @start_byte <= piece.start_byte
    (@start_byte <= piece.start_byte and @end_byte > piece.start_byte)
  end

  def close!
    finished? ? @write_handler.close : nil
  end

  def finished?
    @write_handler.closed? || @write_handler.size == @length
  end

  def cleanup!
    @write_handler.closed? || @write_handler.close
    @read_handler.closed?  || @read_handler.close
  end
end