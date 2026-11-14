class ReplyStylesController < ApplicationController
  def edit
    @rules, @turn = ReplyStyle.rules, ReplyStyle.turn
  end

  def update
    @rules, @turn = params.expect(reply_style: %i[rules turn]).values_at(:rules, :turn)
    if (@errors = ReplyStyle.errors(turn: @turn)).any?
      render :edit, status: :unprocessable_entity
    else
      ReplyStyle.save(rules: @rules, turn: @turn)
      redirect_to edit_reply_style_path, notice: "Saved. The next reply uses these, in every conversation."
    end
  end

  def destroy
    ReplyStyle.restore!
    redirect_to edit_reply_style_path, notice: "Back to the example."
  end
end
