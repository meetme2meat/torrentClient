class BlockRequestScheduler
  BLOCK_SIZE = 2**14
  extend Forwardable

  attr_reader :scheduler_channel, :scheduler_queue, :metainfo
  def initialize(metainfo, scheduler_channel, scheduler_queue)
    @metainfo          = metainfo
    @scheduler_channel = scheduler_channel
    @scheduler_queue   = scheduler_queue
    divide_piece_and_block!
  end
  def_delegators :@metainfo, :connected_peers, :piece_length, :total_length

  # def schedule!
  #   puts "total block size are #{@scheduler_queue.size} "
  #   ## probably worth using tick_loop
  #   ## @tickloop = EM::tick_loop { block_peer_assignment }
  #   EM::PeriodicTimer.new(0.25) { block_peer_assignment }
  # end

  def divide_piece_and_block!
    store_block_but_last_piece
    store_block_for_last_piece
  end

  def store_block_but_last_piece
    0.upto(total_number_pieces - 2) do |piece_num|
      0.upto(number_of_full_block_in_a_piece - 1) do |block_num|
        store_block_in_queue(piece_num, block_num, BLOCK_SIZE)
      end
    end
  end

  def store_block_for_last_piece
    store_full_block_for_last_piece
    store_last_block_for_last_piece
  end

  def store_full_block_for_last_piece
    0.upto(number_of_full_block_in_last_piece - 1) do |block_num|
      store_block_in_queue(last_piece_num - 1, block_num, BLOCK_SIZE)
    end
  end

  def store_last_block_for_last_piece
    return if last_block_in_last_piece_size.zero?
    store_block_in_queue(last_piece_num - 1, last_block_num_for_last_piece, last_block_in_last_piece_size)
  end

  def store_block_in_queue(piece_num, block_num, length)
    scheduler_queue.push build_block_info(piece_num, block_num, length)
  end

  def schedule!
    scheduler_queue.pop do |blockInfo|
      # if it can find peer for the block then reschedule it back to the scheduler queue
      delegator = find_peer_for(blockInfo[:index]) || scheduler_queue
      delegator.push blockInfo
    end
  end

  def find_peer_for(piece)
    available_peers.find_all do |peer|
      peer.have_piece?(piece)
    end.sample
  end

  def available_peers
    connected_peers.unchoking_remote_peers.interested_peers.all
  end

  def build_block_info(index, offset, length)
    {
      index:  index,
      offset: offset,
      length: length
    }
  end

  def calculate_block_num(block)
    block[:index] * number_of_full_block_in_a_piece + block[:offset]
  end

  def last_block_in_last_piece_size
    last_piece_size.remainder(BLOCK_SIZE)
  end

  def number_of_full_block_in_last_piece
    last_piece_size / BLOCK_SIZE
  end
  alias last_block_num_for_last_piece number_of_full_block_in_last_piece

  def last_piece_size
    total_length - (total_number_pieces - 1) * piece_length
    # total_length.remainder(piece_length)
  end

  def number_of_full_pieces
    total_length / piece_length
  end

  def total_number_pieces
    (total_length.to_f / piece_length).ceil
  end
  alias last_piece_num total_number_pieces

  def number_of_full_block_in_a_piece
    piece_length / BLOCK_SIZE
  end
end
