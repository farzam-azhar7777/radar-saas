# The client, in the one glance that decides whether a job is worth a bid.
#
# The client panel used to sit below the post, so a long post pushed it out of
# sight and it was found by chance. It now leads the page, opening with a
# verdict built only from the numbers beside it: nothing is inferred that the
# person could not check for themselves in the row below.
class ClientSnapshot
  Reading = Struct.new(:label, :value, :detail, :tone, keyword_init: true)

  # tone: :good, :warn, :bad or :neutral
  Verdict = Struct.new(:text, :tone, keyword_init: true)

  WORKDAY_HOURS = 9

  def initialize(posting)
    @p = posting
  end

  def verdict
    return Verdict.new(text: "Payment not verified. Upwork has no payment method on file for this client.", tone: :bad) if unverified?
    return Verdict.new(text: "First job on Upwork. There is no history to judge this client on yet.", tone: :warn) if no_history?

    notes = []
    tone = :neutral

    if established?
      notes << "Established client who hires"
      tone = :good
    elsif hires_rarely?
      notes << "Posts often, hires rarely: #{hire_rate}% of #{posted} jobs"
      tone = :warn
    elsif hire_rate.to_i >= 50
      notes << "Hires when they post"
    end

    if spent.positive? && spent < 1_000 && !privacy?
      notes << "small budgets so far: $#{delimit(spent)} across #{pluralize(hires, 'hire')}"
      tone = :warn if tone == :neutral
    end

    if rating.positive? && rating < 4.0
      notes << "rated #{format('%.1f', rating)} by freelancers"
      tone = :warn
    end

    if overlap&.zero?
      notes << "no working hours in common with you"
      tone = :warn unless tone == :good
    end

    notes << "Verified payment" if notes.empty?
    text = notes.first.dup
    text << (notes.size > 1 ? ", but #{notes.drop(1).to_sentence}" : "") << "."
    Verdict.new(text: text.sub(/\A./, &:upcase), tone: tone)
  end

  def readings
    list = []
    list << Reading.new(label: "Payment", value: payment_label, tone: payment_tone)

    list << if privacy?
      Reading.new(label: "Spent", value: "Hidden", detail: "by the client", tone: :neutral)
    else
      Reading.new(label: "Spent", value: "$#{delimit(spent)}",
                  detail: [ pluralize(hires, "hire"), (avg_per_hire && "$#{delimit(avg_per_hire)} each") ].compact.join(", "),
                  tone: spent >= 10_000 ? :good : (spent.zero? ? :warn : :neutral))
    end

    if posted.positive?
      list << Reading.new(label: "Hire rate", value: hire_rate ? "#{hire_rate}%" : "None",
                          detail: "of #{pluralize(posted, 'job')} posted",
                          tone: hire_rate.to_i >= 50 ? :good : :warn)
    end

    if rating.positive?
      list << Reading.new(label: "Rating", value: format("%.1f", rating), detail: "from #{pluralize(reviews, 'review')}",
                          tone: rating >= 4.5 ? :good : (rating < 4.0 ? :warn : :neutral))
    end

    if (location = @p.client_location)
      list << Reading.new(label: "Location", value: location, detail: (@p.client_local_time && "#{@p.client_local_time} there"), tone: :neutral)
    end

    unless overlap.nil?
      list << Reading.new(label: "Hours shared", value: "#{overlap} of #{WORKDAY_HOURS}",
                          detail: "of your working day", tone: overlap >= 4 ? :good : :warn)
    end

    list
  end

  def last_hired_for = @p.client_last_contract_title.presence

  def timezone = @p.client_timezone.presence

  private

  def unverified? = @p.client_payment_verified == false
  def privacy? = @p.client_financial_privacy == true
  def spent = @p.client_total_spent.to_f
  def hires = @p.client_total_hires.to_i
  def posted = @p.client_total_posted_jobs.to_i
  def reviews = @p.client_total_reviews.to_i
  def rating = @p.client_rating.to_f
  def hire_rate = @p.client_hire_rate
  def avg_per_hire = @p.client_avg_per_hire
  def overlap = @p.client_overlap_hours

  def no_history? = posted.zero? && spent.zero? && hires.zero?
  def established? = !privacy? && spent >= 10_000 && hire_rate.to_i >= 50 && (rating.zero? || rating >= 4.5)
  def hires_rarely? = posted >= 5 && hire_rate.to_i < 30

  def payment_label
    return "Verified" if @p.client_payment_verified == true
    return "Not verified" if unverified?

    "Unknown"
  end

  def payment_tone
    return :good if @p.client_payment_verified == true
    return :bad if unverified?

    :neutral
  end

  def delimit(n) = ActiveSupport::NumberHelper.number_to_delimited(n.to_i)

  def pluralize(count, word) = "#{count} #{count == 1 ? word : word.pluralize}"
end
