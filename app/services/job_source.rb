# The single seam between Radar and Upwork.
#
# Both implementations return the same normalized attribute hashes, so every
# schema surprise lands in JobSource::Live and nowhere else.
module JobSource
  def self.current = Live.new

  def self.live? = true
end
