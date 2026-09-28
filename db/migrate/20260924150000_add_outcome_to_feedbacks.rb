class AddOutcomeToFeedbacks < ActiveRecord::Migration[8.1]
  def change
    add_column :feedbacks, :outcome, :string
    add_column :feedbacks, :outcome_note, :text
    add_reference :feedbacks, :lesson, foreign_key: true, null: true

    reversible do |dir|
      dir.up do
        # Backfill by matching the text a lesson recorded it was distilled from,
        # so existing notes do not all read as unresolved.
        execute <<~SQL
          UPDATE feedbacks SET outcome = 'learned',
            lesson_id = (SELECT id FROM lessons WHERE lessons.source_feedback = feedbacks.body LIMIT 1)
          WHERE EXISTS (SELECT 1 FROM lessons WHERE lessons.source_feedback = feedbacks.body)
        SQL
      end
    end
  end
end
