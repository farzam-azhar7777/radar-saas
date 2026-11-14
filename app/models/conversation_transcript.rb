class ConversationTranscript
  TIME = /\A\d{1,2}:\d{2}\s?[AP]M\z/i
  DATE = /\A(?:(?:Today|Yesterday)|(?:Mon|Tues|Wednes|Thurs|Fri|Satur|Sun)day(?:,.*)?|[A-Z][a-z]{2,8} \d{1,2}(?:, \d{4})?)\z/

  Line = Struct.new(:role, :body)

  def self.parse(text, me:) = new(text, me).messages

  def initialize(text, me)
    @lines = text.to_s.gsub("\r\n", "\n").lines.map(&:strip)
    @me = Array(me).compact_blank.map(&:downcase)
  end

  def messages
    found = []
    speaker = nil
    @lines.each_with_index do |line, i|
      if header?(i)
        speaker = line
        found << Line.new(role_of(speaker), +"")
      elsif line.match?(TIME) && speaker
        found << Line.new(role_of(speaker), +"") unless header?(i - 1)
      elsif found.any?
        found.last.body << line << "\n"
      end
    end
    return if found.empty?

    found.each { |m| m.body = tidy(m.body) }.reject { |m| m.body.blank? }.presence
  end

  private

  def header?(i)
    i >= 0 && @lines[i].present? && !@lines[i].match?(TIME) && @lines[i + 1].to_s.match?(TIME)
  end

  def role_of(speaker) = @me.any? { |name| speaker.downcase.start_with?(name) } ? "me" : "client"

  def tidy(body)
    lines = body.lines.map(&:strip)
    lines.pop while lines.any? && (lines.last.blank? || lines.last.match?(DATE))
    lines.join("\n").gsub(/\n{3,}/, "\n\n").strip
  end
end
