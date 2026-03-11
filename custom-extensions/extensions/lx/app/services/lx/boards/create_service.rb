# frozen_string_literal: true

# LX extension for Boards::CreateService.
# Allows setting board scope labels at creation time.
module LX
  module Boards
    module CreateService
      def execute
        labels_param = params.delete(:labels)
        board = super

        if board.persisted? && labels_param.present?
          parent = board.resource_parent
          labels_param.to_s.split(',').map(&:strip).each do |label_name|
            label = parent.labels.find_by(title: label_name)
            next unless label

            LX::BoardLabel.create!(
              board_id: board.id,
              label_id: label.id,
              project_id: (parent.id if parent.is_a?(Project)),
              group_id: (parent.id if parent.is_a?(Group))
            )
          end
        end

        board
      end
    end
  end
end
