# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_09_25_110100) do
  create_table "api_usages", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.date "on", null: false
    t.integer "requests", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["on"], name: "index_api_usages_on_on", unique: true
  end

  create_table "credentials", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "key", null: false
    t.datetime "updated_at", null: false
    t.text "value"
    t.index ["key"], name: "index_credentials_on_key", unique: true
  end

  create_table "feedbacks", force: :cascade do |t|
    t.text "body", null: false
    t.datetime "created_at", null: false
    t.integer "job_posting_id"
    t.integer "lesson_id"
    t.string "outcome"
    t.text "outcome_note"
    t.integer "proposal_id"
    t.boolean "remembered", default: false, null: false
    t.integer "saved_search_id"
    t.datetime "updated_at", null: false
    t.index ["job_posting_id"], name: "index_feedbacks_on_job_posting_id"
    t.index ["lesson_id"], name: "index_feedbacks_on_lesson_id"
    t.index ["proposal_id"], name: "index_feedbacks_on_proposal_id"
    t.index ["saved_search_id"], name: "index_feedbacks_on_saved_search_id"
  end

  create_table "job_postings", force: :cascade do |t|
    t.boolean "already_applied", default: false, null: false
    t.integer "applicants_at_discovery"
    t.datetime "applied_at"
    t.string "category"
    t.string "ciphertext"
    t.string "client_city"
    t.string "client_country"
    t.boolean "client_financial_privacy"
    t.string "client_last_contract_title"
    t.boolean "client_payment_verified"
    t.decimal "client_rating", precision: 3, scale: 2
    t.string "client_timezone"
    t.integer "client_total_hires"
    t.integer "client_total_posted_jobs"
    t.integer "client_total_reviews"
    t.decimal "client_total_spent", precision: 12, scale: 2
    t.string "contract_type"
    t.boolean "cover_letter_required"
    t.datetime "created_at", null: false
    t.text "description"
    t.datetime "detail_fetched_at"
    t.string "duration_label"
    t.string "engagement"
    t.boolean "enterprise", default: false, null: false
    t.string "experience_level"
    t.decimal "fixed_amount", precision: 12, scale: 2
    t.integer "freelancers_to_hire"
    t.text "generation_error"
    t.datetime "generation_queued_at"
    t.decimal "hourly_max", precision: 10, scale: 2
    t.decimal "hourly_min", precision: 10, scale: 2
    t.string "job_url"
    t.datetime "notified_at"
    t.string "outcome"
    t.datetime "outcome_at"
    t.boolean "preferred_location_mandatory", default: false, null: false
    t.json "preferred_locations", default: []
    t.boolean "premium", default: false, null: false
    t.datetime "published_at"
    t.string "rate_proposed"
    t.json "raw_payload", default: {}
    t.datetime "refreshed_at"
    t.integer "saved_search_id"
    t.integer "score"
    t.json "score_reasons", default: []
    t.json "screening_questions", default: []
    t.json "skills", default: []
    t.string "status", default: "new", null: false
    t.string "subcategory"
    t.string "title", null: false
    t.integer "total_applicants"
    t.datetime "updated_at", null: false
    t.string "upwork_id", null: false
    t.index ["notified_at"], name: "index_job_postings_on_notified_at"
    t.index ["outcome"], name: "index_job_postings_on_outcome"
    t.index ["saved_search_id"], name: "index_job_postings_on_saved_search_id"
    t.index ["status", "published_at"], name: "index_job_postings_on_status_and_published_at"
    t.index ["upwork_id"], name: "index_job_postings_on_upwork_id", unique: true
  end

  create_table "knowledge_projects", force: :cascade do |t|
    t.datetime "accepted_at"
    t.string "client"
    t.datetime "created_at", null: false
    t.text "draft_yaml"
    t.datetime "drafted_at"
    t.text "error"
    t.datetime "first_at"
    t.boolean "included", default: false, null: false
    t.integer "knowledge_scan_id"
    t.datetime "last_at"
    t.boolean "manual", default: false, null: false
    t.json "meta", default: {}
    t.string "name", null: false
    t.text "note"
    t.json "open_questions", default: []
    t.integer "own_commits", default: 0
    t.integer "own_commits_when_written"
    t.integer "position"
    t.datetime "queued_at"
    t.float "rank_score", default: 0.0
    t.string "slug"
    t.string "status", default: "candidate", null: false
    t.string "stem"
    t.integer "total_commits", default: 0
    t.datetime "updated_at", null: false
    t.string "url"
    t.index ["knowledge_scan_id", "stem"], name: "index_knowledge_projects_on_knowledge_scan_id_and_stem"
    t.index ["knowledge_scan_id"], name: "index_knowledge_projects_on_knowledge_scan_id"
    t.index ["status"], name: "index_knowledge_projects_on_status"
  end

  create_table "knowledge_repos", force: :cascade do |t|
    t.integer "active_months", default: 0
    t.datetime "created_at", null: false
    t.text "error"
    t.integer "file_count", default: 0
    t.datetime "first_at"
    t.datetime "first_own_at"
    t.string "head_sha"
    t.string "inventory_key"
    t.integer "knowledge_project_id"
    t.integer "knowledge_scan_id", null: false
    t.datetime "last_at"
    t.datetime "last_own_at"
    t.integer "lines_added", default: 0
    t.integer "lines_removed", default: 0
    t.string "name", null: false
    t.integer "own_commits", default: 0
    t.string "path", null: false
    t.text "readme_head"
    t.string "remote_url"
    t.json "stack", default: {}
    t.json "tables", default: []
    t.json "top_dirs", default: {}
    t.json "top_files", default: []
    t.integer "total_commits", default: 0
    t.datetime "updated_at", null: false
    t.index ["knowledge_project_id"], name: "index_knowledge_repos_on_knowledge_project_id"
    t.index ["knowledge_scan_id", "path"], name: "index_knowledge_repos_on_knowledge_scan_id_and_path", unique: true
    t.index ["knowledge_scan_id"], name: "index_knowledge_repos_on_knowledge_scan_id"
  end

  create_table "knowledge_scans", force: :cascade do |t|
    t.json "candidates", default: []
    t.datetime "created_at", null: false
    t.text "error"
    t.json "identities", default: []
    t.datetime "inventoried_at"
    t.json "names", default: []
    t.integer "progress_done", default: 0
    t.string "progress_label"
    t.integer "progress_total", default: 0
    t.string "root_path", null: false
    t.string "status", default: "discovering", null: false
    t.datetime "updated_at", null: false
  end

  create_table "lessons", force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.string "archetype"
    t.text "body", null: false
    t.datetime "created_at", null: false
    t.integer "saved_search_id"
    t.text "source_feedback"
    t.integer "times_used", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["active"], name: "index_lessons_on_active"
    t.index ["archetype"], name: "index_lessons_on_archetype"
    t.index ["saved_search_id"], name: "index_lessons_on_saved_search_id"
  end

  create_table "profiles", force: :cascade do |t|
    t.string "availability"
    t.string "city"
    t.string "country"
    t.datetime "created_at", null: false
    t.text "credentials_line"
    t.string "email"
    t.string "full_name"
    t.text "github_note"
    t.string "github_url"
    t.decimal "hourly_rate", precision: 8, scale: 2
    t.integer "hours_per_week"
    t.text "languages"
    t.string "linkedin_url"
    t.string "portfolio_url"
    t.string "preferred_name"
    t.string "response_time"
    t.text "signature"
    t.text "skills"
    t.text "summary"
    t.string "timezone"
    t.string "title"
    t.datetime "updated_at", null: false
    t.string "upwork_url"
    t.json "voice_samples", default: []
    t.string "website_url"
    t.text "winning_opening"
    t.string "winning_opening_context"
    t.integer "years_experience"
  end

  create_table "proposal_sections", force: :cascade do |t|
    t.text "body", default: "", null: false
    t.datetime "created_at", null: false
    t.string "label", null: false
    t.integer "position", default: 0, null: false
    t.integer "proposal_id", null: false
    t.integer "rewrite_duration_ms"
    t.text "rewrite_feedback"
    t.json "rewrite_meta", default: {}
    t.datetime "rewrite_queued_at"
    t.string "role", default: "letter", null: false
    t.datetime "updated_at", null: false
    t.index ["proposal_id", "position"], name: "index_proposal_sections_on_proposal_id_and_position"
    t.index ["proposal_id"], name: "index_proposal_sections_on_proposal_id"
  end

  create_table "proposals", force: :cascade do |t|
    t.string "archetype"
    t.integer "attempts", default: 1, null: false
    t.text "body"
    t.json "checks", default: {}
    t.json "claude_meta", default: {}
    t.datetime "created_at", null: false
    t.integer "duration_ms"
    t.text "feedback"
    t.datetime "generated_at"
    t.integer "job_posting_id", null: false
    t.string "template_name"
    t.datetime "updated_at", null: false
    t.integer "version", default: 1, null: false
    t.index ["job_posting_id", "version"], name: "index_proposals_on_job_posting_id_and_version", unique: true
    t.index ["job_posting_id"], name: "index_proposals_on_job_posting_id"
  end

  create_table "saved_searches", force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.boolean "auto_generate", default: false, null: false
    t.string "contract_type"
    t.datetime "created_at", null: false
    t.json "excluded_countries", default: []
    t.json "excluded_keywords", default: []
    t.integer "hot_threshold", default: 85, null: false
    t.datetime "last_polled_at"
    t.decimal "min_fixed", precision: 12, scale: 2
    t.decimal "min_hourly", precision: 10, scale: 2
    t.string "name", null: false
    t.integer "position", default: 0, null: false
    t.string "template_name"
    t.json "terms", default: []
    t.integer "threshold", default: 70, null: false
    t.datetime "updated_at", null: false
    t.json "weights", default: {}
    t.index ["name"], name: "index_saved_searches_on_name", unique: true
  end

  create_table "settings", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "key", null: false
    t.datetime "updated_at", null: false
    t.string "value"
    t.index ["key"], name: "index_settings_on_key", unique: true
  end

  add_foreign_key "feedbacks", "job_postings"
  add_foreign_key "feedbacks", "lessons"
  add_foreign_key "feedbacks", "proposals"
  add_foreign_key "feedbacks", "saved_searches"
  add_foreign_key "job_postings", "saved_searches"
  add_foreign_key "knowledge_projects", "knowledge_scans"
  add_foreign_key "knowledge_repos", "knowledge_projects"
  add_foreign_key "knowledge_repos", "knowledge_scans"
  add_foreign_key "lessons", "saved_searches"
  add_foreign_key "proposal_sections", "proposals"
  add_foreign_key "proposals", "job_postings"
end
