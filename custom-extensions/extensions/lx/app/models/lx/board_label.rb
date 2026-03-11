# frozen_string_literal: true

# Model for board_labels table (exists in CE schema but unused without EE).
# Links a board to one or more scoping labels.
module LX
  class BoardLabel < ApplicationRecord
    self.table_name = 'board_labels'

    belongs_to :board
    belongs_to :label
  end
end
