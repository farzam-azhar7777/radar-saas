# Upwork strips markdown, so proposals carry emphasis as Mathematical
# Alphanumeric glyphs instead. Used for the default signature; the person can
# overwrite it with their own.
module UnicodeBold
  # Bold italic serif, the signature style: 𝑭𝒂𝒓𝒛𝒂𝒎
  def self.italic(text)
    map(text, upper: 0x1D468, lower: 0x1D482, digit: 0x1D7CE)
  end

  # Bold sans, the section-heading style: 𝗠𝘆 𝗦𝗸𝗶𝗹𝗹𝘀
  def self.sans(text)
    map(text, upper: 0x1D5D4, lower: 0x1D5EE, digit: 0x1D7EC)
  end

  def self.map(text, upper:, lower:, digit:)
    text.to_s.each_char.map { |c|
      case c
      when "A".."Z" then (upper + c.ord - 65).chr(Encoding::UTF_8)
      when "a".."z" then (lower + c.ord - 97).chr(Encoding::UTF_8)
      when "0".."9" then (digit + c.ord - 48).chr(Encoding::UTF_8)
      else c
      end
    }.join
  end
end
