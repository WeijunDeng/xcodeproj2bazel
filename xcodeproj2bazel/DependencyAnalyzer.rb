
class DependencyAnalyzer

    def read_source_file(file)
        binding.pry unless File.exist? file and File.file? file
        content = File.read(file, :encoding => 'bom|utf-8')
        content.encode!('UTF-8', 'UTF-8', :invalid => :replace)
    
        filter_content = DynamicConfig.filter_content(content)
        if content != filter_content
            puts "rewrite: #{file}"
            File.write(file, filter_content)
            content = filter_content
        end

        content = content.gsub(/(^|\n) *\/\/.*/, "")
        content = content.gsub(/\/\*.*\*\//, "")
        content = content.gsub(/\\ *\n/, " ")
        return content
    end

    def parse_module_deps_hash(module_name, module_deps_hash, module_deps_set)
        return if module_deps_set.include? module_name
        module_deps_set.add module_name
        if module_deps_hash[module_name]
            module_deps_hash[module_name].each do | import_module_name |
                parse_module_deps_hash(import_module_name, module_deps_hash, module_deps_set)
            end
        end
    end

    def parse_import_for_swift_file(file, module_name, module_deps_hash, user_module_hash, file_deps_hash)
        content = read_source_file(file)
        modules = content.scan(/import (\w+)/).flatten
        file_deps_hash[file] = Set.new unless file_deps_hash[file]
        
        modules.each do | import_module_name |
            system_framework = FileFilter.get_system_framework_by_name(import_module_name)
            if system_framework
                file_deps_hash[file].add [:system_framework, system_framework]
                next
            end
            if user_module_hash.has_key? import_module_name
                file_deps_hash[file].add [:user_module, import_module_name]
                module_deps_hash[module_name] = Set.new unless module_deps_hash[module_name]
                module_deps_hash[module_name].add import_module_name
            end
        end
    end

    def parse_dependency_for_file(file, pch, target_name, file_deps_hash, total_public_header_map, target_private_header_map, project_header_map, target_header_dirs, target_framework_dirs, user_module_hash, total_target_copy_map, target_dtrace_files)
        if file_deps_hash.has_key? file
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
    
            match_header = nil
            
            unless match_header
                if total_public_header_map
                    match_header_set = total_public_header_map[import_file_path.downcase]
                    if match_header_set
                        binding.pry unless match_header_set.size == 1
                        a = match_header_set.to_a[0]
                        header = a[0]
                        namespace = a[1]
                        header = FileFilter.get_exist_expand_path_file(header)
                        if header
                            match_header = header
                            # public header_map
                            FileLogger.add_verbose_log "#{file} add header: #{match_header} (#{import_file_path}) by public header_map"
                            file_deps_hash[file].add [:public_header_map, match_header, namespace]
                        end
                    end
                end
            end
            unless match_header
                if target_private_header_map
                    header = target_private_header_map[import_file_path.downcase]
                    if header
                        header = FileFilter.get_exist_expand_path_file(header)
                        if header
                            match_header = header
                            # private header_map
                            FileLogger.add_verbose_log "#{file} add header: #{match_header} (#{import_file_path}) by private header_map"
                            file_deps_hash[file].add [:private_header_map, match_header, target_name]
                        end
                    end
                end
            end
            unless match_header
                if project_header_map
                    header = project_header_map[import_file_path.downcase]
                    if header
                        header = FileFilter.get_exist_expand_path_file(header)
                        if header
                            match_header = header
                            # project header_map
                            FileLogger.add_verbose_log "#{file} add header: #{match_header} (#{import_file_path}) by project header_map"
                            file_deps_hash[file].add [:project_header_map, match_header, target_name]
                        end
                    end
                end
            end
            unless match_header
                header = import_file_path
                header = FileFilter.get_exist_expand_path_file(header)
                if header
                    match_header = header
                    # full path
                    FileLogger.add_verbose_log "#{file} add header: #{match_header} (#{import_file_path}) by workspace path"
                    file_deps_hash[file].add [:headers, match_header]
                end
            end
            unless match_header
                header = File.dirname(file) + "/" + import_file_path
                header = FileFilter.get_exist_expand_path_file(header)
                if header
                    match_header = header
                    # current file dir
                    FileLogger.add_verbose_log "#{file} add header: #{match_header} (#{import_file_path}) by current file dir #{File.dirname(file)}"
                    if is_angled_import
                        file_deps_hash[file].add [:headers, match_header, File.dirname(file)]
                    else
                        file_deps_hash[file].add [:headers, match_header]
                    end
                end
            end
            unless match_header
                match_result = import_file_path.match(/^(\w+)\/(.*)$/)
                if match_result
                    target_framework_dirs.each do | dir |
                        if dir.class == String
                            framework_name = match_result[1]
                            file_name = match_result[2]
                            header = dir + "/" + framework_name + ".framework/Headers/" + file_name
                            header = FileFilter.get_exist_expand_path_file(header)
                            if header
                                # find by framework search path
                                match_header = header
                                FileLogger.add_verbose_log "#{file} add header: #{match_header} (#{import_file_path}) by search framework dir #{dir}"
                                file_deps_hash[file].add [:headers, match_header]
                                break
                            end
                        end
                        if dir.class == Array and not import_file_path.include? "./"
                            copy_dst_file = dir[1] + "/" + import_file_path.split("/")[0] + ".framework/Headers/" + import_file_path.split("/")[1..-1].join("/")
                            if import_file_path.include? "/" and total_target_copy_map[copy_dst_file]
                                match_header = total_target_copy_map[copy_dst_file]
                                namespace = File.dirname(import_file_path)
                                # find by framework search path in build dir
                                file_deps_hash[file].add [:virtual_header_map, match_header, namespace, dir[1] + "/" + import_file_path.split("/")[0] + ".framework"]
                                break
                            end
                        end
                    end
                end
            end
            if not match_header and not import_file_path.include? "./"
                total_target_copy_map_reverse = total_target_copy_map[:reverse]
                current_header_copy_dsts = total_target_copy_map_reverse[file]
                if current_header_copy_dsts
                    current_header_copy_dsts.each do | current_header_copy_dst |
                        if current_header_copy_dst.include? ".framework/Headers/"
                            copy_dst_file = current_header_copy_dst.split(".framework/Headers/")[0] + ".framework/Headers/" + import_file_path
                            if total_target_copy_map[copy_dst_file]
                                match_header = total_target_copy_map[copy_dst_file]
                                namespace = ""
                                namespace = File.dirname(import_file_path) if import_file_path.include? "/"
                                # find by same framework path in build dir
                                file_deps_hash[file].add [:virtual_header_map, match_header, namespace, File.dirname(copy_dst_file)]
                                break
                            end
                        end
                    end
                end
            end
            unless match_header
                target_header_dirs.each do | dir |
                    if dir.class == String
                        header = dir + "/" + import_file_path
                        header = FileFilter.get_exist_expand_path_file(header)
                        if header
                            # find by header search path
                            match_header = header
                            real_match_header = FileFilter.get_real_exist_expand_path_file(match_header)
                            if real_match_header != match_header
                                match_header = real_match_header
                                namespace = ""
                                namespace = File.dirname(import_file_path) if import_file_path.include? "/"
                                # find by symlink headers
                                file_deps_hash[file].add [:virtual_header_map, match_header, namespace, File.dirname(header)]
                                break
                            end
                            FileLogger.add_verbose_log "#{file} add header: #{match_header} (#{import_file_path}) by search header dir #{dir}"
                            file_deps_hash[file].add [:headers, match_header, dir]
                            break
                        end
                    end
                    if dir.class == Array and not import_file_path.include? "./"
                        build_dirs = []
                        if dir[1].include? "*"
                            build_dirs = total_target_copy_map[:pattern][dir[1]]
                            unless build_dirs
                                build_dirs = total_target_copy_map.keys.select{|x| x.class == String and File.fnmatch(dir[1], x) }.map{|x|File.dirname(x)}.uniq
                                total_target_copy_map[:pattern][dir[1]] = build_dirs
                            end
                        else
                            build_dirs = [dir[1]]
                        end
                        build_dirs.each do | build_dir |
                            copy_dst_file = build_dir + "/" + import_file_path
                            if total_target_copy_map[copy_dst_file]
                                match_header = total_target_copy_map[copy_dst_file]
                                namespace = ""
                                namespace = File.dirname(import_file_path) if import_file_path.include? "/"
                                # find by header search path in build dir
                                file_deps_hash[file].add [:virtual_header_map, match_header, namespace, File.dirname(copy_dst_file)]
                                break
                            end
                        end
                    end
                end
            end
            unless match_header
                if import_file_path.end_with? ".h" and not import_file_path.include? "./" and not import_file_path.include? "/"
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
                binding.pry if match_header != FileFilter.get_real_exist_expand_path_file(match_header)

                parse_dependency_for_file(match_header, nil, target_name, file_deps_hash, total_public_header_map, target_private_header_map, project_header_map, target_header_dirs, target_framework_dirs, user_module_hash, total_target_copy_map, target_dtrace_files)
            end
        end
        file_deps_hash[file].sort.each do | dep_info |
            header = dep_info[1]
            next unless header
            next unless file_deps_hash[header]
            file_deps_hash[file].merge file_deps_hash[header]
        end
    end

    def analyze_modules(target_info_hash_for_xcode, target_product_hash)
        user_module_hash = {}
        module_map_file_hash = {}

        total_module_map_files = Set.new
        total_module_map_files.merge target_info_hash_for_xcode.map{|x|x[1][:dep_module_map_files].to_a}
        total_module_map_files.merge target_info_hash_for_xcode.map{|x|x[1][:module_map_file]}
        total_module_map_files.merge target_product_hash.to_a.select{|x|x[1][0] == :import_path and File.extname(x[0]) == ".framework"}.map{|x|x[0]}.map{|x|Dir.glob(x+"/Modules/*.modulemap")}
        total_module_map_files = total_module_map_files.to_a.flatten.select{|x|x and File.exist? x and File.file? x}.map{|x|File.realpath(x)}.to_set

        total_module_map_files.each do | module_map_file |
            binding.pry unless File.extname(module_map_file) == ".modulemap"
            binding.pry unless File.exist? module_map_file
            module_map_file_content = File.read(module_map_file)
            if module_map_file_content != DynamicConfig.filter_content(module_map_file_content)
                binding.pry
            end
            module_name = module_map_file_content.strip.lines[0].scan(/module\s+(\w+)/).flatten[0]
            binding.pry unless module_name

            module_map_file_headers = module_map_file_content.scan(/\Wheader\s\"(.*)\"/).flatten
            binding.pry unless module_map_file_headers.size > 0

            binding.pry if user_module_hash[module_name]
            user_module_hash[module_name] = {}
            user_module_hash[module_name][:module_map_file] = module_map_file
            user_module_hash[module_name][:module_map_file_headers] = module_map_file_headers
            module_map_file_hash[module_map_file] = module_name
        end

        target_module_name_hash = {}
        target_info_hash_for_xcode.each do | target_name, info_hash |
            has_swift = info_hash[:has_swift]
            module_name = nil
            module_map_file = info_hash[:module_map_file]
            user_module_info = {}
            if module_map_file
                module_name = module_map_file_hash[module_map_file]
            end
            unless module_name
                module_name = info_hash[:product_module_name]
                if module_name
                    binding.pry if user_module_hash[module_name]
                    user_module_hash[module_name] = {}
                end
            end
            next unless module_name
            target_module_name_hash[target_name] = module_name

            target_headers = info_hash[:target_headers]

            umbrella_header = nil
            module_map_headers = Set.new
            if module_map_file
                module_map_file_headers = user_module_hash[module_name][:module_map_file_headers]
                module_map_file_headers.each do | module_map_file_header |
                    has_match_header = false
                    target_headers.each do | header |
                        if header.end_with? "/" + module_map_file_header
                            module_map_headers.add header
                            has_match_header = true
                            break
                        end
                    end
                    binding.pry unless has_match_header
                end
            else
                target_headers.each do | header |
                    if not umbrella_header and File.basename(header) == module_name + ".h"
                        module_map_headers.add header
                        umbrella_header = header
                        break
                    end
                end
            end

            binding.pry unless user_module_hash[module_name]
            binding.pry if module_map_file and module_map_headers.size == 0
            user_module_hash[module_name][:umbrella_header] = umbrella_header
            user_module_hash[module_name][:module_map_headers] = module_map_headers
            user_module_hash[module_name][:has_swift] = has_swift
        end

        user_module_hash.keys.each do | module_name |
            hash = user_module_hash[module_name]
            if hash[:module_map_file]
                if not hash[:module_map_headers] or hash[:module_map_headers].size == 0
                    if hash[:module_map_file].include? ".framework/"
                        module_map_headers = Set.new
                        module_map_file_headers = user_module_hash[module_name][:module_map_file_headers]
                        framework_headers = Dir.glob(hash[:module_map_file].split(".framework/Modules/")[0] + ".framework/Headers/**")
                        invalid = false
                        module_map_file_headers.each do | module_map_file_header |
                            has_match_header = false
                            framework_headers.each do | header |
                                if header.end_with? "/" + module_map_file_header
                                    module_map_headers.add header
                                    has_match_header = true
                                    break
                                end
                            end
                            unless has_match_header
                                invalid = true
                                break
                            end
                        end
                        if invalid
                            user_module_hash.delete(module_name)
                        else
                            hash[:module_map_headers] = module_map_headers
                        end
                        next
                    end
                    binding.pry
                end
            end
        end

        return user_module_hash, target_module_name_hash
    end

    def merge_public_header_map(target_info_hash_for_xcode)
        total_public_header_map = {}
        
        target_info_hash_for_xcode.each do | target_name, info_hash |
            target_public_header_map = info_hash[:target_public_header_map]
            namespace = info_hash[:namespace]
            target_public_header_map.each do | key, header |
                total_public_header_map[key] = Set.new unless total_public_header_map[key]
                total_public_header_map[key].add [header, namespace]
                binding.pry unless namespace and namespace.size > 0
                binding.pry if total_public_header_map[key].size > 1
            end
        end
        return total_public_header_map
    end

    def merge_target_copy_map(target_info_hash_for_xcode)
        total_target_copy_map = {}
        total_target_copy_map_reverse = {}
        target_info_hash_for_xcode.each do | target_name, info_hash |
            info_hash[:target_copy_map].each do | k, v |
                binding.pry if k.include? "./"
                binding.pry if k.include? "//"
                binding.pry if k.end_with? "/"
                binding.pry if total_target_copy_map[k] and total_target_copy_map[k] == v
                total_target_copy_map[k] = v
                total_target_copy_map_reverse[v] = Set.new unless total_target_copy_map_reverse[v]
                total_target_copy_map_reverse[v].add k
            end
        end
        total_target_copy_map[:reverse] = total_target_copy_map_reverse
        total_target_copy_map[:pattern] = {}
        return total_target_copy_map
    end

    def analyze_target_product_hash(target_info_hash_for_xcode)
        target_product_hash = {}
        product_file_name_hash = {}
        target_info_hash_for_xcode.each do | target_name, info_hash |
            product_file_name = info_hash[:product_file_name]
            binding.pry if product_file_name_hash[product_file_name]
            product_file_name_hash[product_file_name] = target_name
        end
        target_info_hash_for_xcode.each do | target_name, info_hash |
            dependency_target_product_file_names = info_hash[:target_links_hash][:dependency_target_product_file_names]
            dependency_target_product_file_names.each do | product_path |
                dependency_target_name = product_file_name_hash[File.basename(product_path)]
                product_info = nil
                if dependency_target_name
                    product_info = [:target_name, dependency_target_name]
                else
                    if File.exist? product_path
                        product_info = [:import_path]
                    else
                        next
                    end
                end
                binding.pry unless product_info

                binding.pry if target_product_hash[product_path] and target_product_hash[product_path] != product_info
                target_product_hash[product_path] = product_info
            end

            resources_files = info_hash[:resources_files]
            resources_files.each do | product_path |
                next if File.exist? product_path
                dependency_target_name = product_file_name_hash[File.basename(product_path)]
                product_info = nil
                if dependency_target_name
                    product_info = [:target_name, dependency_target_name]
                end
                binding.pry unless product_info

                binding.pry if target_product_hash[product_path] and target_product_hash[product_path] != product_info
                target_product_hash[product_path] = product_info
            end
        end
        return target_product_hash
    end

    def analyze(target_info_hash_for_xcode)

        analyze_result = {}

        target_product_hash = analyze_target_product_hash(target_info_hash_for_xcode)
        user_module_hash, target_module_name_hash = analyze_modules(target_info_hash_for_xcode, target_product_hash)
        total_public_header_map = merge_public_header_map(target_info_hash_for_xcode)
        total_target_copy_map = merge_target_copy_map(target_info_hash_for_xcode)
        
        analyze_result[:user_module_hash] = user_module_hash
        analyze_result[:target_module_name_hash] = target_module_name_hash
        analyze_result[:target_product_hash] = target_product_hash

        module_deps_hash = {}

        target_info_hash_for_xcode.each do | target_name, info_hash |
            pch = info_hash[:pch]
            flags_sources_hash = info_hash[:flags_sources_hash]
            module_name = target_module_name_hash[target_name]

            target_private_header_map = info_hash[:target_private_header_map]
            use_header_map = info_hash[:use_header_map]
            target_header_dirs = info_hash[:target_header_dirs]
            target_framework_dirs = info_hash[:target_framework_dirs]
            project_header_map = info_hash[:project_header_map]

            target_public_header_map = nil
            target_public_header_map = total_public_header_map if use_header_map

            target_dtrace_files = Set.new
            flags_sources_hash.each do | flags, source_files |
                extname = flags[0]
                if FileFilter.get_source_file_extnames_d.include? extname
                    target_dtrace_files.merge source_files
                end
            end

            file_deps_hash = KeyValueStore.get_key_value_store_in_container(analyze_result, target_name)
            if pch
                parse_dependency_for_file(pch, nil, target_name, file_deps_hash, target_public_header_map, target_private_header_map, project_header_map, target_header_dirs, target_framework_dirs, user_module_hash, total_target_copy_map, target_dtrace_files)
            end
            if module_name and user_module_hash[module_name]
                user_module_hash[module_name][:module_map_headers].each do | file |
                    parse_dependency_for_file(file, pch, target_name, file_deps_hash, target_public_header_map, target_private_header_map, project_header_map, target_header_dirs, target_framework_dirs, user_module_hash, total_target_copy_map, target_dtrace_files)
                end
            end
            if info_hash[:swift_objc_bridging_header]
                file = info_hash[:swift_objc_bridging_header]
                parse_dependency_for_file(file, pch, target_name, file_deps_hash, target_public_header_map, target_private_header_map, project_header_map, target_header_dirs, target_framework_dirs, user_module_hash, total_target_copy_map, target_dtrace_files)
            end
            flags_sources_hash.each do | flags, source_files |
                extname = flags[0]
                if FileFilter.get_source_file_extnames_c_type.include? extname
                    source_files.each do | file |
                        parse_dependency_for_file(file, pch, target_name, file_deps_hash, target_public_header_map, target_private_header_map, project_header_map, target_header_dirs, target_framework_dirs, user_module_hash, total_target_copy_map, target_dtrace_files)
                    end   
                elsif FileFilter.get_source_file_extnames_swift.include? extname
                    source_files.each do | file |
                        parse_import_for_swift_file(file, module_name, module_deps_hash, user_module_hash, file_deps_hash)
                    end
                end
            end
        end

        user_module_hash.each do | module_name, hash |
            module_map_deps = Set.new
            module_map_headers = hash[:module_map_headers]
            if module_map_headers
                target_info_hash_for_xcode.each do | target_name, info_hash |
                    file_deps_hash = KeyValueStore.get_key_value_store_in_container(analyze_result, target_name)
                    module_map_headers.each do | file |
                        module_map_deps.merge file_deps_hash[file] if file_deps_hash[file]
                    end
                end
            end
            module_deps_set = Set.new
            parse_module_deps_hash(module_name, module_deps_hash, module_deps_set)
            hash[:module_deps] = module_map_deps + module_deps_set.map{|x| [:user_module, x] }.to_set
        end

        return analyze_result
    end
end