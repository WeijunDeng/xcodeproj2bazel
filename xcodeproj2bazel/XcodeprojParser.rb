require 'xcodeproj'
require 'pry'
require 'i18n'

class XcodeprojParser
    def get_project(project_path)
        project = Xcodeproj::Project.open(project_path)
        return project
    end

    def get_projects(workspace_path, input_project_path)
        input_projects = []
        project_paths = Set.new
        if workspace_path
            workspace = Xcodeproj::Workspace::new_from_xcworkspace(workspace_path)    
            workspace.file_references.each do | project_ref |
                path = File.dirname(workspace_path) + "/" + project_ref.path
                path = FileFilter.get_exist_expand_path_dir(path)
                next unless path
                next if project_paths.include? path
                project_paths.add path
                project = get_project(path)
                input_projects.push project
            end
        elsif input_project_path
            path = FileFilter.get_exist_expand_path_dir(input_project_path)
            binding.pry unless path
            project_paths.add path
            project = get_project(path)
            input_projects.push project
        end
        binding.pry unless input_projects.size > 0

        output_projects = input_projects

        input_projects.each do | input_project |
            wrapper_project_paths = get_wrapper_project_paths(input_project)
            wrapper_project_paths.each do | path |
                path = FileFilter.get_exist_expand_path_dir(path)
                next unless path
                next if project_paths.include? path
                project_paths.add path
                project = get_project(path)
                output_projects.push project
            end
        end

        return output_projects
    end

    def get_wrapper_project_paths(project)
        wrapper_projects = project.files.select{|file|file.last_known_file_type=="wrapper.pb-project"}
        wrapper_project_paths = []
        wrapper_projects.each do | wrapper_project_file |
            wrapper_project_file_path = wrapper_project_file.real_path.to_s
            wrapper_project_paths.push wrapper_project_file_path
        end
        return wrapper_project_paths.uniq
    end

    def get_file_paths_from_build_file(file)
        return get_file_paths_from_file_ref(file.file_ref)
    end

    def get_file_refs_from_file_ref(file_ref)
        return [] unless file_ref

        file_refs = []
        if file_ref.class == Xcodeproj::Project::Object::PBXVariantGroup
            file_refs = file_ref.files
        elsif file_ref.class == Xcodeproj::Project::Object::PBXFileReference
            file_refs = [file_ref]
        else
            raise "unsupported #{file_ref.class}"
        end
        return file_refs
    end

    def get_file_paths_from_file_ref(file_ref)
        file_paths = []
        get_file_refs_from_file_ref(file_ref).each do | ref |
            file_path = nil
            file_path = ref.real_path.to_s
            if ref.parent.class == Xcodeproj::Project::Object::PBXGroup
                new_file_path = ref.parent.real_path.to_s + "/" + ref.path.to_s
                if File.exist? new_file_path
                    file_path = new_file_path
                end
            end
        
            file_path = FileFilter.get_exist_expand_path(file_path)
            file_paths.push file_path if file_path
        end

        return file_paths
    end

    def parse_xcconfig_variables(xcconfig_file_path, variable_hash, xcconfig_file_paths)
        return if xcconfig_file_paths.include? xcconfig_file_path
        xcconfig_file_paths.add xcconfig_file_path
        content = File.read(xcconfig_file_path)
        content.each_line do | line |
            line = line.strip
            next if line.size == 0
            next if line.start_with? "//"
            # ASSETCATALOG_COMPILER_APPICON_NAME = MyAppIcon // This is a comment. 
            line = line.gsub(/\/\/.*/, "")
            line = line.strip
            next if line.size == 0
            # #include "MyOtherConfigFile.xcconfig"
            # #include? "MyOtherConfigFile.xcconfig"
            # #include "../MyOtherConfigFile.xcconfig"    // In the parent directory.
            # #include "/Users/MyUserName/Desktop/MyOtherConfigFile.xcconfig" // At the specific path.
            import_file_path_match = line.match(/^#include\??\s*\"(.+?)\"/)
            if import_file_path_match
                import_file_path = import_file_path_match[1]
                unless File.exist? import_file_path
                    file_path = File.dirname(xcconfig_file_path) + "/" + import_file_path
                    import_file_path = file_path if File.exist? file_path
                end
                
                if File.exist? import_file_path
                    parse_xcconfig_variables(import_file_path, variable_hash, xcconfig_file_paths)
                else
                    unless line.start_with? "#include?"
                        binding.pry
                    end
                end
                next
            end
            next if line.start_with? "#"
            # https://developer.apple.com/documentation/xcode/adding-a-build-configuration-file-to-your-project?changes=l_3
            # OTHER_LDFLAGS[arch=x86_64] = -lncurses
            # OTHER_LDFLAGS[sdk=macos*][arch=x86_64] = -lncurses
            # CONFIGURATION_BUILD_DIR = $(BUILD_DIR)/$(CONFIGURATION)$(EFFECTIVE_PLATFORM_NAME)
            # OTHER_SWIFT_FLAGS = $(inherited) -v
            match_result = line.match(/(\w+(?:\[[\w\*]+=[\w\*]+\])*)\s*=(.*)/)
            binding.pry unless match_result
            key = match_result[1].strip
            value = match_result[2].strip
            key = filter_build_settings_condition_key(key)
            variable_hash[key] = value if key
        end
    end
    
    def get_build_settings_variables(build_configurations, parent_variable_hash, project, target)
        # https://developer.apple.com/documentation/xcode/configuring-the-build-settings-of-a-target?changes=la_3
        # The hierarchy of precedence is:
        # Target-level values.
        # Configuration settings file values mapped to a target.
        # Project-level values.
        # Configuration settings file mapped to the project.
        # System default values.
        variable_hash = {}
        build_configurations.each do | config |
            next unless config.name == DynamicConfig.get_build_configuration_name
            config.build_settings.each do | key, value |
                key = filter_build_settings_condition_key(key)
                variable_hash[key] = value if key
            end
        end
        xcconfig_variable_hash = {}
        xcconfig_file_paths = Set.new
        build_configurations.each do | config |
            next unless config.name == DynamicConfig.get_build_configuration_name
            if config.base_configuration_reference
                xcconfig_file_path = config.base_configuration_reference.real_path.to_s
                if File.exist? xcconfig_file_path
                    parse_xcconfig_variables(xcconfig_file_path, xcconfig_variable_hash, xcconfig_file_paths)
                end
            end
        end
        xcconfig_variable_hash.keys.each do | key |
            unless variable_hash[key]
                variable_hash[key] = xcconfig_variable_hash[key]
            end
        end
        parent_variable_hash.keys.each do | key |
            unless variable_hash[key]
                variable_hash[key] = parent_variable_hash[key]
            end
        end

        variable_hash.keys.each do | key |
            value = variable_hash[key]
            inherited_values = []
            inherited_value = xcconfig_variable_hash[key]
            inherited_values.push inherited_value if inherited_value and inherited_value != value
            inherited_value = parent_variable_hash[key]
            inherited_values.push inherited_value if inherited_value and inherited_value != value

            inherited_values.push ""
            inherited_values.each do | inherited_value |
                if value.class == Array
                    if inherited_value.class == String
                        value = value.map { |x| x.gsub("$(inherited)", inherited_value) }
                    elsif inherited_value.class == Array
                        value = value.map { |x| x == "$(inherited)" ? inherited_value : x }.flatten
                    else
                        binding.pry
                    end
                elsif value.class == String
                    if inherited_value.class == String
                        value = value.gsub("$(inherited)", inherited_value)
                    elsif inherited_value.class == Array
                        value = value.gsub("$(inherited)", inherited_value.join(" "))
                    else
                        binding.pry
                    end
                else
                    binding.pry
                end
            end
            variable_hash[key] = value
        end

        if target
            unless variable_hash["CONFIGURATION"]
                variable_hash["CONFIGURATION"] = DynamicConfig.get_build_configuration_name
            end
            unless variable_hash["EFFECTIVE_PLATFORM_NAME"]
                variable_hash["EFFECTIVE_PLATFORM_NAME"] = DynamicConfig.get_build_effective_platform_name
            end
            unless variable_hash["TARGET_NAME"]
                variable_hash["TARGET_NAME"] = target.name
            end
            unless variable_hash["OTHER_CFLAGS"]
                variable_hash["OTHER_CFLAGS"] = ""
            end
            unless variable_hash["OTHER_CPLUSPLUSFLAGS"]
                variable_hash["OTHER_CPLUSPLUSFLAGS"] = ""
            end
            unless variable_hash["WARNING_CFLAGS"]
                variable_hash["WARNING_CFLAGS"] = ""
            end
            unless variable_hash["OTHER_SWIFT_FLAGS"]
                variable_hash["OTHER_SWIFT_FLAGS"] = ""
            end
            unless variable_hash["SRCROOT"]
                variable_hash["SRCROOT"] = File.dirname(project.path.to_s)
            end
            unless variable_hash["PROJECT_DIR"]
                variable_hash["PROJECT_DIR"] = File.dirname(project.path.to_s)
            end
        end

        return variable_hash
    end

    def filter_build_settings_condition_key(key)
        if key.include? "["
            build_settings_condition_hash = DynamicConfig.get_build_settings_condition
            key.split("[")[1..-1].each do | split_item |
                k = split_item.split("=")[0]
                v = split_item.split("=")[1][0..-2]
                binding.pry unless build_settings_condition_hash.has_key? k
                unless build_settings_condition_hash[k] == v
                    unless build_settings_condition_hash[k].match(/^#{v.gsub("*", ".*")}$/)
                        key = nil
                        break
                    end
                end
            end
            key = key.split("[")[0] if key
        end
        return key
    end

    # https://github.com/CocoaPods/Core/blob/c6ac388ee43f0782fdb8e32386f41f96dbe29082/lib/cocoapods-core/specification.rb#L205
    def c99ext_identifier(name)
        return nil if name.nil?
        I18n.config.available_locales = :en
        I18n.transliterate(name).gsub(/^([0-9])/, '_\1').
          gsub(/[^a-zA-Z0-9_]/, '_').gsub(/_+/, '_')
    end

    # http://codeworkshop.net/posts/xcode-build-setting-transformations
    def rfc1034_identifier(name)
        return name.gsub(/\s+/, "-")
    end

    def get_target_build_settings(target, variable_hash, key, multi_value)
        target_build_settings = []
        if variable_hash[key]
            rewrite_count = 0
            while (variable_hash[key].to_s.include? "$")
                has_rewrite = false
                value = variable_hash[key]
                variable_hash.keys.each do | key2 |
                    value2 = variable_hash[key2]
                    next if key == key2
                    if value == "$(#{key2})" or value == "${#{key2}}"
                        value = value2
                        next
                    end

                    if value2.class == String
                        if value.class == Array
                            value = value.map { | x | x.gsub("$(#{key2})", value2).gsub("${#{key2}}", value2) }
                            unless value2.include? "$"
                                value = value.map { | x | x.gsub("$(#{key2}:c99extidentifier)", c99ext_identifier(value2)).gsub("${#{key2}:c99extidentifier}", c99ext_identifier(value2)) }
                                value = value.map { | x | x.gsub("$(#{key2}:rfc1034identifier)", rfc1034_identifier(value2)).gsub("${#{key2}:rfc1034identifier}", rfc1034_identifier(value2)) }
                            end
                        elsif value.class == String
                            value = value.gsub("$(#{key2})", value2).gsub("${#{key2}}", value2)
                            unless value2.include? "$"
                                value = value.gsub("$(#{key2}:c99extidentifier)", c99ext_identifier(value2)).gsub("${#{key2}:c99extidentifier}", c99ext_identifier(value2))
                                value = value.gsub("$(#{key2}:rfc1034identifier)", rfc1034_identifier(value2)).gsub("${#{key2}:rfc1034identifier}", rfc1034_identifier(value2))
                            end
                        else
                            binding.pry
                        end
                    end
                end
                if variable_hash[key] != value
                    has_rewrite = true
                    variable_hash[key] = value
                end                  
                break unless has_rewrite
                
                rewrite_count = rewrite_count + 1
                if rewrite_count > 10
                    binding.pry
                end
            end
    
            if variable_hash[key].size > 0
                target_build_settings.push variable_hash[key]
            end
        end
        binding.pry if target_build_settings.to_s.include? ":rfc1034identifier"
        binding.pry if target_build_settings.to_s.include? ":c99extidentifier"

        target_build_settings = target_build_settings.flatten.map{|x|x.strip}.select{|x|x.size>0}

        if multi_value
            target_build_settings = split_multi_values(target_build_settings)
        else
            binding.pry if target_build_settings.size > 1
        end
        return target_build_settings
    end

    def split_multi_values(values)
        split_values = []
        values.flatten.each do | value |
            while (value.size > 0)
                normal_chars = /\w\-\+\$\{\}\(\)\/\.\*=@/
                match_result = value.match(/^[#{normal_chars}]+(?: |$)/)
                if match_result
                    match_value = match_result[0].strip
                    split_values.push match_value
                    value = value[match_result[0].size..-1].strip
                    next
                end
                match_result = value.match(/^(?:[#{normal_chars}]*\"[#{normal_chars} ]*\"[#{normal_chars}]*)+(?: |$)/)
                if match_result
                    match_value = match_result[0].strip
                    if match_value.include? " "
                        match_value = match_value.gsub("\"", "\\\"")
                    else
                        match_value = match_value.gsub("\"", "")
                    end
                    split_values.push match_value
                    value = value[match_result[0].size..-1].strip
                    next
                end
                match_result = value.match(/^(?:[#{normal_chars}]*\'[#{normal_chars}\"]*\'[#{normal_chars}]*)+(?: |$)/)
                if match_result
                    match_value = match_result[0].strip
                    match_value = match_value.gsub("\"", "\\\"")
                    if match_value.match(/^\'[#{normal_chars}]*\'$/)
                        match_value = match_value.gsub("'", "")
                    end
                    split_values.push match_value
                    value = value[match_result[0].size..-1].strip
                    next
                end
                match_result = value.match(/^\"[#{normal_chars}]+$/)
                if match_result
                    match_value = match_result[0].gsub("\"", "").strip
                    split_values.push match_value
                    value = value[match_result[0].size..-1].strip
                    next
                end
                binding.pry
            end
        end
        return split_values
    end

    def merge_flags(flags)
        (0..(flags.size-1)).each do | flag_i |
            if flag_i + 1 < flags.size
                if flags[flag_i].start_with? "-" and not flags[flag_i].include? "="
                    if not flags[flag_i+1].start_with? "-"
                        flags[flag_i] = flags[flag_i] + " " + flags[flag_i+1]
                        flags[flag_i+1] = ""
                    end
                end
            end
        end
        flags.delete_if{|x|x.size==0}
    end

    def get_exist_build_settings_path(target, variable_hash, path)
        binding.pry if path.include? "'"
        binding.pry if path.include? "\""
        origin_path = path

        binding.pry if get_target_build_settings(target, variable_hash, "EXCLUDED_RECURSIVE_SEARCH_PATH_SUBDIRECTORIES", true).size > 0

        recursive = false
        if path.end_with? "/**"
            recursive = true
            path = File.dirname(path)
        end

        new_path = get_target_src_root(target, variable_hash) + "/" + path
        if File.exist? new_path
            path = new_path
        end

        path = FileFilter.get_exist_expand_path(path)
        if path
            if recursive
                # FIXME, support EXCLUDED_RECURSIVE_SEARCH_PATH_SUBDIRECTORIES
                dirs = FileFilter.get_recursive_dirs(path)
                return dirs
            else
                return path
            end
        end

        if origin_path.start_with? "/usr/"
            if File.exist? origin_path
                return origin_path
            end
        end

        if File.exist? origin_path
            binding.pry # FIXME
        end

        return nil
    end

    def get_project_header_map(project)
        project_header_map = {}
        project.files.each do | file_ref |
            file_paths = get_file_paths_from_file_ref(file_ref)
            file_paths.each do | file_path |
                next unless FileFilter.get_header_file_extnames.include? File.extname(file_path).downcase

                key = File.basename(file_path).downcase
                project_header_map[key] = Set.new unless project_header_map[key]
                project_header_map[key].add file_path
            end
        end
        return project_header_map
    end

    def get_target_header_map(target, use_header_map, product_name)
        target_public_header_map = {}
        target_private_header_map = {}
        target_headers = []
        namespace = nil
        if use_header_map
            namespace = product_name
        end
        target.headers_build_phase.files.each do | file |
            file_paths = get_file_paths_from_build_file(file)
            file_paths.each do | file_path |
                file_path = FileFilter.get_real_exist_expand_path_file(file_path)
                binding.pry unless file_path
                extname = File.extname(file_path).downcase
                unless FileFilter.get_header_file_extnames.include? extname
                    binding.pry
                end
                target_headers.push file_path
                is_public = false
                if file.settings
                    file.settings.each do | k, v |
                        binding.pry if k != "ATTRIBUTES"
                        if v and v.include? "Public"
                            is_public = true
                        end
                    end
                end

                if use_header_map
                    if is_public
                        key = (namespace + "/" + File.basename(file_path)).downcase
                        target_public_header_map[key] = Set.new unless target_public_header_map[key]
                        target_public_header_map[key].add file_path
                        binding.pry if target_public_header_map[key].size > 1
                    end

                    key = (namespace + "/" + File.basename(file_path)).downcase
                    target_private_header_map[key] = Set.new unless target_private_header_map[key]
                    target_private_header_map[key].add file_path

                    key = (File.basename(file_path)).downcase
                    target_private_header_map[key] = Set.new unless target_private_header_map[key]
                    target_private_header_map[key].add file_path
                end
            end           
        end

        return target_headers.uniq, namespace, target_public_header_map, target_private_header_map
    end

    def get_target_source_files(target, variable_hash)
        flags_sources_hash = {}
        clang_enable_objc_arc = false
        clang_enable_objc_arc_settings = get_target_build_settings(target, variable_hash, "CLANG_ENABLE_OBJC_ARC", false)
        if clang_enable_objc_arc_settings.size == 1 and clang_enable_objc_arc_settings[0].upcase == "YES"
            clang_enable_objc_arc = true
        end
        has_swift = false
        target.source_build_phase.files.each do | file |
            file_paths = get_file_paths_from_build_file(file)
            file_paths.each do | file_path |
                extname = File.extname(file_path).downcase
                if FileFilter.get_source_file_extnames_swift.include? extname
                    has_swift = true
                end
                next if FileFilter.get_source_file_extnames_ignore.include? extname
                binding.pry unless FileFilter.get_source_file_extnames_all.include? extname
                binding.pry unless file_path and File.exist? file_path and File.file? file_path

                file_compiler_flags = ""
                if file.settings
                    file.settings.each do | k, v |
                        if k == "COMPILER_FLAGS"
                            binding.pry unless v.class == String
                            file_compiler_flags = v
                        else
                            binding.pry
                        end
                    end
                end
                file_compiler_flags = file_compiler_flags.gsub("$(inherited)", "").strip
                file_compiler_flags = split_multi_values([file_compiler_flags])
                file_compiler_flags = merge_flags(file_compiler_flags).uniq
                fileflags = [extname, file_compiler_flags]
                flags_sources_hash[fileflags] = Set.new unless flags_sources_hash[fileflags]
                flags_sources_hash[fileflags].add file_path
            end
        end
        return flags_sources_hash, clang_enable_objc_arc, has_swift
    end

    def get_target_resources(target)
        resources_files = Set.new
        dependency_resource_product_file_names = Set.new
        (target.resources_build_phase.files + target.source_build_phase.files).each do | file |
            next unless file.file_ref
            file_paths = get_file_paths_from_build_file(file)
            if file_paths.size > 0
                file_paths.each do | file_path |
                    extname = File.extname(file_path).downcase
                    next if FileFilter.get_source_file_extnames_all.include? extname
                    next if FileFilter.get_header_file_extnames.include? extname
                    resources_files.add file_path
                end
                next
            end
            file_path = file.file_ref.real_path.to_s
            if file_path.start_with? "${BUILT_PRODUCTS_DIR}/"
                product_file_name = File.basename(file_path)
                dependency_resource_product_file_names.add product_file_name
                next
            end
            binding.pry
        end
        return resources_files, dependency_resource_product_file_names
    end

    def get_target_header_dirs(target, variable_hash, target_c_compile_flags, target_cxx_compile_flags)
        target_header_dirs = []
        # TODO, split HEADER_SEARCH_PATHS and USER_HEADER_SEARCH_PATHS
        search_paths = get_target_build_settings(target, variable_hash, "HEADER_SEARCH_PATHS", true) + get_target_build_settings(target, variable_hash, "USER_HEADER_SEARCH_PATHS", true)
        [target_c_compile_flags, target_cxx_compile_flags].each do | flags |
            if flags.size > 0
                (0..(flags.size-1)).each do | flag_i |
                    flag = flags[flag_i]
                    if flag == "-isystem" and flag_i + 1 < flags.size
                        search_paths.push flags[flag_i+1]
                        flags[flag_i] = ""
                        flags[flag_i+1] = ""
                        next
                    end
                    binding.pry if flag.start_with? "-isystem"
                    binding.pry if flag.start_with? "-I"
                    binding.pry if flag.start_with? "-iquote"
                    binding.pry if flag.start_with? "-isysroot"
                    binding.pry if flag.start_with? "-include"
                end
                flags.delete_if{|x|x.size==0}
            end
        end
        search_paths.push get_target_src_root(target, variable_hash)
        search_paths.each do | origin_search_path |
            search_path = get_exist_build_settings_path(target, variable_hash, origin_search_path)
            if search_path and search_path.size > 0
                if search_path.class == Array
                    target_header_dirs = target_header_dirs + search_path
                else
                    target_header_dirs.push search_path
                end
                next
            end
            # beta
            target_header_dirs.push [:unknown, origin_search_path]
        end

        return target_header_dirs.uniq
    end
    
    def get_target_framework_dirs(target, variable_hash, target_link_flags, target_c_compile_flags, target_cxx_compile_flags)
        target_framework_dirs = []
        search_paths = get_target_build_settings(target, variable_hash, "FRAMEWORK_SEARCH_PATHS", true)
        flags = target_link_flags
        if flags.size > 0
            (0..(flags.size-1)).each do | flag_i |
                flag = flags[flag_i]
                if flag == "-F" and flag_i + 1< flags.size
                    search_paths.push flags[flag_i+1]
                    flags[flag_i] = ""
                    flags[flag_i+1] = ""
                    next
                end
                binding.pry if flag.start_with? "-F"
            end
            flags.delete_if{|x|x.size==0}
        end
        [target_c_compile_flags, target_cxx_compile_flags].each do | flags |
            if flags.size > 0
                (0..(flags.size-1)).each do | flag_i |
                    flag = flags[flag_i]
                    if flag == "-iframework" and flag_i + 1 < flags.size
                        search_paths.push flags[flag_i+1]
                        flags[flag_i] = ""
                        flags[flag_i+1] = ""
                        next
                    end
                    binding.pry if flag.start_with? "-iframework"
                end
                flags.delete_if{|x|x.size==0}
            end
        end

        search_paths.uniq.each do | search_path |
            search_path = get_exist_build_settings_path(target, variable_hash, search_path)
            if search_path and search_path.size > 0
                if search_path.class == Array
                    target_framework_dirs = (target_framework_dirs + search_path).uniq
                else
                    target_framework_dirs.push search_path unless target_framework_dirs.include? search_path
                end
            end
        end
        return target_framework_dirs
    end
    
    def get_target_library_dirs(target, variable_hash, target_link_flags)
        target_library_dirs = []
        search_paths = get_target_build_settings(target, variable_hash, "LIBRARY_SEARCH_PATHS", true)
        flags = target_link_flags
        if flags.size > 0
            (0..(flags.size-1)).each do | flag_i |
                flag = flags[flag_i]
                if flag == "-L" and flag_i + 1 < flags.size
                    search_paths.push flags[flag_i+1]
                    flags[flag_i] = ""
                    flags[flag_i+1] = ""
                    next
                end
                binding.pry if flag.start_with? "-L"
            end
            flags.delete_if{|x|x.size==0}
        end
        search_paths.uniq.each do | search_path |
            search_path = get_exist_build_settings_path(target, variable_hash, search_path)
            if search_path and search_path.size > 0
                if search_path.class == Array
                    target_library_dirs = (target_library_dirs + search_path).uniq
                else
                    target_library_dirs.push search_path unless target_library_dirs.include? search_path
                end
            end
        end
    
        return target_library_dirs
    end

    def get_target_use_header_map(target, variable_hash)
        target_build_settings = get_target_build_settings(target, variable_hash, "USE_HEADERMAP", false)
        if target_build_settings.size == 0
            return true
        end
        if target_build_settings.size == 1
            return false if target_build_settings[0].upcase == "NO"
            return true if target_build_settings[0].upcase == "YES"
        end
        raise "unexpected USE_HEADERMAP #{target_build_settings}"
        return true
    end
    
    def get_target_compile_flags(target, variable_hash)
        target_c_compile_flags = get_target_build_settings(target, variable_hash, "OTHER_CFLAGS", true)
        target_cxx_compile_flags = get_target_build_settings(target, variable_hash, "OTHER_CPLUSPLUSFLAGS", true)
        target_c_warning_flags = get_target_build_settings(target, variable_hash, "WARNING_CFLAGS", true)
        target_swift_compile_flags = get_target_build_settings(target, variable_hash, "OTHER_SWIFT_FLAGS", true)

        gcc_c_language_standard_settings = get_target_build_settings(target, variable_hash, "GCC_C_LANGUAGE_STANDARD", false)
        clang_cxx_language_standard_settings = get_target_build_settings(target, variable_hash, "CLANG_CXX_LANGUAGE_STANDARD", false)
        clang_cxx_library_settings = get_target_build_settings(target, variable_hash, "CLANG_CXX_LIBRARY", false)

        gcc_c_language_standard_settings.each do | value |
            value = "-std=" + value
            target_c_compile_flags.push value unless target_c_compile_flags.include? value
        end
        clang_cxx_language_standard_settings.each do | value |
            value = "-std=" + value
            target_cxx_compile_flags.push value unless target_cxx_compile_flags.include? value
        end
        clang_cxx_library_settings.each do | value |
            value = "-stdlib=" + value
            target_cxx_compile_flags.push value unless target_cxx_compile_flags.include? value
        end
        settings = get_target_build_settings(target, variable_hash, "CLANG_MODULES_AUTOLINK", false)
        if settings.size > 0
            binding.pry
        end
        return target_c_compile_flags, target_cxx_compile_flags, target_c_warning_flags, target_swift_compile_flags
    end
    
    def get_target_link_flags(target, variable_hash)
        if target.product_type == "com.apple.product-type.bundle"
            return []
        end
        target_link_flags = get_target_build_settings(target, variable_hash, "OTHER_LDFLAGS", true)

        dead_code_stripping_settings = get_target_build_settings(target, variable_hash, "DEAD_CODE_STRIPPING", false)
        unless dead_code_stripping_settings[-1] and dead_code_stripping_settings[-1].upcase == "NO"
            target_link_flags.push "-dead_strip" unless target_link_flags.include? "-dead_strip"
        end
        return target_link_flags
    end

    def get_target_links_hash(target, variable_hash, target_library_dirs, target_framework_dirs, target_link_flags, product_file_name)
        user_framework_paths = []
        user_library_paths = []
        system_frameworks = Set.new
        system_weak_frameworks = Set.new
        system_libraries = Set.new
        dependency_target_product_file_names = []
    
        frameworks_build_files = []
    
        target.copy_files_build_phases.each do | build_phase |
            if build_phase.dst_subfolder_spec == "10" or # Framework 
                build_phase.dst_subfolder_spec == "13" # Plugin
                frameworks_build_files = frameworks_build_files + build_phase.files
            end
        end
    
        if target.frameworks_build_phases
            frameworks_build_files = frameworks_build_files + target.frameworks_build_phases.files
        end
    
        frameworks_build_files.each do | file |
            file_paths = get_file_paths_from_build_file(file)
            if file_paths.size > 0
                file_paths.each do | file_path |
                    extname = File.extname(file_path).downcase
                    if extname == ".a"
                        user_library_paths.push file_path
                    elsif extname == ".framework"
                        user_framework_paths.push file_path
                    elsif extname == ".xcframework"
                        xcframework_info = FileFilter.get_match_xcframework_info(file_path)
                        binding.pry unless xcframework_info
                        library_path = xcframework_info[:LibraryPath]
                        binding.pry unless library_path
                        if File.extname(library_path).downcase == ".framework"
                            library_path = FileFilter.get_exist_expand_path_dir(library_path)
                            binding.pry unless library_path
                            user_framework_paths.push library_path
                        elsif File.extname(library_path).downcase == ".a"
                            library_path = FileFilter.get_exist_expand_path_file(library_path)
                            binding.pry unless library_path
                            user_library_paths.push library_path
                        else
                            binding.pry
                        end 
                    else
                        binding.pry
                    end
                end
            else
                file_path = file.file_ref.real_path.to_s
                file_dir = File.dirname(file_path)
                extname = File.extname(file_path).downcase
    
                weak_framework = false
                if file.settings and file.settings["ATTRIBUTES"]
                    if file.settings["ATTRIBUTES"].include? "Weak"
                        weak_framework = true
                    end
                end
    
                if extname == ".framework"
                    system_framework = FileFilter.get_system_framework_by_name(File.basename(file_path).split(extname)[0])
                    if system_framework
                        if weak_framework
                            system_weak_frameworks.add system_framework
                        else
                            system_frameworks.add system_framework
                        end
                    else
                        found = false
                        target_framework_dirs.each do | dir |
                            framework_path = dir + "/" + File.basename(file_path)
                            framework_path = FileFilter.get_exist_expand_path_dir(framework_path)
                            if framework_path
                                user_framework_paths.push framework_path
                                found = true
                                break
                            end
                        end
                        unless found
                            dependency_target_product_file_names.push File.basename(file_path)
                        end
                    end
                elsif extname == ".tbd"
                    system_libraries.add File.basename(file_path)
                elsif extname == ".appex" or extname == ".bundle" or extname == ".a"
                    dependency_target_product_file_names.push File.basename(file_path)
                else
                    binding.pry
                end
            end
        end
        alwayslink_product_file_names = Set.new
        flags = target_link_flags
        if flags.size > 0
            (0..(flags.size-1)).each do | flag_i |
                flag = flags[flag_i]
                binding.pry if flag.downcase.include? ".xcframework"

                if flag_i + 1 < flags.size
                    if flag == "-framework" or flag == "-weak_framework"
                        framework_name = flags[flag_i+1]
                        system_framework = FileFilter.get_system_framework_by_name(framework_name)
                        if system_framework
                            if flag == "-weak_framework"
                                system_weak_frameworks.add system_framework
                            else
                                system_frameworks.add system_framework
                            end
                        else
                            found = false
                            framework_file_name = framework_name + ".framework"
                            target_framework_dirs.each do | dir |
                                framework_path = dir + "/" + framework_file_name
                                framework_path = FileFilter.get_exist_expand_path_dir(framework_path)
                                if framework_path
                                    user_framework_paths.push framework_path
                                    found = true
                                    break
                                end
                            end
                            unless found
                                target_framework_dirs.each do | dir |
                                    Dir.glob("#{dir}/*.xcframework").sort.each do | xcframework_path | 
                                        xcframework_info = FileFilter.get_match_xcframework_info(xcframework_path)
                                        next unless xcframework_info
                                        library_path = xcframework_info[:LibraryPath]
                                        if library_path and File.basename(library_path) == framework_file_name
                                            library_path = FileFilter.get_exist_expand_path_dir(library_path)
                                            binding.pry unless library_path
                                            user_framework_paths.push library_path
                                            found = true
                                            break
                                        end
                                    end
                                    break if found
                                end
                            end
                            unless found
                                dependency_target_product_file_names.push framework_file_name
                            end
                        end
                        flags[flag_i] = ""
                        flags[flag_i+1] = ""
                        next
                    end
                end

                if flag.start_with? "-l"
                    library_name = flag.sub("-l", "")
                    system_library = FileFilter.get_system_library_by_name(library_name)
                    if system_library
                        system_libraries.add system_library
                    else
                        library_file_name = "lib" + flag.sub("-l", "") + ".a"
                        found = false
                        target_library_dirs.each do | dir |
                            library_path = dir + "/" + library_file_name
                            library_path = FileFilter.get_exist_expand_path_file(library_path)
                            if library_path
                                user_library_paths.push library_path
                                found = true
                                break
                            end
                        end
                        unless found
                            target_framework_dirs.each do | dir |
                                Dir.glob("#{dir}/*.xcframework").sort.each do | xcframework_path | 
                                    xcframework_info = FileFilter.get_match_xcframework_info(xcframework_path)
                                    next unless xcframework_info
                                    library_path = xcframework_info[:LibraryPath]
                                    if library_path and File.basename(library_path) == library_file_name
                                        library_path = FileFilter.get_exist_expand_path_file(library_path)
                                        binding.pry unless library_path
                                        user_library_paths.push library_path
                                        found = true
                                        break
                                    end
                                end
                                break if found
                            end
                        end

                        unless found
                            dependency_target_product_file_names.push library_file_name
                        end
                    end
                    flags[flag_i] = ""
                    next
                end

                force_load = (flag_i > 0 and flags[flag_i-1] == "-force_load")
                if force_load
                    flags[flag_i-1] = ""
                end
                if File.extname(File.dirname(flag)).downcase == ".framework"
                    framework_path = File.dirname(flag)
                    framework_path = FileFilter.get_exist_expand_path_dir(framework_path)
                    if framework_path
                        user_framework_paths.push framework_path
                        alwayslink_product_file_names.add File.basename(framework_path) if force_load
                    else
                        dependency_target_product_file_names.push File.basename(File.dirname(flag))
                        alwayslink_product_file_names.add File.basename(File.dirname(flag)) if force_load
                    end
                    flags[flag_i] = ""
                    next
                end
                if File.extname(flag).downcase == ".a"
                    library_path = flag
                    library_path = FileFilter.get_exist_expand_path_file(library_path)
                    if library_path
                        user_library_paths.push library_path
                        alwayslink_product_file_names.add File.basename(library_path) if force_load
                    else
                        dependency_target_product_file_names.push File.basename(flag)
                        alwayslink_product_file_names.add File.basename(flag) if force_load
                    end
                    flags[flag_i] = ""
                    next
                end
                    
                if flag == "-all_load"
                    alwayslink_product_file_names.add product_file_name
                    flags[flag_i] = ""
                    next
                end                
            end
            flags.delete_if{|x|x.size==0}
        end

        target_links_hash = {}
        target_links_hash[:user_framework_paths] = user_framework_paths.uniq
        target_links_hash[:user_library_paths] = user_library_paths.uniq
        target_links_hash[:system_frameworks] = system_frameworks
        target_links_hash[:system_weak_frameworks] = system_weak_frameworks
        target_links_hash[:system_libraries] = system_libraries
        target_links_hash[:dependency_target_product_file_names] = dependency_target_product_file_names.uniq
        target_links_hash[:alwayslink_product_file_names] = alwayslink_product_file_names

        return target_links_hash
    end

    def get_target_defines(target, variable_hash, target_c_compile_flags, target_cxx_compile_flags, target_swift_compile_flags)
        target_defines = get_target_build_settings(target, variable_hash, "GCC_PREPROCESSOR_DEFINITIONS", true)
        c_target_defines = []
        cxx_target_defines = []
        swift_target_defines = []

        [[target_c_compile_flags, c_target_defines], [target_cxx_compile_flags, cxx_target_defines], [target_swift_compile_flags, swift_target_defines]].each do | group |
            flags = group[0]
            defines = group[1]
            (0..(flags.size-1)).each do | flag_i |
                flag = flags[flag_i]
                if flag == "-D"
                    binding.pry if flag_i == flags.size
                    defines.push flags[flag_i+1]
                    flags[flag_i] = ""
                    flags[flag_i+1] = ""
                else
                    if flag.start_with? "-D"
                        defines.push flag.sub("-D", "")
                        flags[flag_i] = ""
                    end
                end
            end
            flags.delete_if{|x|x.size==0}
        end

        swift_target_defines += get_target_build_settings(target, variable_hash, "SWIFT_ACTIVE_COMPILATION_CONDITIONS", true)
        
        return target_defines.uniq, c_target_defines.uniq, cxx_target_defines.uniq, swift_target_defines.uniq
    end

    def get_target_src_root(target, variable_hash)
        settings = get_target_build_settings(target, variable_hash, "SRCROOT", false)
        result = nil
        if settings.size == 1
            result = settings[0]
            result = FileFilter.get_exist_expand_path_dir(result)
        end
        binding.pry unless result
        return result
    end

    def get_target_pch(target, variable_hash)
        pch = nil
        pch_settings = get_target_build_settings(target, variable_hash, "GCC_PREFIX_HEADER", false)
        if pch_settings.size == 1
            path = pch_settings[0]
            unless File.exist? path
                new_path = get_target_src_root(target, variable_hash) + "/" + path
                if File.exist? new_path
                    path = new_path
                end
            end
            path = FileFilter.get_real_exist_expand_path_file(path)
            if path
                pch = path
            end
        end
        return pch
    end

    def parse_target_product_info(target, variable_hash)

        product_name_settings = get_target_build_settings(target, variable_hash, "PRODUCT_NAME", false)
    
        if product_name_settings.size > 0
            if not product_name_settings[0].include? "$"
                product_name = product_name_settings[0]
            end
        end
        binding.pry unless product_name
        product_file_name = nil
        if target.product_type == "com.apple.product-type.application"
            product_file_name = product_name + ".app"
        elsif target.product_type == "com.apple.product-type.app-extension"
            product_file_name = product_name + ".appex"
        elsif target.product_type == "com.apple.product-type.framework"
            product_file_name = product_name + ".framework"
        elsif target.product_type == "com.apple.product-type.bundle"
            product_file_name = product_name + ".bundle"
        elsif target.product_type == "com.apple.product-type.library.static"
            product_file_name = "lib" + product_name + ".a"
        elsif target.product_type == "com.apple.product-type.bundle.unit-test"
            product_file_name = product_name + ".xctest"
        elsif target.product_type == "com.apple.product-type.application.watchapp2"
            product_file_name = product_name + ".app"
        elsif target.product_type == "com.apple.product-type.watchkit2-extension"
            product_file_name = product_name + ".appex"
        else
            binding.pry
            raise "unsupported #{target.product_type} #{target.name}"
        end
    
        info_plist = nil
        bundle_version = nil
        bundle_id = nil
    
        bundle_id_settings = get_target_build_settings(target, variable_hash, "PRODUCT_BUNDLE_IDENTIFIER", false)
        if bundle_id_settings.size == 1
            bundle_id = bundle_id_settings[0]
        end
        bundle_version_settings = get_target_build_settings(target, variable_hash, "CURRENT_PROJECT_VERSION", false)
        if bundle_version_settings.size == 1
            bundle_version = bundle_version_settings[0]
        end

        info_plist_settings = get_target_build_settings(target, variable_hash, "INFOPLIST_FILE", false)
        if info_plist_settings.size > 0
            info_plist = get_exist_build_settings_path(target, variable_hash, info_plist_settings[0])
            if info_plist
                info_plist_bundle_version = Open3.capture3("/usr/libexec/PlistBuddy -c \"Print :CFBundleVersion\" \"#{info_plist}\"")[0].strip
                if info_plist_bundle_version.size > 0 and not info_plist_bundle_version.include? "$"
                    bundle_version = info_plist_bundle_version
                end
                
                info_plist_bundle_id = Open3.capture3("/usr/libexec/PlistBuddy -c \"Print :CFBundleIdentifier\" \"#{info_plist}\"")[0].strip
                if info_plist_bundle_id.size > 0 and not info_plist_bundle_id.include? "$"
                    bundle_id = info_plist_bundle_id
                end
            end
        end

        binding.pry if bundle_id and bundle_id.include? "$"

        mach_o_type_settings = get_target_build_settings(target, variable_hash, "MACH_O_TYPE", false)
        mach_o_type = nil
        if mach_o_type_settings.size == 1
            mach_o_type = mach_o_type_settings[0]
        elsif mach_o_type_settings.size == 0
            if target.product_type == "com.apple.product-type.application"
                mach_o_type = "mh_execute"
            elsif target.product_type == "com.apple.product-type.app-extension"
                mach_o_type = "mh_execute"
            elsif target.product_type == "com.apple.product-type.framework"
                mach_o_type = "mh_dylib"
            elsif target.product_type == "com.apple.product-type.bundle"
                mach_o_type = "mh_bundle"
            elsif target.product_type == "com.apple.product-type.library.static"
                mach_o_type = "staticlib"
            elsif target.product_type == "com.apple.product-type.bundle.unit-test"
                mach_o_type = "mh_bundle"
            elsif target.product_type == "com.apple.product-type.application.watchapp2"
                mach_o_type = "mh_execute"
            elsif target.product_type == "com.apple.product-type.watchkit2-extension"
                mach_o_type = "mh_execute"
            else
                raise "unsupported #{target.product_type}"
            end
        end
        
        unless mach_o_type and mach_o_type.size > 0 and not mach_o_type.include? "$"
            raise "unsupported mach_o_type"
        end
    
        return product_name, product_file_name, info_plist, bundle_id, bundle_version, mach_o_type
    end

    def get_target_provisioning_profile(target, variable_hash)
        settings = get_target_build_settings(target, variable_hash, "PROVISIONING_PROFILE_SPECIFIER", false)
        if settings.size == 0
            return nil
        end
        return settings[-1]
    end

    def get_target_iphoneos_deployment_target(target, variable_hash)
        settings = get_target_build_settings(target, variable_hash, "IPHONEOS_DEPLOYMENT_TARGET", false)
        if settings.size == 0
            return nil
        end
        return settings[-1]      
    end

    def get_targe_swift_setting(target, variable_hash)
        swift_objc_bridging_header = nil
        settings = get_target_build_settings(target, variable_hash, "SWIFT_OBJC_BRIDGING_HEADER", false)
        if settings.size > 0
            swift_objc_bridging_header = get_exist_build_settings_path(target, variable_hash, settings[-1])
            unless swift_objc_bridging_header and swift_objc_bridging_header.class == String
                binding.pry
            end
        end
        return swift_objc_bridging_header
    end

    def get_targe_modules_setting(target, variable_hash, product_name, flags_sources_hash, target_c_compile_flags, target_swift_compile_flags)
        enable_modules = false
        settings = get_target_build_settings(target, variable_hash, "CLANG_ENABLE_MODULES", false)
        if settings.size == 1 and settings[0].upcase == "YES"
            enable_modules = true
        end

        defines_module = false
        settings = get_target_build_settings(target, variable_hash, "DEFINES_MODULE", false)
        if settings.size == 1 and settings[0].upcase == "YES"
            defines_module = true
        end
        product_module_name = nil
        settings = get_target_build_settings(target, variable_hash, "PRODUCT_MODULE_NAME", false)
        if settings.size == 1
            product_module_name = settings[0]
            unless product_module_name.match(/^\w+$/)
                binding.pry
            end
        end
        module_map_file = nil
        settings = get_target_build_settings(target, variable_hash, "MODULEMAP_FILE", false)
        if settings.size > 0
            module_map_file = get_exist_build_settings_path(target, variable_hash, settings[-1])
            module_map_file =  FileFilter.get_real_exist_expand_path_file(module_map_file)
        end
        dep_module_map_files = Set.new
        [target_c_compile_flags, target_swift_compile_flags].each do | flags |
            (0..(flags.size-1)).each do | flag_i |
                flag = flags[flag_i]
                if flag.start_with? "-fmodule-map-file="
                    file = flag.sub("-fmodule-map-file=", "").strip
                    file = FileFilter.get_real_exist_expand_path_file(file)
                    if file
                        dep_module_map_files.add file
                    end
                    flags[flag_i] = ""
                    flags[flag_i-1] = "" if flag_i>0 and flags[flag_i-1] == "-Xcc"
                end
            end
            flags.delete_if{|x|x.size==0}
        end

        if not defines_module and module_map_file
            defines_module = true
        end
        if not defines_module and target.product_type == "com.apple.product-type.framework"
            defines_module = true
        end
        if not defines_module
            flags_sources_hash.each do | flags, source_files |
                extname = flags[0]
                if FileFilter.get_source_file_extnames_swift.include? extname
                    defines_module = true
                    break
                end
            end
        end
        
        if defines_module
            if not product_module_name
                product_module_name = c99ext_identifier(product_name)
            end
        end

        return enable_modules, product_module_name, module_map_file, dep_module_map_files
    end

    def get_target_targeted_device_family(target, variable_hash)
        settings = get_target_build_settings(target, variable_hash, "TARGETED_DEVICE_FAMILY", false)
        if settings.size == 0
            return ["iphone"]
        end
        splits = settings[-1].split(",")
        families = []
        splits.each do | split |
            if split == "1"
                families.push "iphone"
            elsif split == "2"
                families.push "ipad"
            elsif split == "3"
                families.push "tv"
            elsif split == "4"
                families.push "watch"
            elsif split == "5"
                families.push "Apple HomePod"  # TODO
            elsif split == "6"
                families.push "mac"
            else
                binding.pry
            end
        end
        return families            
    end

    def get_target_app_icon(target, variable_hash, resources_files)
        name = "AppIcon"
        settings = get_target_build_settings(target, variable_hash, "ASSETCATALOG_COMPILER_APPICON_NAME", false)
        if settings.size > 0
            name = settings[-1]
        end
        resources_files.each do | file |
            if File.extname(file).downcase == ".xcassets"
                appiconsets = Dir.glob("#{file}/**/#{name}.appiconset")
                if appiconsets.size == 1
                    return appiconsets[0]
                end
            end
        end
        return nil
    end

    def parse_xcodeproj(workspace_path, input_project_path)
        target_info_hash_for_xcode = {}
    
        projects = get_projects(workspace_path, input_project_path)
        projects.each do | project |
            project_path = project.path.to_s + "/project.pbxproj"
            project_variable_hash = get_build_settings_variables(project.build_configurations, {}, project, nil)
            project_header_map = get_project_header_map(project)
            project.native_targets.each do | target |
                if target_info_hash_for_xcode[target.name]
                    raise "unexpected conflicting #{target.name}"
                end
                
                variable_hash = get_build_settings_variables(target.build_configurations, project_variable_hash, project, target)
                header_path_hash_for_target_header_map = {}

                flags_sources_hash, clang_enable_objc_arc, has_swift = get_target_source_files(target, variable_hash)
    
                target_c_compile_flags, target_cxx_compile_flags, target_c_warning_flags, target_swift_compile_flags = get_target_compile_flags(target, variable_hash)
                target_link_flags = get_target_link_flags(target, variable_hash)
                target_header_dirs = get_target_header_dirs(target, variable_hash, target_c_compile_flags, target_cxx_compile_flags)
                target_framework_dirs = get_target_framework_dirs(target, variable_hash, target_link_flags, target_c_compile_flags, target_cxx_compile_flags)
                target_library_dirs = get_target_library_dirs(target, variable_hash, target_link_flags)
                pch = get_target_pch(target, variable_hash)
                target_defines, c_target_defines, cxx_target_defines, swift_target_defines = get_target_defines(target, variable_hash, target_c_compile_flags, target_cxx_compile_flags, target_swift_compile_flags)
                product_name, product_file_name, info_plist, bundle_id, bundle_version, mach_o_type = parse_target_product_info(target, variable_hash)
                target_links_hash = get_target_links_hash(target, variable_hash, target_library_dirs, target_framework_dirs, target_link_flags, product_file_name)
                resources_files, dependency_resource_product_file_names = get_target_resources(target)
                target_app_icon = get_target_app_icon(target, variable_hash, resources_files)
                provisioning_profile_specifier = get_target_provisioning_profile(target, variable_hash)
                iphoneos_deployment_target = get_target_iphoneos_deployment_target(target, variable_hash)
                targeted_device_family = get_target_targeted_device_family(target, variable_hash)

                swift_objc_bridging_header = get_targe_swift_setting(target, variable_hash)
                enable_modules, product_module_name, module_map_file, dep_module_map_files = get_targe_modules_setting(target, variable_hash, product_name, flags_sources_hash, target_c_compile_flags, target_swift_compile_flags)

                use_header_map = get_target_use_header_map(target, variable_hash)
                target_headers, namespace, target_public_header_map, target_private_header_map = get_target_header_map(target, use_header_map, product_name)

                info_hash = {}
                info_hash[:product_name] = product_name
                info_hash[:product_file_name] = product_file_name
                info_hash[:project_path] = project_path
                info_hash[:info_plist] = info_plist
                info_hash[:bundle_id] = bundle_id
                info_hash[:bundle_version] = bundle_version
                info_hash[:mach_o_type] = mach_o_type
                info_hash[:pch] = pch
                info_hash[:clang_enable_objc_arc] = clang_enable_objc_arc
                info_hash[:has_swift] = has_swift
                info_hash[:flags_sources_hash] = flags_sources_hash
                info_hash[:enable_modules] = enable_modules
                info_hash[:product_module_name] = product_module_name
                info_hash[:module_map_file] = module_map_file
                info_hash[:dep_module_map_files] = dep_module_map_files
                info_hash[:swift_objc_bridging_header] = swift_objc_bridging_header
                info_hash[:target_headers] = target_headers
                info_hash[:use_header_map] = use_header_map
                info_hash[:namespace] = namespace
                info_hash[:target_public_header_map] = target_public_header_map
                info_hash[:target_private_header_map] = target_private_header_map
                if use_header_map
                    info_hash[:project_header_map] = project_header_map
                else
                    info_hash[:project_header_map] = {}
                end
                info_hash[:target_header_dirs] = target_header_dirs
                info_hash[:target_framework_dirs] = target_framework_dirs
                info_hash[:target_defines] = target_defines
                info_hash[:c_target_defines] = c_target_defines
                info_hash[:cxx_target_defines] = cxx_target_defines
                info_hash[:swift_target_defines] = swift_target_defines
                info_hash[:target_links_hash] = target_links_hash
                info_hash[:resources_files] = resources_files
                info_hash[:dependency_resource_product_file_names] = dependency_resource_product_file_names
                info_hash[:target_app_icon] = target_app_icon
                info_hash[:provisioning_profile_specifier] = provisioning_profile_specifier
                info_hash[:iphoneos_deployment_target] = iphoneos_deployment_target
                info_hash[:targeted_device_family] = targeted_device_family

                info_hash[:target_c_compile_flags] = merge_flags(target_c_compile_flags + target_c_warning_flags).uniq
                info_hash[:target_cxx_compile_flags] = merge_flags(target_cxx_compile_flags).uniq
                info_hash[:target_swift_compile_flags] = merge_flags(target_swift_compile_flags).uniq
                info_hash[:target_link_flags] = merge_flags(target_link_flags).uniq

                target_info_hash_for_xcode[target.name] = info_hash
            end
        end

        total_build_product_file_name_set = target_info_hash_for_xcode.map{|e|e[1][:product_file_name].downcase}.to_set
        total_user_framework_path_set = target_info_hash_for_xcode.map{|e|e[1][:target_links_hash][:user_framework_paths]}.flatten.to_set.select{|path| not total_build_product_file_name_set.include? File.basename(path).downcase}.to_set
        total_user_library_paths = target_info_hash_for_xcode.map{|e|e[1][:target_links_hash][:user_library_paths]}.flatten.to_set.select{|path| not total_build_product_file_name_set.include? File.basename(path).downcase}.to_set
        total_alwayslink_product_file_names = target_info_hash_for_xcode.values.map{|e|e[:target_links_hash][:alwayslink_product_file_names].to_a}.flatten.map{|x|x.downcase}.to_set
        binding.pry if (total_alwayslink_product_file_names - total_build_product_file_name_set).size > 0

        # fixed invalid links
        target_info_hash_for_xcode.each do | target_name, info_hash |
            target_links_hash = info_hash[:target_links_hash]
    
            fixed_dependency_target_product_file_names = ((target_links_hash[:dependency_target_product_file_names] + target_links_hash[:user_framework_paths] + target_links_hash[:user_library_paths]).map{|e| File.basename(e)}.select{|e| total_build_product_file_name_set.include? e.downcase }).uniq
            fixed_user_framework_paths = (target_links_hash[:user_framework_paths].select{|path| not total_build_product_file_name_set.include? File.basename(path).downcase } + total_user_framework_path_set.select{|path| target_links_hash
            [:dependency_target_product_file_names].include? File.basename(path)}).uniq
            fixed_user_library_paths = (target_links_hash[:user_library_paths].select{|path| not total_build_product_file_name_set.include? File.basename(path).downcase } + total_user_library_paths.select{|path| target_links_hash[:dependency_target_product_file_names].include? File.basename(path)}).uniq
    
            target_links_hash[:dependency_target_product_file_names] = fixed_dependency_target_product_file_names
            target_links_hash[:user_framework_paths] = fixed_user_framework_paths
            target_links_hash[:user_library_paths] = fixed_user_library_paths
        end

        return target_info_hash_for_xcode
    end

end

