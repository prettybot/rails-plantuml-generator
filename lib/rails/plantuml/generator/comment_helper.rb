# https://github.com/pinnymz/migration_comments
# 这里没有用到打开类技术
module Rails
  module Plantuml
    module Generator
      class CommentHelper
        def initialize(clazz)
          @table_name = clazz.table_name
          @adapter = clazz.connection
        end

        def retrieve_table_comment(table_name)
          @adapter.select_value(table_comment_sql(table_name)).presence
        end

        def retrieve_column_comments(table_name, *column_names)
          result = @adapter.select_rows(column_comment_sql(table_name, *column_names)) || []
          Hash[result.map { |row| [row[0].to_sym, row[1].presence] }]
        end

        def table_comment_sql(table_name)
          <<SQL
SELECT table_comment FROM INFORMATION_SCHEMA.TABLES
  WHERE table_schema = '#{database_name}'
  AND table_name = '#{table_name}'
SQL
        end

        def column_comment_sql(table_name, *column_names)
          if column_names.empty?
            col_matcher_sql = ""
          else
            col_matcher_sql = " AND column_name IN (#{column_names.map { |c_name| "'#{c_name}'" }.join(',')})"
          end
          <<SQL
SELECT column_name, column_comment FROM INFORMATION_SCHEMA.COLUMNS
  WHERE table_schema = '#{database_name}'
  AND table_name = '#{table_name}' #{col_matcher_sql}
SQL
        end

        def database_name
          @database_name ||= @adapter.select_value("SELECT DATABASE()")
        end
      end
    end
  end
end
