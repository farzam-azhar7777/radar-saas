require "open3"
require "timeout"

module Knowledge
  # Read-only git, as an argument list, never through a shell.
  #
  # The path comes from a form, so it is never interpolated into a command
  # string. Every call has a deadline: one repository with a broken object store
  # or a hung credential helper must not stall a scan of two hundred.
  module Git
    TIMEOUT = 60

    # Git should never ask anything. A prompt for credentials or a pager would
    # sit waiting for a terminal that does not exist.
    ENV_VARS = { "GIT_TERMINAL_PROMPT" => "0", "GIT_PAGER" => "cat", "PAGER" => "cat", "LC_ALL" => "C" }.freeze

    module_function

    def run(path, *args, timeout: TIMEOUT)
      out = +""
      Open3.popen3(ENV_VARS, "git", "-C", path.to_s, "-c", "core.quotepath=off", *args, pgroup: true) do |stdin, stdout, stderr, thread|
        stdin.close
        reader = Thread.new { out << stdout.read.to_s }
        drain = Thread.new { stderr.read }

        unless thread.join(timeout)
          Process.kill("KILL", -Process.getpgid(thread.pid)) rescue nil
          reader.kill
          drain.kill
          return nil
        end

        reader.join
        drain.join
        return thread.value.success? ? out.force_encoding(Encoding::UTF_8).scrub : nil
      end
    rescue Errno::ENOENT, IOError, SystemCallError
      nil
    end

    def repo?(path) = File.exist?(File.join(path.to_s, ".git"))
  end
end
