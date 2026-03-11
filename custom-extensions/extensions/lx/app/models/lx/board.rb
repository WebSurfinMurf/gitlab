# frozen_string_literal: true

# LX extension for Board model.
# Adds label-based board scoping (EE feature brought to CE).
module LX
  module Board
    extend ActiveSupport::Concern

    prepended do
      has_many :board_labels, class_name: 'LX::BoardLabel', foreign_key: :board_id
      has_many :labels, through: :board_labels
    end

    def scoped?
      board_labels.any?
    end
  end
end
