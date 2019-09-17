module Rails
  module Plantuml
    module Generator
      class Association
        attr_accessor :associations, :remark

        def initialize(table_name, table_column, asso_table_name, asso_table_column, remark = "")
          @associations = {"#{table_column}": table_name, "#{asso_table_column}": asso_table_name}
          @remark = remark
        end

        # 判断两个对象的实例变量是否完全相等
        def equal_to?(obj)
          return false if obj.class != self.class
          obj.associations == self.associations
        end
      end
    end
  end
end