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

  def unset_bit(number)
    @bits[number] = 0
  end

  def set_bits
    bits.each_index.select { |index| bits[index] == 1 }
  end

  def unset_bits
    # can do lazy on this
    bits.each_index.select { |index| bits[index].zero? }
  end

  def to_s
    bits.inspect
  end
end
