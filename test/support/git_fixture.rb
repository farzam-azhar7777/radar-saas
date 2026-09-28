# Real git repositories, built in a temp folder, so the knowledge base is
# tested against git itself rather than a fake of it.
module GitFixture
  def build_folder
    root = Pathname.new(Dir.mktmpdir("radar-kb"))
    yield root
    root
  end

  # commits: [[author_name, email, message, { "path" => "content" }], ...]
  def git_repo(root, name, commits, files: {})
    dir = root.join(name)
    FileUtils.mkdir_p(dir)
    git(dir, "init", "-q", "-b", "main")
    files.each { |path, content| write(dir, path, content) }
    commits.each_with_index do |(author, email, message, changes), i|
      (changes || { "work/#{i}.rb" => "# #{message}\n" * (i + 1) }).each { |path, content| write(dir, path, content) }
      git(dir, "add", "-A")
      env = { "GIT_AUTHOR_NAME" => author, "GIT_AUTHOR_EMAIL" => email,
              "GIT_COMMITTER_NAME" => author, "GIT_COMMITTER_EMAIL" => email,
              "GIT_AUTHOR_DATE" => "2025-0#{(i % 9) + 1}-10T10:00:00Z", "GIT_COMMITTER_DATE" => "2025-0#{(i % 9) + 1}-10T10:00:00Z" }
      system(env, "git", "-C", dir.to_s, "-c", "commit.gpgsign=false", "commit", "-q", "-m", message, exception: true, out: File::NULL)
    end
    dir
  end

  def write(dir, path, content)
    target = dir.join(path)
    FileUtils.mkdir_p(target.dirname)
    File.write(target, content)
  end

  def git(dir, *args) = system("git", "-C", dir.to_s, *args, exception: true, out: File::NULL, err: File::NULL)
end
