Rails.application.routes.draw do
  root "job_postings#index"

  resources :job_postings, only: [ :show ], path: "jobs" do
    member do
      post :refresh
      post :generate
      post :regenerate
      post :dismiss
      post :restore
      post :mark_applied
      post :outcome
      post :promote
      patch :template
    end
  end

  get "filtered", to: "job_postings#filtered", as: :filtered
  get "applied",  to: "job_postings#applied",  as: :applied

  # One part of a proposal, rewritten on its own.
  resources :proposal_sections, only: [], path: "parts" do
    member { post :rewrite }
  end

  resources :saved_searches, path: "searches"
  resources :lessons, only: %i[index update destroy] do
    collection { post :teach }
  end
  # Overruling a skipped note: keep it as a rule, verbatim.
  post "notes/:id/keep", to: "lessons#keep", as: :keep_note
  post "poll", to: "polls#create", as: :poll
  post "auto_generate", to: "settings#toggle_auto_generate", as: :toggle_auto_generate
  post "auto_polling", to: "settings#toggle_auto_polling", as: :toggle_auto_polling
  post "native_notifications", to: "settings#toggle_native_notifications", as: :toggle_native_notifications

  get  "oauth/upwork/connect",  to: "oauth/upwork#connect",  as: :upwork_connect
  get  "oauth/upwork/callback", to: "oauth/upwork#callback", as: :upwork_callback

  get "alerts", to: "alerts#index", as: :alerts, defaults: { format: :json }

  get "settings", to: "settings#show", as: :settings

  # The setup wizard. Everything above redirects here until it is finished.
  scope "setup", module: "setup", as: "setup" do
    get "/", to: "steps#index", as: ""
    post "claude/check", to: "claude#check", as: :claude_check
    patch "claude/path", to: "claude#path", as: :claude_path
    patch "claude/model", to: "claude#model", as: :claude_model
    patch "upwork/key", to: "upwork#key", as: :upwork_key
    get "upwork/authorize", to: "upwork#authorize", as: :upwork_authorize
    post "upwork/code", to: "upwork#code", as: :upwork_code
    post "upwork/verify", to: "upwork#verify", as: :upwork_verify
    delete "upwork/connection", to: "upwork#disconnect", as: :upwork_disconnect
    patch "profile", to: "profiles#update", as: :profile

    post "knowledge/scan", to: "knowledge#scan", as: :knowledge_scan
    delete "knowledge/scan", to: "knowledge#restart", as: :knowledge_restart
    post "knowledge/rescan", to: "knowledge#rescan", as: :knowledge_rescan
    patch "knowledge/identities", to: "knowledge#identities", as: :knowledge_identities
    post "knowledge/write", to: "knowledge#write", as: :knowledge_write
    post "knowledge/merge", to: "knowledge#merge", as: :knowledge_merge
    post "knowledge/accept_all", to: "knowledge#accept_all", as: :knowledge_accept_all
    post "knowledge/projects", to: "knowledge#create", as: :knowledge_projects
    patch "knowledge/projects/:id", to: "knowledge#update", as: :knowledge_project
    post "knowledge/projects/:id/toggle", to: "knowledge#toggle", as: :knowledge_toggle
    post "knowledge/projects/:id/exclude", to: "knowledge#exclude", as: :knowledge_exclude
    post "knowledge/projects/:id/restore", to: "knowledge#restore", as: :knowledge_restore
    post "knowledge/projects/:id/split", to: "knowledge#split", as: :knowledge_split
    post "knowledge/projects/:id/accept", to: "knowledge#accept", as: :knowledge_accept
    post "knowledge/projects/:id/unaccept", to: "knowledge#unaccept", as: :knowledge_unaccept
    post "knowledge/projects/:id/rewrite", to: "knowledge#rewrite", as: :knowledge_rewrite

    patch "voice", to: "voices#update", as: :voice

    post "searches/suggest", to: "searches#suggest", as: :searches_suggest
    post "searches", to: "searches#create", as: :searches
    post "searches/preview", to: "searches#preview", as: :searches_preview
    delete "searches/:id", to: "searches#destroy", as: :search

    patch "preferences", to: "preferences#update", as: :preferences

    post "first_proposal/check", to: "first_proposals#check", as: :first_proposal_check
    post "first_proposal/pick/:id", to: "first_proposals#pick", as: :first_proposal_pick
    post "first_proposal/paste", to: "first_proposals#paste", as: :first_proposal_paste
    post "first_proposal/verdict", to: "first_proposals#verdict", as: :first_proposal_verdict

    post ":step/continue", to: "steps#continue", as: :continue
    post ":step/skip", to: "steps#skip", as: :skip
    post ":step/unskip", to: "steps#unskip", as: :unskip
    get ":step", to: "steps#show", as: :step
  end

  get "up" => "rails/health#show", as: :rails_health_check
end
