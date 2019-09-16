module Rails
  module Plantuml
    module Generator
      class Association
          def initialize(table_name, another_table_name, associated_column, is_foreign_key)
            @tables = Set.new([table_name,another_table_name])
            @associated_column = associated_column
            @is_foreign_key = is_foreign_key
          end
      end
    end
  end
end