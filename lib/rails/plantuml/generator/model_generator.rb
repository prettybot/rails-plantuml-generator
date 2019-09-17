module Rails
  module Plantuml
    module Generator
      class ModelGenerator

        def initialize(model_files, whitelist_regex)
          @whitelist_regex = Regexp.new whitelist_regex if whitelist_regex
          @models = (model_files.map { |filename| extract_class_name(filename).constantize }).select { |m| class_relevant? m }
          @associations_hash = determine_associations @models
          binding.pry
        end

        def class_relevant?(clazz)
          return false unless clazz < ((defined? ApplicationRecord).present? ? ApplicationRecord : ActiveRecord::Base)
          return true unless @whitelist_regex
          !@whitelist_regex.match(clazz.name).nil?
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
              binding.pry if model.to_s == "City::HABTM_Consultors"
              assoc_class_name = assoc.class_name rescue nil
              assoc_class_name ||= assoc.name.to_s.underscore.singularize.camelize
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
                    puts "WARNING: #{third_class_name} not exists"
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
                  puts "WARNING: #{assoc_class_name} not exists"
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
                  puts "WARNING: #{assoc_class_name} not exists"
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
          require 'pry-byebug'
          # binding.pry
          parent = clazz.superclass
          comment_helper = ::Rails::Plantuml::Generator::CommentHelper.new(clazz)
          table_comment = comment_helper.retrieve_table_comment(clazz.table_name)

          io.write "class #{class_name clazz} "
          io.write "extends #{class_name parent}" if class_relevant? parent
          io.puts " {"
          if table_comment.present?
            io.puts "    #{table_comment}"
            io.puts "    =="
          end
          unless clazz.abstract_class
            # TODO 复杂的继承关系
            # columns = clazz.columns_hash.keys
            # columns -= parent.columns_hash.keys if class_relevant? parent
            column_comments = comment_helper.retrieve_column_comments(clazz.table_name)
            clazz.columns.each do |col|
              col_comment = column_comments[col.name.to_sym].nil? ? "" : " --- #{column_comments[col.name.to_sym]}"
              io.puts "    #{col.name} : #{get_col_type(col)}#{col_comment}"
              # io.puts "    #{col.name}:#{col.sql_type} --- #{column_comments[col.name.to_sym]}"
            end
          end

          io.puts "}"
        end

        def write_associations(association_hash, io)
          association_hash.each do |clazz, associations|
            associations.each do |meta|
              other = meta[ASSOCIATION_OTHER_CLASS]
              back_associtiation_meta = association_hash[other]&.find { |other_meta| other_meta[ASSOCIATION_OTHER_CLASS] == clazz }

              back_associtiation_symbol = back_associtiation_meta[ASSOCIATION_TYPE] if back_associtiation_meta
              back_associtiation_name = back_associtiation_meta[ASSOCIATION_OTHER_NAME] if back_associtiation_meta

              association_hash[other]&.delete back_associtiation_meta
              associations.delete meta

              io.write class_name clazz

              io.write " \"#{back_associtiation_symbol}\"" if back_associtiation_meta

              io.write " -- \"#{meta[ASSOCIATION_TYPE]}\" #{class_name other} : \"#{meta[ASSOCIATION_OTHER_NAME]}"
              io.write "\\n#{back_associtiation_name}" if back_associtiation_meta
              io.puts '"'
            end
          end
        end
      end
    end
  end
end