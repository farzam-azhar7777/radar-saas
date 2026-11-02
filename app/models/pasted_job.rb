class PastedJob
  include ActiveModel::Model
  include ActiveModel::Attributes

  BUDGETS = { "" => "Not stated", "hourly" => "Hourly", "fixed" => "Fixed price" }.freeze
  UPWORK_LINK = %r{upwork\.com/\S*?~02(\d{6,})}

  attribute :post, :string
  attribute :title, :string
  attribute :questions, :string
  attribute :budget, :string, default: ""
  attribute :budget_min, :decimal
  attribute :budget_max, :decimal
  attribute :bids, :integer
  attribute :link, :string
  attribute :saved_search_id, :integer

  attr_reader :posting

  validates :post, length: { minimum: 40, message: "needs the job description, at least a few sentences" }
  validates :budget, inclusion: { in: BUDGETS.keys }
  validates :budget_min, :budget_max, :bids, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
  validate { errors.add(:link, "is not an Upwork job link") if link.present? && upwork_id_from_link.nil? }

  def save
    return false unless valid?

    @posting = existing || build
    @already_in_radar = existing.present?
    @posting.update!(status: "matched") if @already_in_radar && %w[ignored dismissed].include?(@posting.status)
    @posting.save! unless @already_in_radar
    FetchClientStats.call([ @posting ]) if !@already_in_radar && @posting.on_upwork?
    true
  end

  def already_in_radar? = @already_in_radar

  def question_list = questions.to_s.split(/\r?\n/).map(&:strip).reject(&:blank?)

  private

  def upwork_id_from_link = link.to_s[UPWORK_LINK, 1]

  def existing
    return @existing if defined?(@existing)

    id = upwork_id_from_link
    @existing = id && JobPosting.find_by(upwork_id: id)
  end

  def build
    id = upwork_id_from_link
    posting = JobPosting.new(
      source: "pasted",
      upwork_id: id || "#{JobPosting::PASTED_ID_PREFIX}#{SecureRandom.hex(6)}",
      ciphertext: id && "~02#{id}",
      job_url: id && "https://www.upwork.com/jobs/~02#{id}",
      title: title.presence&.strip || first_line,
      description: post.strip,
      screening_questions: question_list,
      total_applicants: bids,
      published_at: Time.current,
      notified_at: Time.current,
      detail_fetched_at: id && question_list.empty? ? nil : Time.current,
      status: "matched"
    )
    apply_budget(posting)
    posting.saved_search = chosen_search || BestSearchFor.call(posting, fallback: SavedSearch.ordered.first)
    outcome = ScoreJobPosting.call(posting, saved_search: posting.saved_search) if posting.saved_search
    posting.score, posting.score_reasons = outcome&.score, outcome&.reasons || []
    posting
  end

  def apply_budget(posting)
    case budget
    when "hourly"
      posting.contract_type = "Hourly"
      posting.hourly_min = budget_min
      posting.hourly_max = budget_max || budget_min
    when "fixed"
      posting.contract_type = "Fixed price"
      posting.fixed_amount = budget_min || budget_max
    end
  end

  def chosen_search = saved_search_id && SavedSearch.find_by(id: saved_search_id)

  def first_line = post.to_s.lines.map(&:strip).find(&:present?).to_s.truncate(120, omission: "…")
end
