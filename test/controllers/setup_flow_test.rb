require "test_helper"

# The setup wizard, driven the way a browser drives it. A fresh install has
# nothing: no key, no profile, no searches, and every page must lead back to
# the step the person is on until a proposal they would send exists.
class SetupFlowTest < ActionDispatch::IntegrationTest
  setup do
    Setting.clear(Onboarding::COMPLETED_AT)
    Profile.delete_all
    SavedSearch.delete_all
    Upwork::TokenStore.new.clear!
    reset_career!
  end

  teardown do
    Upwork::TokenStore.new.clear!
    install_career_fixture!
  end

  def finish_through(key)
    Onboarding.steps.each do |s|
      break if s.key == key

      case s.key
      when "welcome", "claude", "preferences" then Onboarding.stamp!(s.key)
      when "upwork_key" then Credential.set_upwork(client_id: "cid", client_secret: "sec", redirect_uri: "https://localhost/cb")
      when "upwork_connect"
        Upwork::TokenStore.new.save!(access_token: "t", refresh_token: "r", expires_at: 1.hour.from_now)
        Onboarding.stamp!("upwork_connect")
      when "profile"
        Profile.first || Profile.create!(full_name: "Ada Lovelace", title: "Rails Developer", country: "United Kingdom",
                                         timezone: "Europe/London", skills: "Rails, Stripe")
      when "knowledge", "voice" then Onboarding.skip!(s.key)
      when "searches" then SavedSearch.find_or_create_by!(name: "Rails") { |s| s.assign_attributes(terms: [ "rails" ], threshold: 70, hot_threshold: 80, active: true) }
      end
    end
  end

  # --- the gate ------------------------------------------------------------

  test "a fresh install sends every page to the first step" do
    get root_path
    assert_redirected_to setup_path
    follow_redirect!
    assert_redirected_to setup_step_path("welcome")

    get settings_path
    assert_redirected_to setup_path
  end

  test "the alerts feed answers JSON rather than an HTML redirect" do
    get alerts_path(format: :json)
    assert_response :conflict
  end

  test "a step past the current one cannot be reached" do
    get setup_step_path("searches")
    assert_redirected_to setup_step_path("welcome")
  end

  test "every step page renders at every point of setup" do
    Onboarding.steps.each do |s|
      finish_through(s.key)
      get setup_step_path(s.key)
      assert_response :success, "#{s.key} did not render"
      assert_select "h1", s.title
    end
  end

  # --- moving through ------------------------------------------------------

  test "welcome moves on to Claude" do
    post setup_continue_path("welcome")
    assert_redirected_to setup_step_path("claude")
    assert Onboarding.done?("welcome")
  end

  test "a required step cannot be skipped and says why" do
    finish_through("profile")
    post setup_skip_path("profile")
    assert_redirected_to setup_step_path("profile")
    assert_match "required", flash[:alert]
  end

  test "an optional step shows what skipping costs before it can be skipped" do
    finish_through("knowledge")
    get setup_step_path("knowledge")
    assert_select "[data-reveal-target=panel][hidden]" do
      assert_select "p", text: /Proposals can only cite your profile/
    end

    post setup_skip_path("knowledge")
    assert_redirected_to setup_step_path("voice")
    assert Onboarding.skipped?("knowledge")
  end

  test "continue refuses a step that is not finished" do
    finish_through("searches")
    post setup_continue_path("searches")
    assert_redirected_to setup_step_path("searches")
    assert_match "not finished", flash[:alert]
  end

  # --- Claude --------------------------------------------------------------

  test "a working Claude moves on, a missing one says how to install it" do
    finish_through("claude")

    Setting.set(Setting::CLAUDE_PATH, "/definitely/not/here/claude")
    post setup_claude_check_path
    assert_redirected_to setup_step_path("claude")
    follow_redirect!
    assert_match "npm install -g @anthropic-ai/claude-code", response.body
    assert_not Onboarding.done?("claude")

    Setting.clear(Setting::CLAUDE_PATH)
    original = ClaudeCheck.method(:call)
    ClaudeCheck.define_singleton_method(:call) { ClaudeCheck::Result.new(installed: true, version: "2.1", signed_in: true, model_ok: true) }
    post setup_claude_check_path
    assert_redirected_to setup_step_path("upwork_key")
    assert Onboarding.done?("claude")
  ensure
    ClaudeCheck.define_singleton_method(:call, original) if original
  end

  test "a plan that cannot use the pinned model can write with its default" do
    finish_through("claude")
    patch setup_claude_model_path, params: { model: "default" }
    assert_nil Radar.writer_model

    patch setup_claude_model_path, params: { model: "pinned" }
    assert_equal Radar::DEFAULT_WRITER_MODEL, Radar.writer_model
  end

  # --- Upwork --------------------------------------------------------------

  test "the key form insists on every field and on https" do
    finish_through("upwork_key")

    patch setup_upwork_key_path, params: { upwork: { client_id: "", client_secret: "", redirect_uri: "https://x.test/cb" } }
    assert_match "Client ID and the Client Secret", flash[:alert]

    patch setup_upwork_key_path, params: { upwork: { client_id: "a", client_secret: "b", redirect_uri: "http://localhost/cb" } }
    assert_match "https://", flash[:alert]
    assert_not Upwork::Client.configured?
  end

  test "a saved key is encrypted, never shown again, and kept when the secret is left blank" do
    finish_through("upwork_key")
    patch setup_upwork_key_path, params: { upwork: { client_id: "client-123", client_secret: "very-secret-value", redirect_uri: "https://x.test/cb" } }
    assert_redirected_to setup_step_path("upwork_connect")

    get setup_step_path("upwork_key")
    assert_no_match "very-secret-value", response.body
    assert_match "very••••alue", response.body

    patch setup_upwork_key_path, params: { upwork: { client_id: "client-123", client_secret: "", redirect_uri: "https://x.test/cb" } }
    assert_equal "very-secret-value", Credential.get("upwork.client_secret")
  end

  test "a different key drops the old key's sign-in" do
    finish_through("profile")
    assert Upwork::TokenStore.new.connected?

    patch setup_upwork_key_path, params: { upwork: { client_id: "another-key", client_secret: "s", redirect_uri: "https://x.test/cb" } }
    assert_not Upwork::TokenStore.new.connected?
    assert_not Onboarding.done?("upwork_connect")
  end

  test "pasting the address Upwork sent back connects, and junk is refused plainly" do
    finish_through("upwork_connect")

    post setup_upwork_code_path, params: { callback: "no code in here" }
    assert_match "does not contain a code", flash[:alert]

    exchanged = nil
    Upwork::Client.class_eval do
      alias_method :__exchange, :exchange_code
      define_method(:exchange_code) { |code| exchanged = code; @store.save!(access_token: "a", refresh_token: "r", expires_at: 1.hour.from_now) }
    end
    original = UpworkProbe.method(:call)
    UpworkProbe.define_singleton_method(:call) { |*| UpworkProbe::Result.new(ok: true, total: 42, titles: [ "Rails dev" ]) }

    post setup_upwork_code_path, params: { callback: "https://localhost/cb?code=abc123&state=x" }
    assert_equal "abc123", exchanged
    assert_redirected_to setup_step_path("profile")
    assert Onboarding.done?("upwork_connect")
  ensure
    Upwork::Client.class_eval { alias_method :exchange_code, :__exchange; remove_method :__exchange } if Upwork::Client.method_defined?(:__exchange)
    UpworkProbe.define_singleton_method(:call, original) if original
  end

  test "Upwork's token errors are explained, not dumped" do
    assert_match "does not recognise this Key", Upwork::TokenError.explain(%(Token request failed: 400 {"error_description":"Invalid client_id parameter value","error":"invalid_request"}))
    assert_match "expired or was already used", Upwork::TokenError.explain(%(400 {"error":"invalid_grant","error_description":"code expired"}))
    assert_match "Callback URL", Upwork::TokenError.explain(%(400 {"error_description":"redirect_uri mismatch"}))
  end

  # --- profile -------------------------------------------------------------

  test "an incomplete profile shows each problem beside its field" do
    finish_through("profile")
    patch setup_profile_path, params: { profile: { full_name: "Ada Lovelace", skills: "Rails", timezone: "Mars/Base" } }

    assert_response :unprocessable_entity
    assert_select ".field-error", text: /Title is needed/
    assert_select ".field-error", text: /Skills needs at least two/
    assert_select ".field-error", text: /Timezone is not a timezone/
    assert_select "input[value=?]", "Ada Lovelace", 1, "what they typed survives"
  end

  test "a complete profile writes the career folder and scores against its skills straight away" do
    finish_through("profile")
    patch setup_profile_path, params: { profile: { full_name: "Ada Lovelace", title: "Rails Developer", country: "United Kingdom",
                                                   timezone: "Europe/London", skills: "Ruby on Rails, Stripe, Hotwire" } }
    assert_redirected_to setup_step_path("knowledge")

    %w[CLAUDE.md profile.yml writing-voice.md skills.yml templates/_index.yml].each do |f|
      assert Radar.career_path.join(f).exist?, "#{f} was not written"
    end
    assert_includes CareerData.instance.skill_terms, "stripe"
  end

  # --- knowledge -----------------------------------------------------------

  test "a folder that does not exist is refused before anything runs" do
    finish_through("knowledge")
    assert_no_enqueued_jobs do
      post setup_knowledge_scan_path, params: { root_path: "/no/such/folder" }
    end
    assert_match "is not a folder", flash[:alert]
  end

  test "choosing a folder starts discovery, and the page shows the scan" do
    finish_through("knowledge")
    folder = Dir.mktmpdir
    assert_enqueued_with(job: Knowledge::DiscoverJob) do
      post setup_knowledge_scan_path, params: { root_path: folder }
    end
    get setup_step_path("knowledge")
    assert_select ".scope"
  ensure
    FileUtils.rm_rf(folder)
  end

  test "identities must include at least one, and claiming them starts the inventory" do
    finish_through("knowledge")
    scan = Knowledge::Scan.create!(root_path: Dir.home, status: "identities",
                                   candidates: [ { "email" => "ada@x.dev", "names" => [ "Ada Lovelace" ], "commits" => 9, "repos" => 1 },
                                                 { "email" => "bob@x.dev", "names" => [ "Bob Builder" ], "commits" => 5, "repos" => 1 } ])

    patch setup_knowledge_identities_path, params: { emails: [] }
    assert_match "Tick at least one", flash[:alert]

    assert_enqueued_with(job: Knowledge::InventoryJob) do
      patch setup_knowledge_identities_path, params: { emails: [ "ada@x.dev" ] }
    end
    scan.reload
    assert_equal [ "ada@x.dev" ], scan.identities
    assert_equal [ "Ada Lovelace" ], scan.names
  end

  test "choosing, renaming, merging, writing up and accepting projects" do
    finish_through("knowledge")
    scan = Knowledge::Scan.create!(root_path: Dir.home, status: "curating")
    a = scan.projects.create!(name: "Acme Api", stem: "acme", own_commits: 50, total_commits: 60, included: true)
    b = scan.projects.create!(name: "Acme Web", stem: "acmeweb", own_commits: 20, total_commits: 20, included: false)
    scan.repos.create!(path: "/tmp/acme-api", name: "acme-api", own_commits: 50, project: a)
    scan.repos.create!(path: "/tmp/acme-web", name: "acme-web", own_commits: 20, project: b)

    post setup_knowledge_toggle_path(b)
    assert b.reload.included

    patch setup_knowledge_project_path(a), params: { project: { name: "Acme Invoicing", client: "Acme Ltd" } }
    assert_equal "Acme Invoicing", a.reload.name
    assert_equal "Acme Ltd", a.client

    post setup_knowledge_merge_path, params: { ids: [ a.id, b.id ] }
    assert_not Knowledge::Project.exists?(b.id)
    assert_equal %w[acme-api acme-web], a.reload.repos.map(&:name).sort

    assert_enqueued_with(job: Knowledge::WriteProjectJob) { post setup_knowledge_write_path }
    assert_equal "queued", a.reload.status

    a.update!(status: "drafted", draft_yaml: { "name" => "Acme Invoicing", "one_liner" => "Invoices", "tags" => [ "rails" ] }.to_yaml)
    get setup_step_path("knowledge")
    assert_select "article#project-#{a.id}"

    post setup_knowledge_accept_path(a)
    assert_equal "accepted", a.reload.status
    assert Radar.career_path.join("projects", "acme-invoicing.yml").exist?
    assert Onboarding.done?("knowledge")
  end

  test "choosing a different folder forgets the old one but keeps what was accepted" do
    finish_through("knowledge")
    scan = Knowledge::Scan.create!(root_path: Dir.home, status: "curating")
    kept = scan.projects.create!(name: "Kept", stem: "kept", status: "accepted", accepted_at: Time.current,
                                 draft_yaml: { "name" => "Kept", "tags" => [ "rails" ] }.to_yaml)
    dropped = scan.projects.create!(name: "Dropped", stem: "dropped")
    Knowledge::Publisher.call

    delete setup_knowledge_restart_path
    assert_not Knowledge::Scan.exists?(scan.id)
    assert_not Knowledge::Project.exists?(dropped.id)
    assert Knowledge::Project.exists?(kept.id)
    assert Radar.career_path.join("projects", "kept.yml").exist?

    patch setup_knowledge_project_path(kept), params: { project: { client: "Acme" } }
    assert_equal "Acme", kept.reload.client, "a project with no scan is still editable"
  end

  test "an accepted project can be edited, and the career folder follows" do
    finish_through("knowledge")
    project = Knowledge::Project.create!(name: "Acme Api", stem: "acme", status: "accepted", accepted_at: Time.current,
                                         draft_yaml: { "name" => "Acme Api", "one_liner" => "Invoices", "tags" => [ "rails" ] }.to_yaml)
    Knowledge::Publisher.call
    assert Radar.career_path.join("projects", "acme-api.yml").exist?

    get setup_step_path("knowledge")
    assert_select "#project-#{project.id} button", text: /Edit/
    assert_select "#project-#{project.id} textarea[name=?]", "project[draft_yaml]"

    patch setup_knowledge_project_path(project), params: { project: { name: "Acme Invoicing", client: "Acme Ltd", url: "",
                                                                      draft_yaml: project.draft_yaml } }
    project.reload
    assert_equal "accepted", project.status, "editing never takes it out of the career folder"
    written = YAML.safe_load_file(Radar.career_path.join("projects", "acme-invoicing.yml"))
    assert_equal "Acme Invoicing", written["name"]
    assert_equal "Acme Ltd", written["client"], "the client field reaches the file proposals read"
    assert_not Radar.career_path.join("projects", "acme-api.yml").exist?, "the old file goes with the old name"
    index = YAML.safe_load_file(Radar.career_path.join("projects", "_index.yml"))["projects"]
    assert_equal [ "Acme Invoicing" ], index.map { |e| e["name"] }
  end

  test "a change made inside the write-up wins when the fields were left alone" do
    finish_through("knowledge")
    project = Knowledge::Project.create!(name: "Acme", stem: "acme", status: "drafted", client: "Old Co",
                                         draft_yaml: { "name" => "Acme", "client" => "Old Co" }.to_yaml)
    edited = { "name" => "Acme Portal", "client" => "New Co", "one_liner" => "Better" }.to_yaml
    patch setup_knowledge_project_path(project), params: { project: { name: "Acme", client: "Old Co", draft_yaml: edited } }

    project.reload
    assert_equal "Acme Portal", project.name
    assert_equal "New Co", project.client
    assert_equal "Better", project.draft["one_liner"]
  end

  test "a write-up edited as YAML is checked before it is saved" do
    finish_through("knowledge")
    project = Knowledge::Project.create!(name: "Thing", stem: "thing", status: "drafted", draft_yaml: "name: Thing\n")
    patch setup_knowledge_project_path(project), params: { project: { draft_yaml: "name: [unclosed" } }
    assert_match "not valid YAML", flash[:alert]
    assert_equal "name: Thing\n", project.reload.draft_yaml
  end

  test "work that is not on this computer can be added by hand" do
    finish_through("knowledge")
    post setup_knowledge_projects_path, params: { project: { name: "Client Portal", client: "Acme", stack: "Rails, Stripe",
                                                             highlights: "- Moved billing to Stripe\n- Cut page loads in half" } }
    written = YAML.safe_load_file(Radar.career_path.join("projects", "client-portal.yml"))
    assert_equal [ "Moved billing to Stripe", "Cut page loads in half" ], written["highlights"]
    assert_includes CareerData.instance.project_terms, "stripe"
  end

  # --- voice, searches, preferences ---------------------------------------

  test "voice samples land in the file the writer reads" do
    finish_through("voice")
    patch setup_voice_path, params: { voice: { winning_opening: "Ledgerline is my billing SaaS.", samples: [ "Shipped it.", "" ], signature: "Ada" } }
    assert_redirected_to setup_step_path("searches")
    assert_includes Radar.career_path.join("writing-voice.md").read, "> Ledgerline is my billing SaaS."
    assert_equal "Ada", Profile.current.signature
  end

  test "saving nothing on the voice step asks for a sample or a skip" do
    finish_through("voice")
    patch setup_voice_path, params: { voice: { winning_opening: "", samples: [ "" ] } }
    assert_match "or skip this step", flash[:alert]
  end

  test "a search is added from the form, and removed" do
    finish_through("searches")
    SavedSearch.delete_all
    post setup_searches_path, params: { search: { name: "Rails", terms_text: "rails developer, hotwire", threshold: 72,
                                                  hot_threshold: 82, auto_generate: "1", excluded_keywords_text: "WordPress" } }
    search = SavedSearch.find_by!(name: "Rails")
    assert_equal [ "rails developer", "hotwire" ], search.terms
    assert_equal [ "wordpress" ], search.excluded_keywords
    assert search.auto_generate
    assert Onboarding.done?("searches")

    delete setup_search_path(search)
    assert_not SavedSearch.exists?(search.id)
  end

  test "a preview before Upwork is connected says so instead of failing" do
    finish_through("searches")
    Upwork::TokenStore.new.clear!
    post setup_searches_preview_path(frame: "preview-x"), params: { search: { name: "R", terms_text: "rails" } }
    assert_select "turbo-frame#preview-x", text: /Connect Upwork first/
  end

  test "suggestions are parsed into clean, bounded searches" do
    items = SearchSuggester.parse(<<~JSON)
      [{"name": "Rails", "terms": ["Rails Developer", "\\"hotwire\\"", ""], "threshold": 40, "hot_threshold": 20,
        "auto_generate": true, "template_name": "made-up", "excluded_keywords": ["WordPress"], "reason": "Built on X"},
       {"name": "", "terms": ["x"]}, {"name": "Empty", "terms": []}]
    JSON
    assert_equal 1, items.size
    s = items.first
    assert_equal [ "rails developer", "hotwire" ], s.terms
    assert_equal 50, s.threshold, "clamped to a sane floor"
    assert_equal 50, s.hot_threshold, "never below the inbox threshold"
    assert_equal "personalised-skills-for-job", s.template_name, "an unknown template falls back to a real one"
    assert_equal [ "wordpress" ], s.excluded_keywords
  end

  test "preferences set the cap, the hours across midnight, and the switches" do
    finish_through("preferences")
    patch setup_preferences_path, params: { preferences: { auto_generate: "0", daily_cap: "9", active_from: "8", active_to: "1", native_notifications: "1" } }
    assert_equal 9, Radar.daily_generation_cap
    assert_equal 8..25, Radar.active_hours
    assert_not Setting.auto_generate?
    assert Setting.native_notifications?
  end

  # --- the first proposal ------------------------------------------------

  test "a pasted job is written up without calling Upwork" do
    finish_through("first_proposal")
    assert_enqueued_with(job: GenerateProposalJob) do
      post setup_first_proposal_paste_path, params: { title: "Rails dev for billing", description: "We need " + ("billing work " * 20),
                                                      questions: "How would you start?\n" }
    end
    posting = JobPosting.find(Setting.get("setup.first_posting_id"))
    assert posting.upwork_id.start_with?("pasted-")
    assert posting.detail_fetched_at.present?, "the Upwork detail fetch is skipped for a pasted job"
    assert_equal [ "How would you start?" ], posting.screening_questions
  end

  test "a job too short to write for is refused" do
    finish_through("first_proposal")
    post setup_first_proposal_paste_path, params: { title: "x", description: "short" }
    assert_match "full description", flash[:alert]
  end

  test "saying no rewrites it with the note, saying yes finishes setup" do
    finish_through("first_proposal")
    posting = JobPosting.create!(upwork_id: "p1", title: "Rails dev", description: "d", status: "matched")
    posting.proposals.create!(version: 1, body: "A draft", generated_at: Time.current)
    Setting.set("setup.first_posting_id", posting.id)

    post setup_first_proposal_verdict_path, params: { send: "no", feedback: "" }
    assert_match "Say what is wrong", flash[:alert]

    assert_enqueued_with(job: GenerateProposalJob) do
      post setup_first_proposal_verdict_path, params: { send: "no", feedback: "Too long.", remember: "1" }
    end
    assert Feedback.find_by(body: "Too long.").remembered

    posting.update_columns(generation_queued_at: nil)
    post setup_first_proposal_verdict_path, params: { send: "yes" }
    assert_redirected_to job_posting_path(posting)
    assert Onboarding.complete?

    get root_path
    assert_response :success
  end

  test "checking again forgets the job that was picked" do
    finish_through("first_proposal")
    Setting.set("setup.first_posting_id", 99)
    assert_enqueued_with(job: PollAllSearchesJob) { post setup_first_proposal_check_path }
    assert_nil Setting.get("setup.first_posting_id")
  end

  # --- after setup ---------------------------------------------------------

  test "nothing is polled or auto-written until setup is finished" do
    SavedSearch.create!(name: "Rails", terms: [ "rails" ], threshold: 70, hot_threshold: 70, auto_generate: true, active: true)
    polled = false
    original = PollAllSearchesJob.instance_method(:perform)
    PollAllSearchesJob.define_method(:perform) { |**| polled = true }
    PollTickJob.perform_now
    assert_not polled
  ensure
    PollAllSearchesJob.define_method(:perform, original)
  end

  test "a finished install can revisit any step from Settings" do
    finish_through("first_proposal")
    Onboarding.complete!
    get settings_path
    assert_response :success
    assert_select "a[href=?]", setup_step_path("profile")

    get setup_step_path("profile")
    assert_response :success
    assert_select "a[href=?]", settings_path
  end
end
