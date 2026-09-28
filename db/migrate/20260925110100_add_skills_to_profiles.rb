# Skills the person wants work for, typed in the profile. Job scoring leans on
# skills.yml, and someone who skips the project scan would otherwise score
# zero on skill overlap for every job and see an empty inbox.
class AddSkillsToProfiles < ActiveRecord::Migration[8.1]
  def change
    add_column :profiles, :skills, :text
  end
end
