require "test_helper"
require_relative "../support/git_fixture"

# The knowledge base, end to end on real git: find the repos, work out which
# commits are the person's, group repos into products, rank them, gather the
# evidence, write them up, and publish only what was accepted.
class KnowledgeEngineTest < ActiveSupport::TestCase
  include GitFixture

  ADA = [ "Ada Lovelace", "ada@home.dev" ].freeze
  ADA_WORK = [ "Ada Lovelace", "ada.lovelace@agency.com" ].freeze
  BOB = [ "Bob Builder", "bob@agency.com" ].freeze

  GEMFILE_LOCK = <<~LOCK.freeze
    GEM
      remote: https://rubygems.org/
      specs:
        rails (7.1.3)
          actionpack (= 7.1.3)
        sidekiq (7.2.0)
        stripe (10.1.0)
        pg (1.5.4)

    DEPENDENCIES
      rails (~> 7.1)
  LOCK

  setup do
    reset_career!
    Profile.current.update!(full_name: "Ada Lovelace", preferred_name: nil, skills: "Rails, Stripe")
    @root = build_folder do |root|
      git_repo(root, "acme-api", [
        [ *ADA, "Add Stripe subscription billing with webhooks", { "app/services/billing/charge.rb" => "class Charge; end\n" } ],
        [ *BOB, "Bump gems and tidy the readme", { "README.md" => "# Acme\n\nInvoicing for plumbers.\n" } ],
        [ *ADA_WORK, "Multi-tenant scoping for every invoice query", { "app/models/invoice.rb" => "class Invoice; end\n" } ],
        [ *ADA, "wip", { "app/models/invoice.rb" => "class Invoice; end\n# x\n" } ]
      ], files: { "Gemfile.lock" => GEMFILE_LOCK, "Gemfile" => "gem 'rails'\n",
                  "db/schema.rb" => %(create_table "invoices" do |t|\nend\ncreate_table "tenants" do |t|\nend\n) })
      git_repo(root, "acme-web", [
        [ *ADA_WORK, "Invoice list with filters and CSV export", { "app/invoices/page.tsx" => "export default 1\n" } ]
      ], files: { "package.json" => { dependencies: { next: "^14.2.0", react: "18.2.0" }, devDependencies: { typescript: "5" } }.to_json })
      git_repo(root, "clients/other-lib", [ [ *BOB, "Initial import of the library code" ] ])
      FileUtils.mkdir_p(root.join("node_modules", "dep"))
      git(root.join("node_modules", "dep"), "init", "-q")
    end
    @scan = Knowledge::Scan.create!(root_path: @root.to_s)
  end

  teardown do
    FileUtils.rm_rf(@root)
    install_career_fixture!
  end

  def discover! = Knowledge::DiscoverJob.perform_now(@scan).then { @scan.reload }

  def inventory!
    discover!
    Knowledge::InventoryJob.perform_now(@scan)
    @scan.reload
  end

  test "discovery finds nested repos and skips dependency folders" do
    paths = Knowledge::Discover.call(@root).map { |p| Pathname(p).relative_path_from(@root).to_s }
    assert_equal %w[acme-api acme-web clients/other-lib], paths
  end

  test "an empty folder fails with a message that says what to do" do
    @scan.update!(root_path: Dir.mktmpdir)
    discover!
    assert_equal "failed", @scan.status
    assert_match "No git repositories were found", @scan.error
  end

  test "identities group by email and pre-tick every one that is the person" do
    discover!
    emails = @scan.candidates.map { |c| c["email"] }

    assert_includes emails, "bob@agency.com"
    assert_equal %w[ada.lovelace@agency.com ada@home.dev], @scan.identities.sort
    assert_equal "identities", @scan.status
  end

  test "someone who merely shares a first name is not pre-ticked" do
    candidate = { "email" => "ada@other.org", "names" => [ "Ada Byron" ] }
    assert_not Knowledge::Identities.likely_mine?(candidate, Profile.current)
  end

  test "inventory counts only their commits and reads the stack, tables and where they worked" do
    inventory!
    api = @scan.repos.find_by(name: "acme-api")

    assert_equal 4, api.total_commits
    assert_equal 3, api.own_commits, "both of Ada's emails count, Bob's commit does not"
    assert_includes api.stack["frameworks"], "Ruby on Rails 7.1"
    assert_includes api.stack["libraries"], "Sidekiq"
    assert_includes api.stack["integrations"], "Stripe"
    assert_includes api.stack["databases"], "PostgreSQL"
    assert_equal %w[invoices tenants], api.tables
    assert_includes api.top_dirs.keys, "app/services"
    assert_not_includes api.top_files, "README.md", "Bob's README edit is not Ada's work"

    web = @scan.repos.find_by(name: "acme-web")
    assert_includes web.stack["frameworks"], "Next.js 14.2"
    assert_includes web.stack["languages"], "TypeScript"
  end

  test "repos that are slices of one product become one project, and repos with none of their commits none" do
    inventory!
    projects = @scan.projects.to_a

    assert_equal 1, projects.size
    acme = projects.first
    assert_equal %w[acme-api acme-web], acme.repos.map(&:name).sort
    assert_equal 4, acme.own_commits
    assert_equal 5, acme.total_commits
    assert acme.included, "a project with their work is pre-ticked"
    assert_equal "curating", @scan.status
  end

  test "stems ignore slice words, versions and case" do
    %w[fast800-api-with-web fast800-app-frontend Fast800_Mobile_v2].each { |n| assert_equal "fast800", Knowledge::Clusterer.stem(n) }
    assert_equal Knowledge::Clusterer.stem("reviews_on_auto_pilot"), Knowledge::Clusterer.stem("reviewson-autopilot")
    assert_equal "api", Knowledge::Clusterer.stem("api")
  end

  test "an unchanged repo is not re-read on rescan" do
    inventory!
    api = @scan.repos.find_by(name: "acme-api")
    api.update_columns(own_commits: 999)

    Knowledge::Inventory.call(api, @scan)
    assert_equal 999, api.reload.own_commits, "same HEAD and identities, so nothing was re-read"

    @scan.update!(identities: [ "ada@home.dev" ])
    Knowledge::Inventory.call(api, @scan)
    assert_equal 2, api.reload.own_commits, "claiming fewer identities re-reads it"
  end

  test "a name, an exclusion and a choice survive a rescan" do
    inventory!
    acme = @scan.projects.first
    acme.update!(name: "Acme Invoicing", included: false, status: "excluded")

    Knowledge::InventoryJob.perform_now(@scan)
    acme.reload
    assert_equal "Acme Invoicing", acme.name
    assert_equal "excluded", acme.status
    assert_equal 1, @scan.projects.count
  end

  test "the evidence is theirs: their commit messages, trivia dropped, nobody else's" do
    inventory!
    evidence = Knowledge::Evidence.call(@scan.projects.first)

    assert_includes evidence, "Add Stripe subscription billing with webhooks"
    assert_includes evidence, "Invoice list with filters and CSV export"
    assert_not_includes evidence, "Bump gems and tidy the readme"
    assert_no_match(/\bwip\b/, evidence)
    assert_includes evidence, "Their commits: 4 of 5"
    assert_includes evidence, "Database tables: invoices, tenants"
  end

  WRITE_UP = <<~YAML
    ```yaml
    name: "Something Else Entirely"
    role: "Lead developer"
    period: "1999"
    one_liner: "Invoicing for plumbers — multi-tenant."
    stack: ["Ruby on Rails 7.1", "Next.js 14"]
    highlights: ["Stripe subscription billing with webhooks"]
    tags: ["Ruby on Rails", "Stripe", "Multi-Tenancy", "invoicing (billing, payments)"]
    relevance: ["payments", "admin-panels-and-internal-dashboards-for-teams"]
    commits: "1000 of 1000"
    open_questions: ["Who was the client?"]
    ```
  YAML

  test "a write-up keeps the confirmed name, the real period and the real count, whatever the model said" do
    inventory!
    acme = @scan.projects.first
    acme.update!(name: "Acme Invoicing")

    with_claude(WRITE_UP) do |calls|
      acme.update!(status: "queued")
      Knowledge::WriteProjectJob.perform_now(acme)

      opts = calls.first[:opts]
      assert_equal acme.repos.first.path, opts[:chdir], "reads inside its own repo"
      assert_equal [ acme.repos.second.path ], opts[:add_dirs]
      assert_includes calls.first[:prompt], "Never invent a client"
    end

    acme.reload
    draft = acme.draft
    assert_equal "drafted", acme.status
    assert_equal "Acme Invoicing", draft["name"]
    assert_equal "2025", draft["period"]
    assert_equal "4 of 5", draft["commits"]
    assert_equal "Invoicing for plumbers - multi-tenant.", draft["one_liner"], "no em dashes"
    assert_equal %w[rails stripe multi-tenant invoicing], draft["tags"]
    assert_equal [ "payments" ], draft["relevance"]
    assert_equal [ "Who was the client?" ], acme.open_questions
  end

  test "a failed write-up says why and can be tried again" do
    inventory!
    acme = @scan.projects.first
    with_claude("no yaml here, just prose: [") do
      acme.update!(status: "queued")
      Knowledge::WriteProjectJob.perform_now(acme)
    end

    assert_equal "failed", acme.reload.status
    assert acme.error.present?
  end

  test "only accepted projects reach the career folder, and unaccepting removes every trace" do
    inventory!
    acme = @scan.projects.first
    with_claude(WRITE_UP) { acme.update!(status: "queued"); Knowledge::WriteProjectJob.perform_now(acme) }

    assert_empty CareerFolder.project_files, "a draft is not published"

    acme.reload.accept!
    assert_equal [ acme.file ], CareerFolder.project_files
    written = YAML.safe_load_file(Radar.career_path.join("projects", acme.file))
    assert_nil written["open_questions"], "questions for the person are not facts for the writer"

    index = YAML.safe_load_file(Radar.career_path.join("projects", "_index.yml"))["projects"]
    assert_equal [ acme.file ], index.map { |e| e["file"] }
    assert_includes CareerData.instance.project_terms, "stripe"

    skills = YAML.safe_load_file(Radar.career_path.join("skills.yml"))
    rails = skills["frameworks"].find { |s| s["name"] == "Ruby on Rails" }
    assert_equal [ "7.1" ], rails["versions"]
    assert_match "4 of your commits", rails["evidence"]
    assert_includes CareerData.instance.skill_terms, "ruby on rails"

    acme.unaccept!
    assert_empty CareerFolder.project_files
    assert_empty YAML.safe_load_file(Radar.career_path.join("projects", "_index.yml"))["projects"]
  end

  test "the skills they typed are kept even with no projects at all" do
    Knowledge::Publisher.call
    skills = YAML.safe_load_file(Radar.career_path.join("skills.yml"))
    assert_equal [ "Rails", "Stripe" ], skills["declared"].map { |s| s["name"] }
    assert_includes CareerData.instance.skill_terms, "stripe"
  end

  test "a write-up stuck in flight goes stale instead of saying writing forever" do
    project = Knowledge::Project.new(name: "x", status: "writing", queued_at: 40.minutes.ago, updated_at: 20.minutes.ago)
    assert project.stale?
    assert_not project.in_flight?
  end

  # The twentieth project in a batch waits behind nineteen others. That wait
  # once counted against it, and a healthy write-up was about to be called stuck.
  test "time spent waiting in line never makes a write-up look stuck" do
    waiting = Knowledge::Project.new(name: "x", status: "queued", queued_at: 45.minutes.ago)
    assert_not waiting.stale?

    started = Knowledge::Project.new(name: "y", status: "writing", queued_at: 45.minutes.ago, updated_at: 5.minutes.ago)
    assert_not started.stale?, "five minutes into writing is normal for a large repository"

    assert Knowledge::Project.new(name: "z", status: "queued", queued_at: 3.hours.ago).stale?, "a queue that never moves means the worker is down"
  end

  test "each write-up in flight says where it is" do
    first = Knowledge::Project.create!(name: "a", stem: "a", status: "queued", queued_at: 3.minutes.ago)
    second = Knowledge::Project.create!(name: "b", stem: "b", status: "queued", queued_at: 1.minute.ago)
    writing = Knowledge::Project.create!(name: "c", stem: "c", status: "writing", queued_at: 9.minutes.ago)
    writing.update_columns(updated_at: 4.minutes.ago)

    assert_equal "Waiting, 1st in line", first.progress_label
    assert_equal "Waiting, 2nd in line", second.progress_label
    assert_equal "Writing, 4 min", writing.progress_label
  end
end
