# The shared caption vocabulary every captioned channel uses.
class Internal::VocabulariesController < Internal::ApplicationController
  before_action :set_vocabulary

  def show
  end

  def update
    if @vocabulary.update(params.require(:vocabulary).permit(:phrases))
      redirect_to internal_vocabulary_path, notice: "Caption vocabulary saved. Streams pick it up the next time they go live."
    else
      render :show, status: :unprocessable_entity
    end
  end

  private

  def set_vocabulary
    @vocabulary = Vocabulary.global
    @channels = Channel.alphabetical.includes(:vocabulary)
  end
end
