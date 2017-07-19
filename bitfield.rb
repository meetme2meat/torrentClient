class BitField
  attr_reader :bits
  def initialize(byte_array)
    @bits = byte_array
  end

  def has_bit?(piece_num)
    @bits[piece_num] == 1
  end
  alias have_bit? has_bit?

  def set_bit(piece_num)
    @bits[piece_num] = 1
  end
end
