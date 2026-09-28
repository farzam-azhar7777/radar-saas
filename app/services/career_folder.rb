require "erb"

# The only thing that writes the career folder's knowledge files.
#
# The proposal engine reads a folder of plain files, and it keeps reading one:
# CLAUDE.md, profile.yml, skills.yml, writing-voice.md, projects/ and
# templates/. What changed is who writes them. They used to be hand-built over
# weeks; the setup wizard writes them from a form and from the person's own
# repositories.
#
# Every write is a whole file, rendered from data Radar holds. Nothing is
# patched in place, so a file can always be regenerated from its source.
module CareerFolder
  SOURCE = Rails.root.join("lib", "career_templates")

  module_function

  def root = Radar.career_path

  def ensure!
    %w[projects templates applications].each { |dir| FileUtils.mkdir_p(root.join(dir)) }
    install_templates!
    root
  end

  # The starter templates are copied once. After that they are the person's to
  # edit, and a later write never overwrites them.
  def install_templates!
    Dir[SOURCE.join("templates", "*")].each do |source|
      target = root.join("templates", File.basename(source))
      FileUtils.cp(source, target) unless target.exist?
    end
  end

  # --- profile ----------------------------------------------------------

  def write_profile!(profile = Profile.current)
    ensure!
    write("profile.yml", "# Written by Radar's setup from your profile. Edit it in Radar, not here.\n" +
                         profile_hash(profile).to_yaml.delete_prefix("---\n"))
    write_claude_md!(profile)
  end

  def write_claude_md!(profile = Profile.current)
    template = ERB.new(SOURCE.join("CLAUDE.md.erb").read, trim_mode: "-")
    write("CLAUDE.md", template.result_with_hash(p: profile))
  end

  def profile_hash(p)
    {
      "name" => p.full_name,
      "preferred_name" => p.preferred_name.presence || p.first_name,
      "title" => p.title,
      "location" => p.location_label.presence,
      "timezone" => p.timezone_label,
      "languages_spoken" => p.languages_list.presence,
      "years_experience" => p.years_experience,
      "standing" => p.credentials_line.presence,
      "summary" => p.summary.presence,
      "contact" => {
        "email" => p.email.presence,
        "upwork" => p.upwork_url.presence,
        "github" => p.github_url.presence,
        "github_caveat" => p.github_note.presence,
        "linkedin" => p.linkedin_url.presence,
        "website" => p.website_url.presence,
        "portfolio" => p.portfolio_url.presence
      }.compact.presence,
      "availability" => {
        "hours_per_week" => p.hours_per_week,
        "start" => p.availability.presence,
        "typical_response_time" => p.response_time.presence
      }.compact.presence,
      "rates" => ({ "hourly_usd" => p.hourly_rate.to_f.then { |r| r == r.to_i ? r.to_i : r } } if p.hourly_rate.present?)
    }.compact
  end

  # --- voice ------------------------------------------------------------

  def write_voice!(profile = Profile.current)
    ensure!
    name = profile.first_name
    lines = [ "# Writing voice", "" ]

    if profile.samples.empty? && profile.winning_opening.blank?
      lines << "No samples of #{name}'s writing yet. Write plainly: short sentences, one concrete " \
               "detail per claim, contractions, no buzzwords, no exclamation marks."
    else
      lines << "Real writing by #{name}. Match its tone, sentence length and phrasing. " \
               "Take the voice from these, never the facts: facts come from the project files."
    end

    if profile.winning_opening.present?
      lines += [ "", "---", "", "## An opening #{name} sent that won work", "" ]
      lines << "Context: #{profile.winning_opening_context}" if profile.winning_opening_context.present?
      lines += [ "", quote(profile.winning_opening) ]
    end

    profile.samples.each_with_index do |sample, i|
      lines += [ "", "---", "", "## Sample #{i + 1}", "", quote(sample) ]
    end

    write("writing-voice.md", lines.join("\n") + "\n")
  end

  def quote(text) = text.to_s.strip.lines.map { |l| l.strip.empty? ? ">" : "> #{l.rstrip}" }.join("\n")

  # --- projects ---------------------------------------------------------

  def write_project!(file, yaml_text)
    ensure!
    write(File.join("projects", file), yaml_text.to_s.strip + "\n")
  end

  def remove_project!(file)
    path = root.join("projects", file)
    path.delete if path.exist?
  end

  def write_index!(entries)
    ensure!
    body = { "projects" => entries.map { |e| e.slice("file", "name", "one_liner", "tags", "relevance", "period", "role").compact } }
    write(File.join("projects", "_index.yml"),
          "# Every accepted project, rebuilt by Radar on each change. Tags and relevance drive job matching.\n" +
          body.to_yaml.delete_prefix("---\n"))
  end

  def write_skills!(groups)
    ensure!
    write("skills.yml", "# Derived from your accepted projects, weighted by your own commits.\n" \
                        "# Each entry says where the evidence came from.\n" +
                        groups.to_yaml.delete_prefix("---\n"))
  end

  # --- reading ----------------------------------------------------------

  def exists?(relative) = root.join(relative).exist?

  def read(relative)
    path = root.join(relative)
    path.exist? ? path.read : nil
  end

  def project_files = Dir[root.join("projects", "*.yml")].map { |f| File.basename(f) } - [ "_index.yml" ]

  def write(relative, content)
    path = root.join(relative)
    FileUtils.mkdir_p(path.dirname)
    # Written aside and renamed, so a reader in the other process never sees
    # half a file.
    tmp = path.sub_ext("#{path.extname}.tmp")
    File.write(tmp, content)
    File.rename(tmp, path)
    path
  end
end
