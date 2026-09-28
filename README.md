# Radar

Radar watches Upwork for the jobs worth your time. It scores every one against
your own work, and drafts the proposal from your real projects, in your voice.
You read the draft, change what you like, and send it yourself.

It runs on your computer, with your Upwork API key and your Claude account.
Nothing is shared with anyone else's copy.

## What you need

- **macOS or Linux** with **Ruby 3.4.5** (see `.ruby-version`) and **git**.
- **Claude Code**, signed in. Install it with `npm install -g @anthropic-ai/claude-code`,
  then run `claude` once and sign in. Radar writes with Claude Opus 5 by
  default; setup checks whether your plan can use it and offers your plan's
  default model if it cannot.
- **An Upwork API key issued to you.** Setup walks you through applying: which
  four permissions to tick, and which never to tick. Upwork's review usually
  takes about two business days.
- **The folder your project repositories live in.** Optional, but it is what
  makes the proposals specific.

## Install

```bash
git clone <this repository> radar
cd radar
bin/setup
```

Then open **http://localhost:8586**. Setup takes about fifteen minutes, most of
it Radar reading your repositories while you do something else:

1. Connect Claude Code
2. Add your Upwork API key
3. Connect your Upwork account. No tunnel is needed: you paste back the address Upwork sends you to.
4. Your profile
5. Your work (optional). Radar finds your commits across your repositories and writes up the projects you choose.
6. Your voice (optional)
7. Searches. Suggested from your work, each previewed against live Upwork before you save it.
8. Preferences (optional)
9. Your first proposal. Setup finishes when Radar has written one you would send.

Every step can be changed later from **Settings**.

## Every day

```bash
bin/dev
```

This starts the web server, the background worker and the stylesheet watcher,
on port 8586. Use `PORT=9000 bin/dev` for another port.

Radar only runs while your computer is awake. After a sleep it notices that the
scheduler stalled and restarts it, and the sidebar says so while it does.

## What Radar will never do

Radar cannot submit a proposal, send a message or spend a Connect. Upwork
permanently bans tools that bid for you, so this is enforced in code rather
than promised: `test/services/no_submit_path_test.rb` fails if anything ever
gains that ability. Every model call runs with read-only tools.

## Where your data lives

| What | Where |
|---|---|
| Career folder: the files proposals are written from | `storage/career/` |
| Jobs, proposals, settings | `storage/*.sqlite3` |
| Your Upwork key, encrypted | in the database; the encryption key is `storage/encryption.json` |
| Upwork sign-in | `storage/upwork_tokens.json` |

`storage/` is never committed. To start over, run `bin/setup --reset`. It
leaves your repositories untouched.

## Privacy

Radar reads your repositories on your computer. When it writes up a project,
Claude receives that project's commit messages and up to eight of the files
you changed most in it, under your own Claude account. Nothing else leaves
your computer except Upwork API calls.

## Tests

```bash
bin/rails test
```
