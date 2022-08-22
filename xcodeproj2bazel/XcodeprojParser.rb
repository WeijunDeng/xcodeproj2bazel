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
                next unless project_ref.path.end_with? ".xcodeproj"
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

    def get_file_paths_from_file_ref(file_ref, need_exist)
        file_paths = []
        get_file_refs_from_file_ref(file_ref).each do | ref |
            file_path = nil
            if ref.source_tree == "SOURCE_ROOT"
                # fix bugs in https://github.com/CocoaPods/Xcodeproj/blob/29cd0821d47f864abbd1ca80f23ff2aded0adfed/lib/xcodeproj/project/object/helpers/groupable_helper.rb#L156
                # support CMake generated projects with project_dir_path
                file_path = (ref.project.project_dir + ref.project.root_object.project_dir_path + ref.path).to_s
            else
                file_path = ref.real_path.to_s
            end
            exist_file_path = FileFilter.get_exist_expand_path(file_path)
            if exist_file_path
                file_path = exist_file_path
            else
                puts "not exist #{file_path}" unless file_path.start_with? "$"
                next if need_exist
            end
            file_paths.push file_path
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
            unless variable_hash["CONFIGURATION_BUILD_DIR"]
                variable_hash["CONFIGURATION_BUILD_DIR"] = "${CONFIGURATION_BUILD_DIR}"
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
        return nil unless path
        binding.pry if path.include? "'"
        binding.pry if path.include? "\""
        origin_path = path

        recursive = false
        if path.end_with? "/**"
            recursive = true
            path = File.dirname(path)
        end
        binding.pry if path.include? "**"

        unless path.start_with? "/"
            path = get_target_src_root(target, variable_hash) + "/" + path
        end
        path = FileFilter.get_exist_expand_path(path)
        if path
            if recursive
                dirs = FileFilter.get_recursive_dirs(path)
                return dirs
            else
                return path
            end
        end

        if File.exist? origin_path
            if origin_path.start_with? "/usr/"
                return origin_path
            end
            binding.pry
        end

        return nil
    end

    def get_project_header_map(project)
        project_header_map = {}
        project.files.each do | file_ref |
            file_paths = get_file_paths_from_file_ref(file_ref, true)
            file_paths.each do | file_path |
                next unless FileFilter.get_header_file_extnames.include? File.extname(file_path)
                file_path = FileFilter.get_real_exist_expand_path_file(file_path)
                binding.pry unless file_path

                key = File.basename(file_path).downcase
                project_header_map[key] = Set.new unless project_header_map[key]
                project_header_map[key].add file_path
            end
        end
        return project_header_map
    end

    def get_target_header_map(target, use_header_map, product_name, target_copy_map, product_file_name, configuration_build_dir)
        target_public_header_map = {}
        target_private_header_map = {}
        target_headers = []
        namespace = nil
        if use_header_map
            namespace = product_name
        end
        target.headers_build_phase.files.each do | file |
            file_paths = get_file_paths_from_file_ref(file.file_ref, true)
            file_paths.each do | file_path |
                file_path = FileFilter.get_real_exist_expand_path_file(file_path)
                binding.pry unless file_path
                extname = File.extname(file_path)
                unless FileFilter.get_header_file_extnames.include? extname
                    binding.pry
                end
                target_headers.push file_path
                is_public = false
                is_private = false
                if file.settings
                    file.settings.each do | k, v |
                        if k == "ATTRIBUTES"
                            v.each do | vv |
                                if vv == "Public"
                                    is_public = true
                                elsif vv == "Private"
                                    is_private = true
                                elsif vv == "Project"

                                else
                                    binding.pry
                                end
                            end
                        else
                            binding.pry
                        end
                    end
                end

                if target.product_type == "com.apple.product-type.framework"
                    binding.pry unless configuration_build_dir
                    if is_public
                        copy_dst_file = configuration_build_dir + "/" + product_file_name + "/Headers/" + File.basename(file_path)
                        binding.pry if target_copy_map[copy_dst_file] and target_copy_map[copy_dst_file] != file_path
                        target_copy_map[copy_dst_file] = file_path
                    end
                    if is_private
                        copy_dst_file = configuration_build_dir + "/" + product_file_name + "/PrivateHeaders/" + File.basename(file_path)
                        binding.pry if target_copy_map[copy_dst_file] and target_copy_map[copy_dst_file] != file_path
                        target_copy_map[copy_dst_file] = file_path
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
            file_paths = get_file_paths_from_file_ref(file.file_ref, true)
            file_paths.each do | file_path |
                extname = File.extname(file_path)
                if FileFilter.get_source_file_extnames_swift.include? extname
                    has_swift = true
                end
                next if FileFilter.get_source_file_extnames_ignore.include? extname
                binding.pry unless FileFilter.get_source_file_extnames_all.include? extname
                file_path = FileFilter.get_real_exist_expand_path_file(file_path)
                binding.pry unless file_path

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
        target.resources_build_phase.files.each do | file |
            file_paths = get_file_paths_from_file_ref(file.file_ref, false)
            file_paths.each do | file_path |
                resources_files.add file_path
            end
        end
        return resources_files
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

        search_paths.uniq.each do | origin_search_path |
            search_path = get_exist_build_settings_path(target, variable_hash, origin_search_path)
            if search_path and search_path.size > 0
                if search_path.class == Array
                    target_framework_dirs = (target_framework_dirs + search_path).uniq
                else
                    target_framework_dirs.push search_path unless target_framework_dirs.include? search_path
                end
            else
                target_framework_dirs.push [:unknown, origin_search_path]
            end
        end
        return target_framework_dirs.uniq
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

        get_target_build_settings(target, variable_hash, "GCC_C_LANGUAGE_STANDARD", false).each do | value |
            next if value == "compiler-default"
            value = "-std=" + value
            target_c_compile_flags.push value unless target_c_compile_flags.include? value
        end
        get_target_build_settings(target, variable_hash, "CLANG_CXX_LANGUAGE_STANDARD", false).each do | value |
            next if value == "compiler-default"
            value = "-std=" + value
            target_cxx_compile_flags.push value unless target_cxx_compile_flags.include? value
        end
        get_target_build_settings(target, variable_hash, "CLANG_CXX_LIBRARY", false).each do | value |
            next if value == "compiler-default"
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

    # https://github.com/CocoaPods/Xcodeproj/blob/29cd0821d47f864abbd1ca80f23ff2aded0adfed/lib/xcodeproj/constants.rb#L428
    # COPY_FILES_BUILD_PHASE_DESTINATIONS = {
    #     :absolute_path      =>  '0',
    #     :products_directory => '16',
    #     :wrapper            =>  '1',
    #     :resources          =>  '7', # default
    #     :executables        =>  '6',
    #     :java_resources     => '15',
    #     :frameworks         => '10',
    #     :shared_frameworks  => '11',
    #     :shared_support     => '12',
    #     :plug_ins           => '13',
    #   }.freeze
    def get_target_copy_map(target, variable_hash, product_file_name, dependency_target_product_file_names)
        target_copy_map = {}
        configuration_build_dir = get_target_build_settings(target, variable_hash, "CONFIGURATION_BUILD_DIR", false)[0]
        target.copy_files_build_phases.each do | build_phase |
            if build_phase.dst_subfolder_spec == "16" # products_directory
                binding.pry unless configuration_build_dir
                copy_dst_dir = nil
                match_result = nil
                unless match_result
                    match_result = build_phase.dst_path.match(/^\$\(PUBLIC_HEADERS_FOLDER_PATH\)\/([\w\/\.\-]+)$/)
                    if match_result
                        binding.pry unless target.product_type == "com.apple.product-type.framework"
                        copy_dst_dir = configuration_build_dir + "/" + product_file_name + "/Headers/" + match_result[1]
                    end
                end
                unless match_result
                    match_result = build_phase.dst_path.match(/^\$\(PRIVATE_HEADERS_FOLDER_PATH\)\/([\w\/\.\-]+)$/)
                    if match_result
                        binding.pry unless target.product_type == "com.apple.product-type.framework"
                        copy_dst_dir = configuration_build_dir + "/" + product_file_name + "/PrivateHeaders/" + match_result[1]
                    end
                end
                unless match_result
                    match_result = build_phase.dst_path.match(/^\$\(CONTENTS_FOLDER_PATH\)\/([\w\/\.\-]+)$/)
                    if match_result
                        binding.pry unless target.product_type == "com.apple.product-type.application"
                        copy_dst_dir = configuration_build_dir + "/" + product_file_name + "/" + match_result[1]
                    end
                end
                binding.pry unless copy_dst_dir
                build_phase.files.each do | file |
                    file_paths = get_file_paths_from_file_ref(file.file_ref, false)
                    file_paths.each do | file_path |
                        copy_dst_file = (copy_dst_dir + "/" + File.basename(file_path)).gsub("/./", "/")
                        binding.pry if target_copy_map[copy_dst_file] and target_copy_map[copy_dst_file] != file_path
                        target_copy_map[copy_dst_file] = file_path
                        
                    end
                end
            elsif build_phase.dst_subfolder_spec == "13" # plug_ins
                binding.pry unless target.product_type == "com.apple.product-type.application"
                binding.pry unless build_phase.dst_path == ""
                build_phase.files.each do | file |
                    file_paths = get_file_paths_from_file_ref(file.file_ref, false)
                    file_paths.each do | file_path |
                        copy_dst_file = configuration_build_dir + "/" + product_file_name + "/PlugIns/" + File.basename(file_path)
                        binding.pry if target_copy_map[copy_dst_file] and target_copy_map[copy_dst_file] != file_path
                        target_copy_map[copy_dst_file] = file_path
                        binding.pry unless File.extname(file_path) == ".appex"
                        dependency_target_product_file_names.add file_path
                    end
                end
            elsif build_phase.dst_subfolder_spec == "10" # frameworks
                binding.pry unless target.product_type == "com.apple.product-type.application"
                binding.pry unless build_phase.dst_path == ""
                build_phase.files.each do | file |
                    file_paths = get_file_paths_from_file_ref(file.file_ref, false)
                    file_paths.each do | file_path |
                        copy_dst_file = configuration_build_dir + "/" + product_file_name + "/Frameworks/" + File.basename(file_path)
                        binding.pry if target_copy_map[copy_dst_file] and target_copy_map[copy_dst_file] != file_path
                        target_copy_map[copy_dst_file] = file_path
                        binding.pry unless File.extname(file_path) == ".framework"
                        dependency_target_product_file_names.add file_path
                    end
                end
            else
                binding.pry
            end
        end
        return configuration_build_dir, target_copy_map
    end

    def get_target_links_hash(target, variable_hash, target_library_dirs, target_framework_dirs, target_link_flags, product_file_name)
        
        link_infos = Set.new

        target.frameworks_build_phases.files.each do | file |
            file_paths = get_file_paths_from_file_ref(file.file_ref, false)
            next unless file_paths.size > 0
            binding.pry unless file.file_ref.class == Xcodeproj::Project::Object::PBXFileReference
            binding.pry unless file_paths.size == 1
            weak_framework = false
            attribute_required = false
            if file.settings
                file.settings.each do | k, v |
                    if k == "ATTRIBUTES"
                        v.each do | vv |
                            if vv == "Weak"
                                weak_framework = true
                            elsif vv == "Required"
                                attribute_required = true
                            else
                                binding.pry
                            end
                        end
                    else
                        binding.pry
                    end
                end
            end
            file_paths.each do | file_path |
                if weak_framework
                    link_infos.add [file_path, :weak_framework]
                else
                    link_infos.add [file_path]
                end
            end
        end

        alwayslink_product_file_names = Set.new

        flags = target_link_flags
        if flags.size > 0
            (0..(flags.size-1)).each do | flag_i |
                flag = flags[flag_i]

                if flag_i + 1 < flags.size
                    if flag == "-framework" or flag == "-weak_framework"
                        framework_name = flags[flag_i+1]
                        if flag == "-weak_framework"
                            link_infos.add [framework_name + ".framework", :weak_framework]
                        else
                            link_infos.add [framework_name + ".framework"]
                        end
                        flags[flag_i] = ""
                        flags[flag_i+1] = ""
                        next
                    end
                end

                if flag.start_with? "-l"
                    library_name = flag.sub("-l", "")
                    link_infos.add ["lib" + library_name + ".a"]
                    flags[flag_i] = ""
                    next
                end

                force_load = (flag_i > 0 and flags[flag_i-1] == "-force_load")
                if force_load
                    flags[flag_i-1] = ""
                end
                if File.extname(File.dirname(flag)) == ".framework"
                    framework_path = File.dirname(flag)
                    link_infos.add [framework_path]
                    alwayslink_product_file_names.add File.basename(framework_path) if force_load
                    flags[flag_i] = ""
                    next
                end
                if File.extname(flag) == ".a"
                    library_path = flag
                    link_infos.add [library_path]
                    alwayslink_product_file_names.add File.basename(library_path) if force_load
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

        system_frameworks = Set.new
        system_weak_frameworks = Set.new
        system_libraries = Set.new
        dependency_target_product_file_names = Set.new

        link_infos.each do | link_info |
            link_path = link_info[0]
            extname = File.extname(link_path)
            if extname == ".framework"
                framework_file_name = File.basename(link_path)
                framework_name = framework_file_name.sub(".framework", "")
                system_framework = FileFilter.get_system_framework_by_name(framework_name)
                if system_framework
                    if link_info.include? :weak_framework
                        system_weak_frameworks.add system_framework
                    else
                        system_frameworks.add system_framework
                    end
                else
                    found = false
                    target_framework_dirs.each do | dir |
                        next unless dir.class == String
                        framework_path = dir + "/" + framework_file_name
                        framework_path = FileFilter.get_exist_expand_path_dir(framework_path)
                        if framework_path
                            dependency_target_product_file_names.add framework_path
                            found = true
                            break
                        end
                    end
                    unless found
                        target_framework_dirs.each do | dir |
                            next unless dir.class == String
                            Dir.glob("#{dir}/*.xcframework").sort.each do | xcframework_path | 
                                xcframework_info = FileFilter.get_match_xcframework_info(xcframework_path)
                                next unless xcframework_info
                                library_path = xcframework_info[:LibraryPath]
                                if library_path and File.basename(library_path) == framework_file_name
                                    library_path = FileFilter.get_exist_expand_path_dir(library_path)
                                    binding.pry unless library_path
                                    dependency_target_product_file_names.add library_path
                                    found = true
                                    break
                                end
                            end
                            break if found
                        end
                    end
                    unless found
                        dependency_target_product_file_names.add link_path
                    end
                end
            elsif extname == ".a"
                library_file_name = File.basename(link_path)
                match_result = library_file_name.match(/^lib(.+)\.a$/)
                binding.pry unless match_result
                library_name = match_result[1]
                system_library = FileFilter.get_system_library_by_name(library_name)
                if system_library
                    system_libraries.add system_library
                else
                    found = false
                    target_library_dirs.each do | dir |
                        library_path = dir + "/" + library_file_name
                        library_path = FileFilter.get_exist_expand_path_file(library_path)
                        if library_path
                            dependency_target_product_file_names.add library_path
                            found = true
                            break
                        end
                    end
                    unless found
                        target_framework_dirs.each do | dir |
                            next unless dir.class == String
                            Dir.glob("#{dir}/*.xcframework").sort.each do | xcframework_path | 
                                xcframework_info = FileFilter.get_match_xcframework_info(xcframework_path)
                                next unless xcframework_info
                                library_path = xcframework_info[:LibraryPath]
                                if library_path and File.basename(library_path) == library_file_name
                                    library_path = FileFilter.get_exist_expand_path_file(library_path)
                                    binding.pry unless library_path
                                    dependency_target_product_file_names.add library_path
                                    found = true
                                    break
                                end
                            end
                            break if found
                        end
                    end
                    unless found
                        dependency_target_product_file_names.add link_path
                    end
                end
            elsif extname == ".tbd"
                match_result = File.basename(link_path).match(/^lib(.+)\.tbd$/)
                binding.pry unless match_result
                library_name = match_result[1]
                system_library = FileFilter.get_system_library_by_name(library_name)
                binding.pry unless system_library
                system_libraries.add File.basename(link_path)
            else
                next
            end
        end

        target_links_hash = {}
        target_links_hash[:system_frameworks] = system_frameworks
        target_links_hash[:system_weak_frameworks] = system_weak_frameworks
        target_links_hash[:system_libraries] = system_libraries
        target_links_hash[:dependency_target_product_file_names] = dependency_target_product_file_names
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

        info_plist0 = get_target_build_settings(target, variable_hash, "INFOPLIST_FILE", false)[0]
        info_plist = get_exist_build_settings_path(target, variable_hash, info_plist0)
        binding.pry if info_plist0 and not info_plist
        if info_plist
            info_plist_bundle_version = Open3.capture3("/usr/libexec/PlistBuddy -c \"Print :CFBundleVersion\" \"#{info_plist}\"")[0].strip
            if info_plist_bundle_version.size > 0 and not info_plist_bundle_version.include? "$"
                bundle_version = info_plist_bundle_version
            end
            
            info_plist_bundle_id = Open3.capture3("/usr/libexec/PlistBuddy -c \"Print :CFBundleIdentifier\" \"#{info_plist}\"")[0].strip
            if info_plist_bundle_id.size > 0 and not info_plist_bundle_id.include? "$"
                bundle_id = info_plist_bundle_id
            end

            info_plist_icons = Open3.capture3("/usr/libexec/PlistBuddy -c \"Print :CFBundleIcons\" \"#{info_plist}\"")[0].strip
            if info_plist_icons.size > 0
                if info_plist_icons == "Dict {\n}"
                    cmd = "/usr/libexec/PlistBuddy -c \"Delete :CFBundleIcons\" \"#{info_plist}\""
                    puts cmd
                    system(cmd)
                end
            end
            info_plist_icons = Open3.capture3("/usr/libexec/PlistBuddy -c \"Print :CFBundleIcons~ipad\" \"#{info_plist}\"")[0].strip
            if info_plist_icons.size > 0
                if info_plist_icons == "Dict {\n}"
                    cmd = "/usr/libexec/PlistBuddy -c \"Delete :CFBundleIcons~ipad\" \"#{info_plist}\""
                    puts cmd
                    system(cmd)
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
        return settings[0]
    end

    def get_target_iphoneos_deployment_target(target, variable_hash)
        settings = get_target_build_settings(target, variable_hash, "IPHONEOS_DEPLOYMENT_TARGET", false)
        return settings[0]
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
            if File.extname(file) == ".xcassets"
                appiconsets = Dir.glob("#{file}/**/#{name}.appiconset")
                if appiconsets.size == 1
                    return appiconsets[0]
                end
            end
        end
        return nil
    end

    # https://github.com/CocoaPods/Xcodeproj/blob/29cd0821d47f864abbd1ca80f23ff2aded0adfed/lib/xcodeproj/constants.rb#L146
    # PRODUCT_TYPE_UTI = {
    #     :application                           => 'com.apple.product-type.application',
    #     :application_on_demand_install_capable => 'com.apple.product-type.application.on-demand-install-capable',
    #     :framework                             => 'com.apple.product-type.framework',
    #     :dynamic_library                       => 'com.apple.product-type.library.dynamic',
    #     :static_library                        => 'com.apple.product-type.library.static',
    #     :bundle                                => 'com.apple.product-type.bundle',
    #     :octest_bundle                         => 'com.apple.product-type.bundle',
    #     :unit_test_bundle                      => 'com.apple.product-type.bundle.unit-test',
    #     :ui_test_bundle                        => 'com.apple.product-type.bundle.ui-testing',
    #     :app_extension                         => 'com.apple.product-type.app-extension',
    #     :command_line_tool                     => 'com.apple.product-type.tool',
    #     :watch_app                             => 'com.apple.product-type.application.watchapp',
    #     :watch2_app                            => 'com.apple.product-type.application.watchapp2',
    #     :watch2_app_container                  => 'com.apple.product-type.application.watchapp2-container',
    #     :watch_extension                       => 'com.apple.product-type.watchkit-extension',
    #     :watch2_extension                      => 'com.apple.product-type.watchkit2-extension',
    #     :tv_extension                          => 'com.apple.product-type.tv-app-extension',
    #     :messages_application                  => 'com.apple.product-type.application.messages',
    #     :messages_extension                    => 'com.apple.product-type.app-extension.messages',
    #     :sticker_pack                          => 'com.apple.product-type.app-extension.messages-sticker-pack',
    #     :xpc_service                           => 'com.apple.product-type.xpc-service',
    #   }.freeze
    def supported_target(target, variable_hash)
        if target.product_type == "com.apple.product-type.application" or
            target.product_type == "com.apple.product-type.app-extension" or
            target.product_type == "com.apple.product-type.framework" or
            target.product_type == "com.apple.product-type.bundle" or
            target.product_type == "com.apple.product-type.library.static"

            sdkroot = get_target_build_settings(target, variable_hash, "SDKROOT", false)[0]
            if sdkroot and sdkroot.size > 0 and sdkroot != "iphoneos" and sdkroot != "iphonesimulator" and not sdkroot.include? "iPhoneOS.platform"
                puts "unsupported #{target.name} SDKROOT #{sdkroot}"
                return false
            end
            supported_platforms = get_target_build_settings(target, variable_hash, "SUPPORTED_PLATFORMS", true)
            if supported_platforms.size > 0 and not supported_platforms.include? "iphoneos" and not supported_platforms.include? "iphonesimulator"
                puts "unsupported #{target.name} SUPPORTED_PLATFORMS #{supported_platforms.to_s}"
                return false
            end

            return true
        end
        puts "unsupported #{target.name} product_type #{target.product_type}"
        return false
    end
    
    def parse_xcodeproj(workspace_path, input_project_path)
        target_info_hash_for_xcode = {}
    
        projects = get_projects(workspace_path, input_project_path)
        projects.each do | project |
            project_path = project.path.to_s + "/project.pbxproj"
            project_variable_hash = get_build_settings_variables(project.build_configurations, {}, project, nil)
            project_header_map = get_project_header_map(project)
            project.native_targets.each do | target |
                
                variable_hash = get_build_settings_variables(target.build_configurations, project_variable_hash, project, target)

                next unless supported_target(target, variable_hash)

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
                resources_files = get_target_resources(target)
                target_app_icon = get_target_app_icon(target, variable_hash, resources_files)
                provisioning_profile_specifier = get_target_provisioning_profile(target, variable_hash)
                iphoneos_deployment_target = get_target_iphoneos_deployment_target(target, variable_hash)
                targeted_device_family = get_target_targeted_device_family(target, variable_hash)

                swift_objc_bridging_header = get_targe_swift_setting(target, variable_hash)
                enable_modules, product_module_name, module_map_file, dep_module_map_files = get_targe_modules_setting(target, variable_hash, product_name, flags_sources_hash, target_c_compile_flags, target_swift_compile_flags)

                configuration_build_dir, target_copy_map = get_target_copy_map(target, variable_hash, product_file_name, target_links_hash[:dependency_target_product_file_names])
                use_header_map = get_target_use_header_map(target, variable_hash)
                target_headers, namespace, target_public_header_map, target_private_header_map = get_target_header_map(target, use_header_map, product_name, target_copy_map, product_file_name, configuration_build_dir)

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
                info_hash[:target_copy_map] = target_copy_map
                info_hash[:resources_files] = resources_files
                info_hash[:target_app_icon] = target_app_icon
                info_hash[:provisioning_profile_specifier] = provisioning_profile_specifier
                info_hash[:iphoneos_deployment_target] = iphoneos_deployment_target
                info_hash[:targeted_device_family] = targeted_device_family

                info_hash[:target_c_compile_flags] = merge_flags(target_c_compile_flags + target_c_warning_flags).uniq
                info_hash[:target_cxx_compile_flags] = merge_flags(target_cxx_compile_flags).uniq
                info_hash[:target_swift_compile_flags] = merge_flags(target_swift_compile_flags).uniq
                info_hash[:target_link_flags] = merge_flags(target_link_flags).uniq

                if target_info_hash_for_xcode[product_file_name]
                    raise "unexpected conflicting #{product_file_name}"
                end
                target_info_hash_for_xcode[product_file_name] = info_hash
            end
        end

        return target_info_hash_for_xcode
    end

end

