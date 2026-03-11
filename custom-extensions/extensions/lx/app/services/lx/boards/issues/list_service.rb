# frozen_string_literal: true

# LX extension for Boards::Issues::ListService.
# Filters board issues by the board's scoped labels.
module LX
  module Boards
    module Issues
      module ListService
        private

        def filter(items)
          items = super

          if board.scoped? && board.board_labels.any?
            board.board_labels.each do |board_label|
              items = items.where(
                label_links(items, [board_label.label_id]).arel.exists
              )
            end
          end

          items
        end
      end
    end
  end
end
