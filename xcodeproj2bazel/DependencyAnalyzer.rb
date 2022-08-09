
class DependencyAnalyzer

    def read_source_file(file)
        binding.pry unless File.exist? file and File.file? file
        content = File.read(file, :encoding => 'bom|utf-8')
        content.encode!('UTF-8', 'UTF-8', :invalid => :replace)
    
        filter_content = DynamicConfig.filter_content(content)
        if content != filter_content
            File.write(file, filter_content)
            content = filter_content
        end

        content = content.gsub(/(^|\n) *\/\/.*/, "")
        content = content.gsub(/\/\*.*\*\//, "")
        content = content.gsub(/\\ *\n/, " ")
        return content
    end

    def parse_import_for_swift_file(file, user_module_hash, file_deps_hash)
        content = read_source_file(file)
        modules = content.scan(/import (\w+)/).flatten
        file_deps_hash[file] = Set.new unless file_deps_hash[file]
        
        modules.each do | module_name |
            system_framework = FileFilter.get_system_framework_by_name(module_name)
            if system_framework
                file_deps_hash[file].add [:system_framework, system_framework]
                next
            end
            if user_module_hash.has_key? module_name
                file_deps_hash[file].add [:user_module, module_name]
            end
        end
    end

    def parse_dependency_for_file(file, pch, target_name, file_deps_hash, total_public_headermap, target_private_headermap, project_headermap, target_header_dirs, target_framework_dirs, user_module_hash, target_dtrace_files)
        if file_deps_hash.has_key? file
            file_deps_hash[file].sort.each do | dep_info |
                header = dep_info[1]
                next unless header
                next unless file_deps_hash[header]
                file_deps_hash[file].merge file_deps_hash[header]
            end
            return
        end
    
        if pch
            file_deps_hash[file] = file_deps_hash[pch].clone
        else
            file_deps_hash[file] = Set.new
        end
    
        content = read_source_file(file)
        
        content.each_line do | line |
            line_strip = line.strip
            
            import_module_match = line_strip.match(/@import\s+(\w+)/)
            if import_module_match
                import_module = import_module_match[1]
                system_framework = FileFilter.get_system_framework_by_name(import_module)
                if system_framework
                    file_deps_hash[file].add [:system_framework, system_framework]
                elsif user_module_hash.has_key? import_module
                    file_deps_hash[file].add [:user_module, import_module]
                end
            end
    
            import_file_path_match = line_strip.match(/^# *(?:import|include) *([<\"]\S+?[>\"])/)
            next unless import_file_path_match
            is_angled_import = nil
            if import_file_path_match[1][0] == "<" and import_file_path_match[1][-1] == ">"
                is_angled_import = true
            elsif import_file_path_match[1][0] == "\"" and import_file_path_match[1][-1] == "\""
                is_angled_import = false
            else
                raise "unexpected import #{import_file_path_match}"
            end
            import_file_path = import_file_path_match[1][1..-2]

            if import_file_path.include? $xcodeproj2bazel_pwd
                raise "unexpected #{import_file_path} in #{file}"
            end

            if is_angled_import
                system_framework = FileFilter.get_system_framework_by_name(import_file_path.split("/")[0])
                if system_framework
                    file_deps_hash[file].add [:system_framework, system_framework]
                end
            end
    
            next unless import_file_path.include? "."
            next if FileFilter.is_system_header(import_file_path, is_angled_import)

            import_file_path = import_file_path.gsub(/\/+/, "/")
            header_name_downcase = File.basename(import_file_path).downcase
    
            match_header = nil
            
            unless match_header
                header = import_file_path
                header = FileFilter.get_exist_expand_path_file(header)
                if header
                    match_header = header
                    FileLogger.add_verbose_log "#{file} add header: #{match_header} (#{import_file_path}) by current dir"
                    file_deps_hash[file].add [:headers, match_header]
                end
            end
            unless match_header
                if total_public_headermap
                    match_header_set = total_public_headermap[import_file_path.downcase]
                    if match_header_set and match_header_set.size == 1
                        a = match_header_set.to_a[0]
                        header = a[0]
                        other_target_name = a[1]
                        header = FileFilter.get_exist_expand_path_file(header)
                        if header
                            match_header = header
                            # public headermap
                            FileLogger.add_verbose_log "#{file} add header: #{match_header} (#{import_file_path}) by public headermap"
                            file_deps_hash[file].add [:public_headermap, match_header, other_target_name]
                        end
                    end
                end
            end
            unless match_header
                if target_private_headermap
                    match_header_set = target_private_headermap[import_file_path.downcase]
                    if match_header_set and match_header_set.size == 1
                        header = match_header_set.to_a[0]
                        header = FileFilter.get_exist_expand_path_file(header)
                        if header
                            match_header = header
                            # private headermap
                            FileLogger.add_verbose_log "#{file} add header: #{match_header} (#{import_file_path}) by private headermap"
                            file_deps_hash[file].add [:private_headermap, match_header, target_name]
                        end
                    end
                end
            end
            unless match_header
                if project_headermap
                    match_header_set = project_headermap[import_file_path.downcase]
                    if match_header_set and match_header_set.size == 1
                        header = match_header_set.to_a[0]
                        header = FileFilter.get_exist_expand_path_file(header)
                        if header
                            match_header = header
                            # project headermap
                            FileLogger.add_verbose_log "#{file} add header: #{match_header} (#{import_file_path}) by project headermap"
                            file_deps_hash[file].add [:project_headermap, match_header, target_name]
                        end
                    end
                end
            end
            unless match_header
                header = File.dirname(file) + "/" + import_file_path
                header = FileFilter.get_exist_expand_path_file(header)
                if header
                    match_header = header
                    FileLogger.add_verbose_log "#{file} add header: #{match_header} (#{import_file_path}) by current file dir"
                    if is_angled_import
                        file_deps_hash[file].add [:headers, match_header, File.dirname(file)]
                    else
                        file_deps_hash[file].add [:headers, match_header]
                    end
                end
            end
            unless match_header
                if import_file_path.scan("/").size == 1
                    target_framework_dirs.each do | dir |
                        header = dir + "/" + import_file_path.split("/")[0] + ".framework/Headers/" + import_file_path.split("/")[1]
                        header = FileFilter.get_exist_expand_path_file(header)
                        if header
                            # 按搜索路径找到第一个
                            match_header = header
                            FileLogger.add_verbose_log "#{file} add header: #{match_header} (#{import_file_path}) by search framework dir #{dir}"
                            file_deps_hash[file].add [:headers, match_header]
                            break
                        end
                    end
                end
            end
            unless match_header
                target_header_dirs.each do | dir |
                    next unless dir.class == String
                    header = dir + "/" + import_file_path
                    header = FileFilter.get_exist_expand_path_file(header)
                    if header
                        # 按搜索路径找到第一个
                        match_header = header
                        FileLogger.add_verbose_log "#{file} add header: #{match_header} (#{import_file_path}) by search header dir #{dir}"
                        file_deps_hash[file].add [:headers, match_header, dir]
                        break
                    end
                end
            end

            unless match_header
                if import_file_path.end_with? ".h" and not import_file_path.include? ".." and not import_file_path.include? "/"
                    d_file_path = import_file_path.sub(/\.h$/, ".d").downcase
                    target_dtrace_files.each do | target_dtrace_file |
                        if target_dtrace_file.downcase.end_with? d_file_path
                            file_deps_hash[file].add [:dtrace_header, target_dtrace_file, target_name]
                            break
                        end
                    end
                end
            end

            unless match_header
                if import_file_path.end_with? "-Swift.h"
                    file_deps_hash[file].add [:swift_header, import_file_path]
                else
                    log = "unexpected #{file} (#{import_file_path}) not found"
                    FileLogger.add_verbose_log log
                end
            end
    
            if match_header
    
                if FileFilter.get_exist_expand_path_file(match_header) != match_header
                    binding.pry
                    raise "unexpected #{match_header}"
                end

                unless File.file? match_header
                    binding.pry
                end

                parse_dependency_for_file(match_header, nil, target_name, file_deps_hash, total_public_headermap, target_private_headermap, project_headermap, target_header_dirs, target_framework_dirs, user_module_hash, target_dtrace_files)
            end
        end
        file_deps_hash[file].sort.each do | dep_info |
            header = dep_info[1]
            next unless header
            next unless file_deps_hash[header]
            file_deps_hash[file].merge file_deps_hash[header]
        end
    end

    def analyze_modules(target_info_hash_for_xcode)
        user_module_hash = {}

        module_map_file_hash = {}

        total_module_map_files = (target_info_hash_for_xcode.map{|x|x[1][:dep_module_map_files].to_a} + target_info_hash_for_xcode.map{|x|x[1][:module_map_file]}).flatten.select{|x|x and File.exist? x and File.file? x}.map{|x|File.realpath(x)}.uniq

        total_module_map_files.each do | module_map_file |
            binding.pry unless File.extname(module_map_file).downcase == ".modulemap"
            binding.pry unless File.exist? module_map_file
            module_map_file_content = File.read(module_map_file)
            if module_map_file_content != DynamicConfig.filter_content(module_map_file_content)
                binding.pry
            end
            module_name = module_map_file_content.scan(/module +(\w+)/).flatten[0]
            binding.pry unless module_name
            module_map_file_hash[module_name] = Set.new unless module_map_file_hash[module_name]
            module_map_file_hash[module_name].add module_map_file
            binding.pry if module_map_file_hash[module_name].size > 1
        end

        target_info_hash_for_xcode.each do | target_name, info_hash |
            has_swift = false
            flags_sources_hash = info_hash[:flags_sources_hash]
            flags_sources_hash.each do | flags, source_files |
                extname = flags[0]
                if FileFilter.get_source_file_extnames_swift.include? extname
                    has_swift = true
                end
            end
            product_module_name = info_hash[:product_module_name]
            binding.pry if has_swift and not product_module_name
            next unless product_module_name
            target_headers = info_hash[:target_headers]

            umbrella_header = nil
            moduel_map_headers = Set.new
            module_map_file = nil
            if module_map_file_hash[product_module_name] and module_map_file_hash[product_module_name].size == 1
                module_map_file = module_map_file_hash[product_module_name].to_a[0]
            end
            if module_map_file
                module_map_file_content = File.read(module_map_file)
                module_map_header_files = module_map_file_content.scan(/header \"(.*)\"/).flatten
                binding.pry unless module_map_header_files.size > 0
                module_map_header_files.each do | module_map_header |
                    has_match_header = false
                    target_headers.each do | header |
                        if header.end_with? module_map_header
                            moduel_map_headers.add header
                            has_match_header = true
                            break
                        end
                    end
                    binding.pry unless has_match_header
                end
            else
                target_headers.each do | header |
                    if not umbrella_header and File.basename(header) == product_module_name + ".h"
                        moduel_map_headers.add header
                        umbrella_header = header
                        break
                    end
                end
            end

            user_module_hash[product_module_name] = {}
            user_module_hash[product_module_name][:umbrella_header] = umbrella_header
            user_module_hash[product_module_name][:moduel_map_headers] = moduel_map_headers
            user_module_hash[product_module_name][:module_map_file] = module_map_file
            user_module_hash[product_module_name][:has_swift] = has_swift
        end

        return user_module_hash
    end

    def merge_public_headermap(target_info_hash_for_xcode)
        total_public_headermap = {}
        
        target_info_hash_for_xcode.each do | target_name, info_hash |
            target_public_headermap = info_hash[:target_public_headermap]
            target_public_headermap.each do | key, headers |
                total_public_headermap[key] = Set.new unless total_public_headermap[key]
                headers.each do | header |
                    total_public_headermap[key].add [header, target_name]
                end
                binding.pry if total_public_headermap[key].size > 1
            end
        end
        return total_public_headermap
    end

    def analyze(target_info_hash_for_xcode)

        analyze_result = {}

        user_module_hash = analyze_modules(target_info_hash_for_xcode)
        total_public_headermap = merge_public_headermap(target_info_hash_for_xcode)
        
        analyze_result[:user_module_hash] = user_module_hash

        target_info_hash_for_xcode.each do | target_name, info_hash |
            pch = info_hash[:pch]
            flags_sources_hash = info_hash[:flags_sources_hash]
            product_module_name = info_hash[:product_module_name]

            target_private_headermap = info_hash[:target_private_headermap]
            use_headermap = info_hash[:use_headermap]
            target_header_dirs = info_hash[:target_header_dirs]
            target_framework_dirs = info_hash[:target_framework_dirs]
            project_headermap = info_hash[:project_headermap]

            target_public_headermap = nil
            target_public_headermap = total_public_headermap if use_headermap

            target_dtrace_files = Set.new
            flags_sources_hash.each do | flags, source_files |
                extname = flags[0]
                if FileFilter.get_source_file_extnames_d.include? extname
                    target_dtrace_files.merge source_files
                end
            end

            file_deps_hash = KeyValueStore.get_key_value_store_in_container(analyze_result, target_name)
            if pch
                parse_dependency_for_file(pch, nil, target_name, file_deps_hash, target_public_headermap, target_private_headermap, project_headermap, target_header_dirs, target_framework_dirs, user_module_hash, target_dtrace_files)
            end
            if product_module_name and user_module_hash[product_module_name]
                user_module_hash[product_module_name][:moduel_map_headers].each do | file |
                    parse_dependency_for_file(file, pch, target_name, file_deps_hash, target_public_headermap, target_private_headermap, project_headermap, target_header_dirs, target_framework_dirs, user_module_hash, target_dtrace_files)
                end
            end
            if info_hash[:swift_objc_bridging_header]
                file = info_hash[:swift_objc_bridging_header]
                parse_dependency_for_file(file, pch, target_name, file_deps_hash, target_public_headermap, target_private_headermap, project_headermap, target_header_dirs, target_framework_dirs, user_module_hash, target_dtrace_files)
            end
            flags_sources_hash.each do | flags, source_files |
                extname = flags[0]
                if FileFilter.get_source_file_extnames_c_type.include? extname
                    source_files.each do | file |
                        parse_dependency_for_file(file, pch, target_name, file_deps_hash, target_public_headermap, target_private_headermap, project_headermap, target_header_dirs, target_framework_dirs, user_module_hash, target_dtrace_files)
                    end   
                elsif FileFilter.get_source_file_extnames_swift.include? extname
                    source_files.each do | file |
                        parse_import_for_swift_file(file, user_module_hash, file_deps_hash)
                    end
                end
            end
        end
        
        return analyze_result
    end
end