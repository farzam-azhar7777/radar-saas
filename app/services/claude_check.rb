# Proves Claude Code works for Radar on this computer: that the command
# exists, that it is signed in, and that the person's plan can use the model
# proposals are written with. Each failure gets its own fix.
module ClaudeCheck
  Result = Struct.new(:installed, :version, :signed_in, :model_ok, :error, :fix, keyword_init: true) do
    def ok? = installed && signed_in && model_ok
  end

  PROMPT = "Reply with exactly the word OK and nothing else.".freeze
  TIMEOUT = 120

  module_function

  def call
    version = ClaudeRun.version
    unless version
      return Result.new(installed: false, error: "Radar could not run #{ClaudeRun.command}.",
                        fix: :install)
    end

    begin
      ClaudeRun.call(PROMPT, timeout: TIMEOUT, label: "setup check")
    rescue ClaudeRun::Error => e
      return Result.new(installed: true, version: version, signed_in: false,
                        error: e.message.first(300), fix: signed_out?(e.message) ? :login : :unknown)
    end

    model = Radar.writer_model
    return Result.new(installed: true, version: version, signed_in: true, model_ok: true) if model.nil?

    begin
      ClaudeRun.call(PROMPT, timeout: TIMEOUT, model: model, label: "setup model check")
      Result.new(installed: true, version: version, signed_in: true, model_ok: true)
    rescue ClaudeRun::Error => e
      Result.new(installed: true, version: version, signed_in: true, model_ok: false,
                 error: e.message.first(300), fix: :model)
    end
  end

  def signed_out?(message)
    message.match?(/log ?in|logged out|authenticat|api key|unauthori[sz]ed|credential|\/login/i)
  end
end
