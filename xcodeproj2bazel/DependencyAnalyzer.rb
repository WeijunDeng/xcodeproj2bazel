
class DependencyAnalyzer

    def read_source_file(file)
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

    def parse_import_for_swift_file(file, total_user_modules)
        content = read_source_file(file)
        modules = content.scan(/import (\w+)/).flatten
        system_modules = Set.new
        user_modules = Set.new
        modules.each do | module_name |
            system_module = FileFilter.get_system_framework_by_name(module_name)
            if system_module
                system_modules.add system_module
                next
            end
            user_modules.add module_name
        end
        return system_modules, user_modules
    end

    def parse_dependency_for_file(file, pch, file_headers_hash, file_includes_hash, file_extras_hash, total_public_headermap, target_private_headermap, target_header_dirs, target_framework_dirs)
        if file_headers_hash.has_key? file
            file_headers_hash[file].sort.each do | header |
                file_headers_hash[file].merge file_headers_hash[header] if file_headers_hash[header]
                file_includes_hash[file].merge file_includes_hash[header] if file_includes_hash[header]
                file_extras_hash[file].merge file_extras_hash[header] if file_extras_hash[header]
            end
            return
        end
        raise "unexpected" if file_includes_hash.has_key? file
    
        file_headers_hash[file] = Set.new unless file_headers_hash[file]
        file_includes_hash[file] = Set.new unless file_includes_hash[file]
        file_extras_hash[file] = Set.new unless file_extras_hash[file]
    
        if pch
            file_headers_hash[file] = file_headers_hash[pch].clone
            file_includes_hash[file] = file_includes_hash[pch].clone
            file_extras_hash[file].merge file_extras_hash[pch]
        end
    
        content = read_source_file(file)
        
        content.each_line do | line |
            line_strip = line.strip
            
            import_system_framework_match = line_strip.match(/@import\s+(\w+)/)
            if import_system_framework_match
                import_system_framework = import_system_framework_match[1]
                system_framework_name = FileFilter.get_system_framework_by_name(import_system_framework)
                if system_framework_name
                    file_extras_hash[file].add system_framework_name
                else
                    file_extras_hash[file].add "@import " + system_framework_name
                end
            end
    
            if line_strip.include? "CGImageSource"
                file_extras_hash[file].add FileFilter.get_system_framework_by_name("ImageIO")
            end
            if line_strip.include? "CMSampleBuffer"
                file_extras_hash[file].add FileFilter.get_system_framework_by_name("CoreMedia")
            end
            if line_strip.include? "CVPixelBuffer"
                file_extras_hash[file].add FileFilter.get_system_framework_by_name("CoreVideo")
            end
            if line_strip.include? "MTLDevice"
                file_extras_hash[file].add FileFilter.get_system_framework_by_name("Metal")
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
                system_framework_name = FileFilter.get_system_framework_by_name(import_file_path.split("/")[0])
                if system_framework_name
                    file_extras_hash[file].add system_framework_name
                end
            end
    
            next unless import_file_path.include? "."
            next if FileFilter.is_system_header(import_file_path, is_angled_import)

            import_file_path = import_file_path.gsub("//", "/")
            header_name_downcase = File.basename(import_file_path).downcase
    
            match_header = nil
            should_continue_add_header_dir = true
    
            unless match_header
                header = import_file_path
                header = FileFilter.get_exist_expand_path(header)
                if header
                    match_header = header
                    FileLogger.add_verbose_log "#{file} add header: #{match_header} (#{import_file_path}) by current dir"
                    should_continue_add_header_dir = false
                end
            end
            unless match_header
                if total_public_headermap
                    match_header_set = total_public_headermap[import_file_path.downcase]
                    if match_header_set and match_header_set.size == 1
                        match_header = match_header_set.to_a[0]
                        # public headermap
                        FileLogger.add_verbose_log "#{file} add header: #{match_header} (#{import_file_path}) by public headermap"
                        should_continue_add_header_dir = false
                    end
                end
            end
            unless match_header
                if target_private_headermap
                    match_header = target_private_headermap[import_file_path.downcase]
                    if match_header
                        # private headermap
                        FileLogger.add_verbose_log "#{file} add header: #{match_header} (#{import_file_path}) by private headermap"
                        should_continue_add_header_dir = false
                    end
                end
            end

            unless match_header
                header = File.dirname(file) + "/" + import_file_path
                header = FileFilter.get_exist_expand_path(header)
                if header
                    match_header = header
                    FileLogger.add_verbose_log "#{file} add header: #{match_header} (#{import_file_path}) by current file dir"
                    should_continue_add_header_dir = false unless is_angled_import
                end
            end
            unless match_header
                if import_file_path.scan("/").size == 1
                    target_framework_dirs.each do | dir |
                        header = dir + "/" + import_file_path.split("/")[0] + ".framework/Headers/" + import_file_path.split("/")[1]
                        header = FileFilter.get_exist_expand_path(header)
                        if header
                            # 按搜索路径找到第一个
                            match_header = header
                            FileLogger.add_verbose_log "#{file} add header: #{match_header} (#{import_file_path}) by search framework dir #{dir}"
                            should_break = true
                            break
                        end
                    end
                end
            end
            unless match_header
                target_header_dirs.each do | dir |
                    header = dir + "/" + import_file_path
                    header = FileFilter.get_exist_expand_path(header)
                    if header
                        # 按搜索路径找到第一个
                        match_header = header
                        FileLogger.add_verbose_log "#{file} add header: #{match_header} (#{import_file_path}) by search header dir #{dir}"
                        should_break = true
                        break
                    end
                end
            end

            unless match_header
                if import_file_path.end_with? "-Swift.h"
                    file_headers_hash[file].add import_file_path
                else
                    log = "unexpected #{file} (#{import_file_path}) not found"
                    FileLogger.add_verbose_log log
                end
            end
    
            if match_header
    
                if FileFilter.get_exist_expand_path(match_header) != match_header
                    raise "unexpected #{match_header}"
                end
    
                header_downcase = match_header.downcase
                if should_continue_add_header_dir
                    if header_downcase.include? ".framework/"
                        framework_name = File.basename(header_downcase.split(".framework/")[0])
                        if import_file_path.downcase == framework_name + "/" + File.basename(header_downcase)
                            should_continue_add_header_dir = false
                        end
                    end
                end
                if should_continue_add_header_dir
                    if header_downcase == import_file_path.downcase
                        should_continue_add_header_dir = false
                    end
                end
                if should_continue_add_header_dir
                    file_header_dirs = []
                    file_header_dirs = file_header_dirs + target_header_dirs
                    file_header_dirs = file_header_dirs + file_includes_hash[file].sort.to_a
                    if import_file_path.include? "/" and not import_file_path.include? "../" and match_header.end_with? "/" + import_file_path
                        header_dir = match_header.gsub(/\/#{import_file_path}$/, "")
                        file_header_dirs.push header_dir
                    end
                    file_header_dirs.uniq.each do | header_dir |
                        header = header_dir + "/" + import_file_path
                        header = FileFilter.get_exist_expand_path(header)
                        if header
                            next unless match_header.downcase == header.downcase
                            
                            break if header_dir.downcase == File.dirname(file).downcase and not is_angled_import
    
                            if import_file_path.start_with? "../" and import_file_path.scan("../").size == 1 and import_file_path.scan("/").size > 1
                                header_dir = File.dirname(header_dir) + "/" + import_file_path.split("../")[1].split("/")[0]
                            end
    
                            header_dir = FileFilter.get_exist_expand_path(header_dir)

                            FileLogger.add_verbose_log "#{file} add header_dir: #{header_dir} for #{match_header} #{import_file_path}"
                            file_includes_hash[file].add header_dir 
    
                            should_continue_add_header_dir = false
                            break
                        end
                    end
                end

                if should_continue_add_header_dir
                    binding.pry
                    raise "unexpected #{file} (#{import_file_path}) not found dir"
                end

                file_headers_hash[file].add match_header

                parse_dependency_for_file(match_header, nil, file_headers_hash, file_includes_hash, file_extras_hash, total_public_headermap, target_private_headermap, target_header_dirs, target_framework_dirs)
            end
        end
        file_headers_hash[file].sort.each do | header |
            file_headers_hash[file].merge file_headers_hash[header] if file_headers_hash[header]
            file_includes_hash[file].merge file_includes_hash[header] if file_includes_hash[header]
            file_extras_hash[file].merge file_extras_hash[header] if file_extras_hash[header]
        end
    end

    def analyze(target_info_hash_for_xcode)

        analyze_result = {}

        total_public_headermap = {}
        total_header_namspace_hash = {}
        total_header_module_hash = {}
        total_user_modules = Set.new
        
        target_info_hash_for_xcode.each do | target_name, info_hash |
            product_module_name = info_hash[:product_module_name]
            next unless product_module_name
            total_user_modules.add product_module_name
            target_public_headermap = info_hash[:target_public_headermap]
            if target_public_headermap
                target_public_headermap.each do | key, file_path |
                    next unless file_path and file_path.size > 0
                    total_public_headermap[key] = Set.new unless total_public_headermap[key]
                    total_public_headermap[key].add file_path
                    if key.split("/")[0] == product_module_name.downcase
                        if total_header_namspace_hash[file_path] and total_header_namspace_hash[file_path] != product_module_name
                            binding.pry
                        end
                        total_header_namspace_hash[file_path] = product_module_name
                        total_header_module_hash[file_path] = product_module_name
                    end
                end
            end
        end
        target_info_hash_for_xcode.each do | target_name, info_hash |
            target_private_headermap = info_hash[:target_private_headermap]
            product_module_name = info_hash[:product_module_name]
            if target_private_headermap
                target_private_headermap.each do | key, file_path |
                    next unless file_path and file_path.size > 0
                    if total_header_namspace_hash[file_path]
                        next
                    end
                    if product_module_name and key.split("/")[0] == product_module_name.downcase
                        total_header_namspace_hash[file_path] = product_module_name
                    end
                end
            end
        end
        target_info_hash_for_xcode.each do | target_name, info_hash |
            target_private_headermap = info_hash[:target_private_headermap]
            if target_private_headermap
                target_private_headermap.each do | key, file_path |
                    next unless file_path and file_path.size > 0
                    if total_header_namspace_hash[file_path]
                        next
                    end
                    total_header_namspace_hash[file_path] = ""
                end
            end
        end
        analyze_result[:total_header_namspace_hash] = total_header_namspace_hash
        analyze_result[:total_header_module_hash] = total_header_module_hash
        analyze_result[:total_user_modules] = total_user_modules

        total_system_weak_frameworks = target_info_hash_for_xcode.map{|e|e[1][:target_links_hash][:system_weak_frameworks].to_a}.flatten.to_set

        target_info_hash_for_xcode.each do | target_name, info_hash |
            pch = info_hash[:pch]
            extname_sources_hash = info_hash[:extname_sources_hash]

            target_private_headermap = info_hash[:target_private_headermap]

            target_header_dirs = info_hash[:target_header_dirs]
            target_framework_dirs = info_hash[:target_framework_dirs]

            extname_sources_hash.each do | extname, files_hash |
                extname_analyze_result = KeyValueStore.get_key_value_store_in_container(analyze_result, extname)
                file_headers_hash = KeyValueStore.get_key_value_store_in_container(extname_analyze_result, :file_headers_hash)
                file_includes_hash = KeyValueStore.get_key_value_store_in_container(extname_analyze_result, :file_includes_hash)
                file_extras_hash = KeyValueStore.get_key_value_store_in_container(extname_analyze_result, :file_extras_hash)
                file_swift_system_modules_hash = KeyValueStore.get_key_value_store_in_container(extname_analyze_result, :file_swift_system_modules_hash)
                file_swift_user_modules_hash = KeyValueStore.get_key_value_store_in_container(extname_analyze_result, :file_swift_user_modules_hash)

                if FileFilter.get_source_file_extnames_without_swift.include? extname
                    file_pch = nil
                    if FileFilter.get_objc_source_file_extnames.include? extname or FileFilter.get_cpp_source_file_extnames.include? extname
                        file_pch = pch
                    end
                    if file_pch
                        parse_dependency_for_file(file_pch, nil, file_headers_hash, file_includes_hash, file_extras_hash, total_public_headermap, target_private_headermap, target_header_dirs, target_framework_dirs)
                    end
                    files_hash.each do | file, file_hash |
                        parse_dependency_for_file(file, file_pch, file_headers_hash, file_includes_hash, file_extras_hash, total_public_headermap, target_private_headermap, target_header_dirs, target_framework_dirs)
                    end

                    if FileFilter.get_pure_objc_source_file_extnames.include? extname
                        if info_hash[:swift_objc_bridging_header]
                            file = info_hash[:swift_objc_bridging_header]
                            if not file_headers_hash.has_key? file
                                parse_dependency_for_file(file, nil, file_headers_hash, file_includes_hash, file_extras_hash, total_public_headermap, target_private_headermap, target_header_dirs, target_framework_dirs)
                            end
                        end
                    end
                end

                if FileFilter.get_swift_source_file_extnames.include? extname
                    files_hash.each do | file, file_hash |
                        swift_system_modules, swift_user_modules = parse_import_for_swift_file(file, total_user_modules)
                        file_swift_system_modules_hash[file] = Set.new unless file_swift_system_modules_hash[file]
                        file_swift_system_modules_hash[file].merge swift_system_modules

                        file_swift_user_modules_hash[file] = Set.new unless file_swift_user_modules_hash[file]
                        file_swift_user_modules_hash[file].merge swift_user_modules
                    end
                end
            end

            target_links_hash = info_hash[:target_links_hash]
            info_hash[:objc_modules] = Set.new
            extname_sources_hash.each do | extname, files_hash |
                extname_analyze_result = KeyValueStore.get_key_value_store_in_container(analyze_result, extname)

                if FileFilter.get_swift_source_file_extnames.include? extname
                    file_swift_system_modules_hash = KeyValueStore.get_key_value_store_in_container(extname_analyze_result, :file_swift_system_modules_hash)
                    files_hash.each do | file, file_hash |
                        file_swift_system_modules_hash[file].each do | framework_name |
                            if total_system_weak_frameworks.include? framework_name
                                target_links_hash[:system_weak_frameworks].add framework_name
                            else
                                target_links_hash[:system_frameworks].add framework_name
                            end
                        end
                    end
                end
                
                file_extras_hash = KeyValueStore.get_key_value_store_in_container(extname_analyze_result, :file_extras_hash)
                files_hash.each do | file, file_hash |
                    next unless file_extras_hash[file]
                    file_extras_hash[file].each do | extra |                        
                        framework_name = nil
                        module_name = nil
                        if extra.start_with? "@import "
                            module_name = extra.sub("@import ", "")
                        else
                            framework_name = extra
                        end

                        if framework_name
                            if total_system_weak_frameworks.include? framework_name
                                target_links_hash[:system_weak_frameworks].add framework_name
                            else
                                target_links_hash[:system_frameworks].add framework_name
                            end
                        end
                        if module_name
                            info_hash[:objc_modules].add module_name
                        end
                    end
                end
                
            end
        end

        return analyze_result
    end
end