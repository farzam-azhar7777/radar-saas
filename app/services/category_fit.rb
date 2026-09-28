# Upwork classifies every posting itself, and Radar was throwing that away.
#
# It is the one signal that survives a post which never names a framework. The
# healthcare job that prompted this scored 0 on skills because its requirements
# were PointClickCare and X12 EDI rather than Rails or Next.js, while Upwork had
# already filed it under web_development.
#
# Coarser than a skill match and weighted accordingly. It says which desk the
# work sits on, not whether Farzam can do it.
class CategoryFit
  # Subcategory is the specific signal and is checked first. Values are the
  # fraction of the component's weight the posting earns.
  SUBCATEGORY = {
    # Exactly what he does.
    "web_development"                 => 1.0,
    "ai_apps_integration"             => 1.0,

    # His work, one step off the centre.
    "devops_solution_architecture"    => 0.7,
    "ai_machine_learning"             => 0.7,
    "other_software_development"      => 0.6,
    "scripts_utilities"               => 0.6,
    "data_extraction_etl"             => 0.6,

    # Software, but not his. He can take these; they are not what he is for.
    "desktop_application_development" => 0.4,
    "mobile_development"              => 0.4,
    "data_mining_management"          => 0.4,
    "data_analysis_testing"           => 0.4,
    "qa_testing"                      => 0.3,
    "erp_crm_software"                => 0.3,
    "information_security_compliance" => 0.3,

    # Deliberately low. Upwork files Shopify, Wix and Squarespace work here, and
    # it is the single largest source of noise in the web category.
    "ecommerce_development"           => 0.2,

    # Software-adjacent but a different trade.
    "web_mobile_design"               => 0.0,
    "product_management_scrum"        => 0.0,
    "game_design_development"         => 0.0,
    "blockchain_nft_cryptocurrency"   => 0.0,
    "network_system_administration"   => 0.0
  }.freeze

  # Used when the subcategory is missing or unrecognised: the right department,
  # desk unknown.
  CATEGORY = {
    "web_mobile_software_dev" => 0.6,
    "data_science_analytics"  => 0.4,
    "it_networking"           => 0.3
  }.freeze

  def self.call(...) = new(...).call

  def initialize(posting)
    @posting = posting
  end

  # [fraction, note] to match the other scoring components.
  def call
    sub = normalize(@posting.subcategory)
    cat = normalize(@posting.category)

    if sub.present? && SUBCATEGORY.key?(sub)
      [ SUBCATEGORY[sub], "Upwork filed it under #{label(sub)}" ]
    elsif cat.present? && CATEGORY.key?(cat)
      [ CATEGORY[cat], "Filed under #{label(cat)}, no closer detail" ]
    elsif cat.present?
      [ 0.0, "Filed under #{label(cat)}, not your field" ]
    else
      # Absent on a small number of postings. Neutral rather than punitive:
      # missing data is not evidence against the job.
      [ 0.5, "Upwork did not classify it" ]
    end
  end

  private

  def normalize(value) = value.to_s.strip.downcase.presence

  def label(key) = key.tr("_", " ")
end
