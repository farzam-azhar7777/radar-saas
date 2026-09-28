module Knowledge
  # Who committed across the folder, most active first.
  #
  # One person commits as several people: a personal email, an employer's, a
  # GitHub noreply address, a name spelled two ways. Measured on the first real
  # folder this ran against, its owner had four. Nothing downstream is right
  # until the person has claimed all of theirs, so this is shown to them rather
  # than guessed.
  module Identities
    LIMIT = 40

    module_function

    # [{ "email", "name", "names", "commits", "repos" }], grouped by email.
    def call(paths, &progress)
      by_email = Hash.new { |h, k| h[k] = { "email" => k, "names" => Hash.new(0), "commits" => 0, "repos" => 0 } }

      paths.each_with_index do |path, i|
        shortlog(path).each do |email, name, count|
          entry = by_email[email]
          entry["names"][name] += count
          entry["commits"] += count
          entry["repos"] += 1
        end
        progress&.call(i + 1, paths.size)
      end

      by_email.values
              .sort_by { |e| -e["commits"] }
              .first(LIMIT)
              .map { |e|
                names = e["names"].sort_by { |_, c| -c }.map(&:first)
                e.merge("name" => names.first, "names" => names)
              }
    end

    def shortlog(path)
      out = Git.run(path, "shortlog", "-sne", "--all", "--no-merges", timeout: 30).to_s
      out.lines.filter_map { |line|
        next unless (m = line.match(/\A\s*(\d+)\s+(.*?)\s+<([^>]*)>\s*\z/))

        [ m[3].downcase.strip, m[2].strip, m[1].to_i ]
      }
    end

    # Which identities are probably the person, from their profile, so the
    # usual case is one glance and a click. Deliberately strict: a wrong
    # pre-tick credits someone else's commits to them, which is worse than an
    # unticked box they notice.
    def likely_mine?(identity, profile)
      email = identity["email"].to_s
      return true if profile.email.present? && email.casecmp?(profile.email.strip)

      full = words(profile.full_name)
      return false if full.size < 2

      Array(identity["names"]).any? { |n| (full - words(n)).empty? } ||
        full.all? { |w| letters(email.split("@").first).include?(w) }
    end

    def words(text) = text.to_s.downcase.split(/[^a-z0-9]+/).reject(&:blank?)
    def letters(text) = text.to_s.downcase.gsub(/[^a-z]/, "")
  end
end
