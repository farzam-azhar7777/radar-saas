module Setup
  class StepsController < BaseController
    before_action :set_step, except: :index

    def index
      target = Onboarding.complete? ? Onboarding.steps.first : Onboarding.current || Onboarding.steps.last
      redirect_to setup_step_path(target.key)
    end

    def show
      return redirect_to setup_step_path(Onboarding.current.key) unless Onboarding.reachable?(@step.key)

      send("load_#{@step.key}") if respond_to?("load_#{@step.key}", true)
      render :show
    end

    # Steps with nothing to fill in (welcome), or whose work is already saved,
    # move on from here.
    def continue
      case @step.key
      when "welcome" then Onboarding.stamp!("welcome")
      else
        return go_to(@step.key, alert: "This step is not finished yet.") unless Onboarding.done?(@step.key)
      end
      advance_from(@step.key)
    end

    def skip
      return go_to(@step.key, alert: "#{@step.rail} is required. #{@step.why}") if @step.required?

      Onboarding.skip!(@step.key)
      advance_from(@step.key, notice: "Skipped #{@step.rail.downcase}. You can come back to it from Settings.")
    end

    def unskip
      Onboarding.unskip!(@step.key)
      go_to(@step.key)
    end

    private

    def set_step
      @step = Onboarding.find(params[:step]) or raise ActionController::RoutingError, "No such setup step"
    end

    def load_claude
      @claude_command = ClaudeRun.command
      @writer_model = Radar.writer_model
    end

    def load_upwork_key
      @saved = Credential.upwork
    end

    def load_upwork_connect
      @connected = Upwork::TokenStore.new.connected?
      @redirect_uri = Credential.get("upwork.redirect_uri")
    end

    def load_profile
      @profile = Profile.current
    end

    def load_knowledge
      @scan = Knowledge::Scan.current
      return unless @scan

      @projects = @scan.projects.includes(:repos).ranked
      @accepted = Knowledge::Project.accepted.count
    end

    def load_voice
      @profile = Profile.current
    end

    def load_searches
      @searches = SavedSearch.ordered
      @suggestions = SearchSuggester.items
      @suggest_state = SearchSuggester.state
      @presets = SearchSuggester.presets
      @taken = @searches.map { |s| s.name.downcase }
    end

    def load_preferences
      @auto = Setting.auto_generate?
      @cap = Radar.daily_generation_cap
      @hours = Radar.active_hours
    end

    def load_first_proposal
      @posting = JobPosting.find_by(id: Setting.get("setup.first_posting_id"))
      @candidates = JobPosting.inbox.includes(:saved_search).order(score: :desc).limit(8) unless @posting
      @checked = Setting.get("setup.first_check_at").present?
    end
  end
end
