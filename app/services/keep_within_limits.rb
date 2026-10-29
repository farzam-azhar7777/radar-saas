class KeepWithinLimits
  def self.call(postings)
    Array(postings).reject do |posting|
      breach = posting.saved_search&.search_limits&.breach(posting)
      next false unless breach

      reason = { "key" => "outside_limits", "points" => 0, "max" => 100, "note" => breach }
      posting.update!(status: "ignored", score_reasons: Array(posting.score_reasons) + [ reason ])
      true
    end
  end
end
