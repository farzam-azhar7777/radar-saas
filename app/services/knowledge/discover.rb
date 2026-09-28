module Knowledge
  # Every git repository under a folder, to a sensible depth.
  #
  # People keep work as ~/code/<repo>, as ~/code/<client>/<repo>, and as
  # monorepos with their own nested repos. Three levels covers all of those
  # without walking into dependency folders that hold thousands of vendored
  # repositories nobody wrote.
  module Discover
    MAX_DEPTH = 3

    SKIP = %w[
      node_modules vendor bower_components .bundle .git tmp log dist build out coverage
      Pods DerivedData .venv venv env __pycache__ .next .nuxt .cache target .terraform
      .idea .vscode Library Applications
    ].to_set.freeze

    module_function

    def call(root)
      root = Pathname.new(root).expand_path
      return [] unless root.directory?

      found = []
      walk(root, 0, found)
      found.sort
    end

    def walk(dir, depth, found)
      found << dir.to_s if depth.positive? && Git.repo?(dir)
      return if depth >= MAX_DEPTH

      children(dir).each { |child| walk(child, depth + 1, found) }
    end

    def children(dir)
      dir.children.select { |c|
        c.directory? && !c.symlink? && !SKIP.include?(c.basename.to_s) && !c.basename.to_s.start_with?(".")
      }
    rescue Errno::EACCES, Errno::EPERM, Errno::ENOENT
      []
    end

    # The folder itself can be a single repo; people point at one project too.
    def self.with_root(root)
      list = call(root)
      Git.repo?(root) ? [ Pathname.new(root).expand_path.to_s ] + list : list
    end
  end
end
