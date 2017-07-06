class BitField
  attr_reader :bits
  def initialize(byte_array)
    @bits = byte_array.join.split('').map(&:to_i)
  end

  def has_bit?(block_num)
    @bits[block_num] == 1
  end
  alias have_bit? has_bit?

  def set_bit(number)
    @bits[number] = 1
  end
end
