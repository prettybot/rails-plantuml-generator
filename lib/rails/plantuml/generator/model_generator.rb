module Rails
  module Plantuml
    module Generator
      class ModelGenerator

        def initialize(model_files)
          @models = (model_files.map { |filename| extract_class_name(filename).constantize }).select { |m| class_relevant? m }
          @associations_hash = determine_associations @models
        end

        def class_relevant?(clazz)
          clazz.superclass == ((defined? ApplicationRecord).present? ? ApplicationRecord : ActiveRecord::Base)
        end

        def class_name(clazz)
          clazz.name
        end

        def extract_class_name(filename)
          filename_was, class_name = filename, nil

          filename = "app/models/#{filename.split('app/models')[1]}"

          while filename.split('/').length > 2
            begin
              class_name = filename.match(/.*\/models\/(.*).rb$/)[1].camelize
              class_name.constantize
              break
            rescue Exception
              class_name = nil
              filename_end = filename.split('/')[2..-1]
              filename_end.shift
              filename = "#{filename.split('/')[0, 2].join('/')}/#{filename_end.join('/')}"
            end
          end

          if class_name.nil?
            filename_was.match(/.*\/models\/(.*).rb$/)[1].camelize
          else
            class_name
          end
        end

        def determine_associations(models)
          result = []
          models.each do |model|
            associations = model.reflect_on_all_associations
            associations.each do |assoc|
              # FIXME 是不是都有class_name
              assoc_class_name = assoc.class_name rescue nil
              assoc_class_name ||= assoc.name.to_s.underscore.singularize.camelize
              # 自连接
              if assoc_class_name == model.to_s
                new_obj = ::Rails::Plantuml::Generator::Association.new(model.table_name, "id", model.table_name, assoc.options[:foreign_key] || "#{assoc.plural_name.singularize}_id")
                result << new_obj unless include_same_obj?(result, new_obj)
                next
              end
              macro = assoc.macro.to_s
              if assoc.options.include?(:through)
                if macro == "has_many"
                  # has_many :through
                  # 这里有两种情况
                  # 两个模型之间多对多的关联关系
                  # 简化嵌套的has_many关联
                  # 区别在于后者没有反向的has_many关联关系
                  third_class_name = get_third_class_name(model, assoc.options[:through])
                  begin
                    third_class = third_class_name.constantize
                  rescue NameError
                    puts "WARNING: #{third_class_name} not exists (#{model.to_s} #{macro}:#{third_class_name.underscore.pluralize})"
                    next
                  end
                  if third_class.column_names.include?("#{assoc_class_name.underscore}_id")
                    # 两个模型之间多对多的关系
                    new_obj = ::Rails::Plantuml::Generator::Association.new(model.table_name, "id", third_class.table_name, "#{model.table_name.singularize}_id")
                    result << new_obj unless include_same_obj?(result, new_obj)
                  end
                elsif macro == "has-one"
                  # do nothing
                end
              elsif assoc.options.include?(:as)
                begin
                  assoc_class = assoc_class_name.constantize
                rescue NameError
                  puts "WARNING: #{assoc_class_name} not exists (#{model.to_s} #{macro}:#{assoc_class_name.underscore.pluralize})"
                  next
                end
                new_obj = ::Rails::Plantuml::Generator::Association.new(model.table_name, "id", assoc_class.table_name, "#{assoc.options[:as]}_id", "多态")
                result << new_obj unless include_same_obj?(result, new_obj)
              elsif assoc.options.include?(:polymorphic)
                # do nothing
              else
                begin
                  assoc_class = assoc_class_name.constantize
                rescue NameError
                  puts "WARNING: #{assoc_class_name} not exists (#{model.to_s} #{macro}:#{assoc_class_name.underscore.pluralize})"
                  next
                end
                # 普通的一对一/一对多/多对多的关系
                if macro == "has_and_belongs_to_many"
                  third_table_name = assoc.options[:join_table] || ActiveRecord::ModelSchema.derive_join_table_name(model.table_name, assoc_class.table_name)
                  new_obj = ::Rails::Plantuml::Generator::Association.new(model.table_name, "id", third_table_name, "#{model.table_name.singularize}_id")
                  result << new_obj unless include_same_obj?(result, new_obj)
                elsif macro == "has_one" || macro == "has_many"
                  new_obj = ::Rails::Plantuml::Generator::Association.new(model.table_name, "id", assoc_class.table_name, "#{model.table_name.singularize}_id")
                  result << new_obj unless include_same_obj?(result, new_obj)
                elsif macro == "belongs_to"
                  new_obj = ::Rails::Plantuml::Generator::Association.new(model.table_name, "#{assoc_class.table_name.singularize}_id", assoc_class.table_name, "id")
                  result << new_obj unless include_same_obj?(result, new_obj)
                else
                  # do nothing
                end
              end
            end
          end
          result
        end

        # 判读数组中是有已经有相同的元素（obj）
        def include_same_obj?(arr, new_obj)
          arr.each do |obj|
            if obj.equal_to? new_obj
              return true
            end
          end
          false
        end

        # 得到through的第三个中间model
        def get_third_class_name(clazz, table_alias)
          clazz.reflect_on_all_associations.each do |association|
            if association.name == table_alias
              return association.class_name
            end
          end
        end

        def write_to_io(io)
          io.puts '@startuml'

          @models.each do |model|
            write_class model, io
            io.puts
          end

          write_associations @associations_hash, io
          io.puts

          io.puts '@enduml'
        end

        def get_col_type(col)
          if (col.respond_to?(:bigint?) && col.bigint?) || /\Abigint\b/ =~ col.sql_type
            'bigint'
          else
            (col.type || col.sql_type).to_s
          end
        end

        def write_class(clazz, io)
          return if clazz.abstract_class
          comment_helper = ::Rails::Plantuml::Generator::CommentHelper.new(clazz)
          table_comment = comment_helper.retrieve_table_comment(clazz.table_name)

          io.write "class #{clazz.table_name} "
          io.puts " {"
          if table_comment.present?
            io.puts "    #{table_comment}"
            io.puts "    =="
          end

          column_comments = comment_helper.retrieve_column_comments(clazz.table_name)
          clazz.columns.each do |col|
            col_comment = column_comments[col.name.to_sym].nil? ? "" : " --- #{column_comments[col.name.to_sym]}"
            io.puts "    #{col.name} : #{get_col_type(col)}#{col_comment}"
          end

          io.puts "}"
        end

        def write_associations(associations, io)
          associations.each do |assoc|
            keys = assoc.associations.keys
            values = assoc.associations.values
            remark = assoc.remark.present? ? "(#{assoc.remark})" : ""
            io.puts "#{values[0].to_s} -- #{values[1].to_s} : on #{keys[0]}=#{keys[1]}#{remark}"
          end
        end
      end
    end
  end
end