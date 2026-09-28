# Where the person is in setup, and what each step is for.
#
# Every step says why it matters. A required step says why it cannot be
# skipped. A skippable one says exactly what is lost before it lets anyone skip
# it. Nothing is hidden behind the wizard afterwards: every step can be
# revisited from Settings.
module Onboarding
  Step = Struct.new(:key, :title, :rail, :required, :why, :skip_cost, keyword_init: true) do
    def required? = required
    def skippable? = !required
  end

  STEPS = [
    Step.new(key: "welcome", rail: "Welcome", required: true,
             title: "Radar finds the Upwork jobs worth your time, and has the proposal ready",
             why: "About fifteen minutes to set up. Most of it is Radar reading your work while you do something else."),
    Step.new(key: "claude", rail: "Claude Code", required: true,
             title: "Connect Claude Code",
             why: "Radar writes every proposal by running Claude Code on this computer, signed in to your own Claude account. " \
                  "Without it, nothing can be written."),
    Step.new(key: "upwork_key", rail: "Upwork API key", required: true,
             title: "Add your Upwork API key",
             why: "Radar reads jobs through Upwork's official API, with a key issued to you. It is the only way to find jobs " \
                  "without scraping, which Upwork prohibits."),
    Step.new(key: "upwork_connect", rail: "Connect Upwork", required: true,
             title: "Connect your Upwork account",
             why: "The key identifies the app. This step lets it read jobs as you. Radar can only ever read: it cannot " \
                  "submit a proposal, send a message or spend a Connect."),
    Step.new(key: "profile", rail: "Your profile", required: true,
             title: "Tell Radar who is pitching",
             why: "Every proposal is signed as you, quotes your rate and availability, and scores jobs against your skills."),
    Step.new(key: "knowledge", rail: "Your work", required: false,
             title: "Show Radar what you have built",
             why: "Proposals win on one concrete detail from real work. Radar reads your own repositories, works out which " \
                  "commits are yours, and writes up the projects you choose.",
             skip_cost: "Proposals can only cite your profile, so they will read like everyone else's. Job matching also " \
                        "loses your project tags, so fewer of the right jobs reach your inbox. You can do this later from Settings."),
    Step.new(key: "voice", rail: "Your voice", required: false,
             title: "Show Radar how you write",
             why: "A proposal that sounds like you gets replies. Paste something you wrote and Radar matches it.",
             skip_cost: "Proposals will be clear and correct but anonymous: nobody reading them will hear you. " \
                        "You can add samples later from Settings."),
    Step.new(key: "searches", rail: "Searches", required: true,
             title: "Choose what to watch for",
             why: "Searches decide which jobs Radar pulls from Upwork and which ones get a proposal written straight away. " \
                  "Radar needs at least one to do anything."),
    Step.new(key: "preferences", rail: "Preferences", required: false,
             title: "Set how Radar works for you",
             why: "When to check more often, how many proposals to write a day, and how to tell you.",
             skip_cost: "Radar uses sensible defaults: checks every few minutes from 7am to 1am your time, writes up to " \
                        "15 proposals a day, and alerts in the browser. You can change any of it later."),
    Step.new(key: "first_proposal", rail: "First proposal", required: true,
             title: "Write your first proposal",
             why: "Setup is finished when Radar has written a proposal you would actually send. If it has not, this is " \
                  "where you tell it what is wrong.")
  ].freeze

  KEYS = STEPS.map(&:key).freeze
  SKIPPED = "setup.skipped".freeze
  COMPLETED_AT = "setup.completed_at".freeze

  module_function

  def steps = STEPS

  def find(key) = STEPS.find { |s| s.key == key.to_s }

  def index(key) = KEYS.index(key.to_s)

  def number(key) = index(key).to_i + 1

  def complete? = Setting.get(COMPLETED_AT).present?

  def complete!
    Setting.set(COMPLETED_AT, Time.current.iso8601)
  end

  # A mark on a step: done, skipped, current, or waiting.
  def status(key)
    return :done if done?(key)
    return :skipped if skipped?(key)
    return :current if key.to_s == current&.key

    :waiting
  end

  def done?(key)
    case key.to_s
    when "welcome" then stamped?("welcome")
    when "claude" then stamped?("claude")
    when "upwork_key" then Upwork::Client.configured?
    when "upwork_connect" then Upwork::Client.configured? && Upwork::TokenStore.new.connected? && stamped?("upwork_connect")
    when "profile" then Profile.current.persisted? && Profile.current.complete?
    when "knowledge" then Knowledge::Project.accepted.exists?
    when "voice" then Profile.current.samples.any? || Profile.current.winning_opening.present?
    when "searches" then SavedSearch.active.exists?
    when "preferences" then stamped?("preferences")
    when "first_proposal" then stamped?("first_proposal")
    else false
    end
  end

  def skipped?(key) = !done?(key) && skipped_keys.include?(key.to_s)

  def resolved?(key) = done?(key) || skipped?(key)

  def skipped_keys = JSON.parse(Setting.get(SKIPPED, "[]")) rescue []

  def skip!(key)
    step = find(key)
    raise ArgumentError, "#{key} cannot be skipped" unless step&.skippable?

    Setting.set(SKIPPED, (skipped_keys | [ step.key ]).to_json)
  end

  def unskip!(key)
    Setting.set(SKIPPED, (skipped_keys - [ key.to_s ]).to_json)
  end

  def stamp!(key) = Setting.set("setup.#{key}_at", Time.current.iso8601)
  def stamped?(key) = Setting.get("setup.#{key}_at").present?
  def unstamp!(key) = Setting.clear("setup.#{key}_at")

  # The first step that is neither done nor skipped.
  def current = STEPS.find { |s| !resolved?(s.key) }

  # Steps are taken in order: everything up to the current one can be visited,
  # nothing past it, because each needs what came before (the scan needs
  # Claude, suggested searches need the scan, the first proposal needs all).
  def reachable?(key)
    return true if complete?

    at = current
    at.nil? || index(key) <= index(at.key)
  end

  def next_after(key) = STEPS[index(key).to_i + 1]
  def previous_before(key) = (i = index(key).to_i).zero? ? nil : STEPS[i - 1]

  def progress
    (STEPS.count { |s| resolved?(s.key) } * 100.0 / STEPS.size).round
  end
end
