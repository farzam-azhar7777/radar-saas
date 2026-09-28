module SetupHelper
  def countries
    @countries ||= TZInfo::Country.all.map(&:name).sort
  end

  # Grouped by region, the way people look for their own.
  def timezone_options
    @timezone_options ||= TZInfo::Timezone.all_country_zone_identifiers.sort
                                          .group_by { |z| z.split("/").first }
  end

  def field_error(record, attribute)
    return if record.nil? || record.errors[attribute].empty?

    tag.p("#{record.class.human_attribute_name(attribute)} #{record.errors[attribute].first}", class: "field-error")
  end

  def invalid?(record, attribute) = record&.errors&.[](attribute).present? ? "true" : nil

  # A folder people commonly keep work in, if it exists here.
  COMMON_FOLDERS = %w[~/code ~/Code ~/projects ~/Projects ~/dev ~/src ~/work ~/workspace ~/Sites ~/www ~/www/sites
                      ~/Developer ~/Documents/GitHub ~/Documents/Projects ~/repos ~/git].freeze

  # Folders that exist here, most repositories first, so the right one is
  # usually already filled in. Counts direct children only: cheap enough to
  # run on page load.
  def likely_project_folders
    @likely_project_folders ||= COMMON_FOLDERS.filter_map { |f|
      path = File.expand_path(f)
      next unless File.directory?(path)

      repos = Dir.children(path).count { |c| File.exist?(File.join(path, c, ".git")) } rescue 0
      [ f, repos ] if repos.positive?
    }.uniq { |f, _| File.realpath(File.expand_path(f)) rescue f }.sort_by { |_, n| -n }.first(5)
  end

  def number_label(n) = number_with_delimiter(n.to_i)
end
