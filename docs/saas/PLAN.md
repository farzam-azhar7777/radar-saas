# Radar for everyone: onboarding and the knowledge base

Written 2026-09-25. The goal: anyone with their own Upwork API key clones this
repo, runs `bin/setup`, opens the browser, and the app walks them to their
first proposal worth sending. One install is one person. No multi-tenancy.

## What made Radar single-user

| Where | What was hardcoded | Becomes |
|---|---|---|
| `config/credentials.yml.enc` | Upwork client id, secret, redirect | `Credential` rows, Active Record encrypted, key file generated in `storage/` |
| `Radar.pitchsmith_path` | `../pitchsmith` | `Radar.career_path`, default `storage/career`, written by the wizard |
| Seven prompt builders | "Farzam", "his", "him" | the profile's first name, "they" |
| `config/proposal_spec.md` | his SurgePoint opening, his signature, his badges | a template rendered from the profile |
| `JobPosting::HOME_TZ`, `HOME_COUNTRY` | Asia/Karachi, Pakistan | profile timezone and country |
| `Radar.timezone` | Asia/Karachi | profile timezone |
| `db/seeds.rb` | his six searches | nothing; searches come from the wizard |
| `ProposalCheck::SELF_INTRO` | "i'm farzam" | the profile's names |
| Port 8585 in job links | fixed | `Radar.port`, default 8586 |
| Session cookie | shared name | its own name, so two copies on one machine do not log each other out |

## The career directory

The generator already reads a pitchsmith-shaped folder, and it keeps doing so.
The wizard writes that folder instead of the user hand-building it:

    storage/career/
      CLAUDE.md              rules + facts, rendered from the profile
      profile.yml            the profile form
      skills.yml             derived from accepted projects, weighted by own commits
      writing-voice.md       the voice step's samples, verbatim
      projects/_index.yml    rebuilt on every accept
      projects/<slug>.yml    one per accepted project
      templates/             the four starter templates (structure only)
      applications/          filled on "Mark applied"

## The knowledge base algorithm

Git decides what is yours and what matters. The model only writes up what the
user has already approved. Cost scales with the ~20 chosen projects, not with
the number of repos or files.

1. **Identity.** Top commit identities across the folder. The user ticks their
   own; names matching the profile are pre-ticked.
2. **Inventory** (deterministic). Every git root to depth 3: total and own
   commits, own first and last commit, active months, lines added, stack from
   lockfiles, remote, README head, schema table names.
3. **Cluster and rank** (deterministic). Repos become products by name stem
   (`fast800-api-with-web` + `fast800-app-frontend`). Ranked by own commits
   (log), share, span, recency. Zero-own-commit repos are set aside.
4. **Curation** (UI, no model). Ranked cards, top 20 pre-ticked. Include,
   exclude, merge, rename to the name the client knows it by.
5. **Evidence pack** (deterministic). Own commit subjects grouped by the
   directories touched, most-touched files, integrations, tables, numbers.
6. **Synthesis** (Claude, read-only, 3 at a time). Evidence + template schema
   + tag vocabulary in, one project YAML out. Unsupported fields stay empty.
7. **Review.** Accept, edit, regenerate with a note, or reject. Only accepted
   projects reach the career folder.

## The wizard

| # | Step | Required | If skipped |
|---|---|---|---|
| 1 | Welcome | yes | |
| 2 | Claude Code | yes | nothing can be written |
| 3 | Upwork key | yes | no jobs can be found |
| 4 | Connect Upwork | yes | no jobs can be found |
| 5 | Profile | yes | |
| 6 | Your work | no | letters cite only the profile; weaker job scoring |
| 7 | Your voice | no | competent but anonymous letters |
| 8 | Searches | yes, at least one | |
| 9 | Preferences | no | sensible defaults |
| 10 | First proposal | yes | |

Every required step says why it is required. Every skippable step states what
is lost before it lets you skip. Everything stays revisitable from Settings.

**Connecting Upwork** does not need a tunnel. Upwork requires an https
callback, but the page does not have to load: the user pastes the address they
land on and Radar takes the code from it. A callback that does reach the app
completes on its own.

## Unchanged, on purpose

- Radar cannot submit, message or spend Connects. `test/services/no_submit_path_test.rb`
  still guards it, and every new model call goes through `ClaudeRun`, read-only.
- The proposal engine itself: archetypes, checks, parts, repair, lessons.
