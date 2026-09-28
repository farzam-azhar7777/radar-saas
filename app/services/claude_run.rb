require "open3"

# One place that runs Claude headless inside the career repo.
#
# The generator, the section rewriter and the lesson distiller each grew their
# own copy of this, and a fourth was about to appear for the parallel writer.
# Three of them had subtly different timeout and kill behaviour, and the tool
# restriction that keeps Radar read-only was repeated in each.
#
# Tool access is restricted to reads here, once, which is what makes "Radar
# never writes into the career folder, or into anyone's repos" a mechanism
# rather than a promise.
class ClaudeRun
  ALLOWED_TOOLS = "Read,Glob,Grep".freeze

  class Error < StandardError; end

  Result = Struct.new(:text, :meta, :duration_ms, keyword_init: true)

  def self.call(...) = new(...).call

  # The command Radar will run, for showing on screen. Asked of this file so
  # that nothing else in the app needs to know how claude is started.
  def self.command = Radar.claude_bin

  # "2.1.273 (Claude Code)", or nil when the command cannot be run at all.
  # Lives here because this file is the only one allowed to start claude.
  def self.version(bin = Radar.claude_bin)
    out, status = Open3.capture2e(bin, "--version")
    status.success? ? out.strip.lines.first&.strip : nil
  rescue SystemCallError
    nil
  end

  # chdir is where the model's Read, Glob and Grep can see. The career folder by
  # default; one of the person's repos when a project is being written up.
  # add_dirs lets the model read beyond chdir, still read-only: a project
  # spread over three repositories is written up from all three.
  def initialize(prompt, timeout:, model: nil, label: nil, chdir: nil, add_dirs: [])
    @prompt = prompt
    @timeout = timeout
    @model = model.presence
    @label = label
    @chdir = (chdir || CareerFolder.ensure!).to_s
    @add_dirs = Array(add_dirs).map(&:to_s).reject { |d| d.blank? || d == @chdir }
  end

  def call
    started = Time.current
    output = spawn_and_wait
    payload = parse(output)

    text = payload["result"].to_s
    raise Error, "claude returned no result text" if text.blank?

    Result.new(text: text, duration_ms: ((Time.current - started) * 1000).to_i,
               meta: payload.slice("session_id", "total_cost_usd", "num_turns", "duration_api_ms", "stop_reason"))
  end

  private

  def spawn_and_wait
    cmd = [ Radar.claude_bin, "-p", @prompt, "--output-format", "json", "--allowedTools", ALLOWED_TOOLS ]
    cmd += [ "--model", @model ] if @model
    @add_dirs.each { |dir| cmd += [ "--add-dir", dir ] }

    output = +""
    status = nil

    # pgroup, so a timeout kills the whole tree rather than orphaning the model
    # process to keep burning tokens with nobody listening.
    Open3.popen2e(*cmd, chdir: @chdir, pgroup: true) do |stdin, stdout_err, wait_thr|
      stdin.close
      reader = Thread.new { output << stdout_err.read rescue nil }

      unless wait_thr.join(@timeout)
        begin
          Process.kill("TERM", -Process.getpgid(wait_thr.pid))
        rescue StandardError
          nil
        end
        reader.kill
        raise Error, "#{@label || 'claude -p'} exceeded #{@timeout}s"
      end

      reader.join(5)
      status = wait_thr.value
    end

    raise Error, "claude exited #{status&.exitstatus}: #{output.first(400)}" unless status&.success?

    output
  rescue Errno::ENOENT
    # Not on the PATH the server was started with. Common when claude came
    # from a version manager, and fixable in Settings without a restart.
    raise Error, "Radar could not find the claude command (#{Radar.claude_bin}). Set its full path in Settings."
  end

  def parse(raw)
    JSON.parse(raw)
  rescue JSON::ParserError
    start = raw.index("{")
    raise Error, "unparseable output: #{raw.first(400)}" if start.nil?

    JSON.parse(raw[start..])
  rescue StandardError => e
    raise Error, e.message
  end

  # Pull the last fenced block, which is how every prompt here asks for output.
  #
  # An empty block returns empty, deliberately. Falling back to the raw text
  # when a fence was found but had nothing in it hands the caller a string of
  # backticks, which then reads as content.
  def self.fenced(text)
    blocks = text.to_s.scan(/```[a-zA-Z]*\n(.*?)```/m).flatten
    return blocks.last.strip if blocks.any?

    text.to_s.strip
  end
end
