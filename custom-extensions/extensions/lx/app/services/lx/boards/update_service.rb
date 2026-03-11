# frozen_string_literal: true

# LX extension for Boards::UpdateService.
# Allows setting board scope labels via the API.
module LX
  module Boards
    module UpdateService
      def execute(board)
        handle_labels(board)
        super
      end

      private

      def handle_labels(board)
        return unless params.key?(:labels)

        label_names = params.delete(:labels)

        LX::BoardLabel.where(board_id: board.id).delete_all

        return if label_names.blank?

        parent = board.resource_parent
        label_names.to_s.split(',').map(&:strip).each do |label_name|
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
    end
  end
end
