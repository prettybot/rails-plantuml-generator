module Rails
  module Plantuml
    module Generator
      class Association
        def initialize(table_name, table_column, asso_table_name, asso_table_column, remark = "")
          @associations = {"#{table_name}": table_column, "#{asso_table_name}": asso_table_column}
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