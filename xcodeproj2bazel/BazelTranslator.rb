class BazelTranslator
    def translate(target_info_hash_for_xcode, analyze_result)

        total_header_namspace_hash = analyze_result[:total_header_namspace_hash]
        total_header_module_hash = analyze_result[:total_header_module_hash]
        total_user_modules = analyze_result[:total_user_modules]

        target_info_hash_for_bazel = {}
    
        product_file_name_hash = {}
    
        alwayslink_product_file_names = Set.new
        module_map_file_hash = {}
        target_info_hash_for_xcode.each do | target_name, info_hash |
            product_file_name = info_hash[:product_file_name]
            product_file_name_hash[product_file_name] = target_name
    
            alwayslink_product_file_names.merge info_hash[:target_links_hash][:alwayslink_product_file_names]

            product_module_name = info_hash[:product_module_name]
            if product_module_name
                modulemap_file = info_hash[:modulemap_file]
                module_map_file_hash[product_module_name] = modulemap_file
            end
        end
    
        total_header_namspace_hash.each do | header, namespace |
            next if File.extname(header) == ".pch"
            header_target_name = get_bazel_target_name_for_header_map(total_header_namspace_hash, header)
            header_target_info = KeyValueStore.get_key_value_store_in_container(target_info_hash_for_bazel, header_target_name)
            header_target_info["rule"] = "header_map"
            header_target_info["namespace"] = namespace if namespace and namespace.size > 0
            header_target_info["hdrs"] = Set.new unless header_target_info["hdrs"]
            header_target_info["hdrs"].add header
            # namespace_only
        end

        total_header_module_hash.each do | header, namespace |
            next if File.extname(header) == ".pch"
            binding.pry unless namespace and namespace.size > 0
            header_target_name = get_bazel_target_name_for_module_map(namespace, false)
            header_target_info = KeyValueStore.get_key_value_store_in_container(target_info_hash_for_bazel, header_target_name)
            header_target_info["rule"] = "module_map"
            unless header_target_info["module_name"]
                header_target_info["module_name"] = namespace
                if module_map_file_hash[namespace]
                    binding.pry unless File.exist? module_map_file_hash[namespace]
                    # TODO, use exist module map file
                    # header_target_info["module_map_file"] = module_map_file_hash[namespace]
                    module_map_file_content = File.read(module_map_file_hash[namespace])
                    match_result = module_map_file_content.match(/umbrella header \"(.*)\"/)
                    if match_result
                        umbrella_header = match_result[1]
                        if umbrella_header.include? "/"
                            binding.pry
                        else
                            umbrella_header = File.dirname(module_map_file_hash[namespace]) + "/" + umbrella_header
                            umbrella_header = FileFilter.get_exist_expand_path(umbrella_header)
                            if umbrella_header
                                header_target_info["umbrella_header"] = umbrella_header
                            else
                                header_target_info["umbrella_header_name"] = match_result[1]
                            end
                        end
                    else
                        binding.pry
                    end
                end
            end

            if header_target_info["umbrella_header_name"]
                if File.basename(header) == header_target_info["umbrella_header_name"]
                    header_target_info["umbrella_header"] = header
                    header_target_info.delete "umbrella_header_name"
                end
            end

            if not header_target_info["umbrella_header"] and File.basename(header) == namespace + ".h"
                header_target_info["umbrella_header"] = header
            else
                header_target_info["hdrs"] = Set.new unless header_target_info["hdrs"]
                header_target_info["hdrs"].add header
            end
        end

        target_info_hash_for_xcode.each do | target_name, info_hash |
            product_module_name = info_hash[:product_module_name]
            next unless product_module_name
            raise unless product_module_name.size > 0
            product_file_name = info_hash[:product_file_name]
            extname_sources_hash = info_hash[:extname_sources_hash]
            extname_sources_hash.each do | extname, files_hash |
                if FileFilter.get_swift_source_file_extnames.include? extname
                    bazel_target_name = get_bazel_target_name_for_product_file_name_and_extname_and_swift_module_name(product_file_name, extname, product_module_name)

                    header_target_name0 = get_bazel_target_name_for_module_map(product_module_name, false)
                    next unless target_info_hash_for_bazel.has_key? header_target_name0
                    header_target_info0 = KeyValueStore.get_key_value_store_in_container(target_info_hash_for_bazel, header_target_name0)

                    header_target_name = get_bazel_target_name_for_module_map(product_module_name, true)
                    header_target_info = KeyValueStore.get_key_value_store_in_container(target_info_hash_for_bazel, header_target_name)
                    header_target_info["rule"] = header_target_info0["rule"]
                    header_target_info["module_name"] = header_target_info0["module_name"]
                    header_target_info["umbrella_header"] = header_target_info0["umbrella_header"] if header_target_info0["umbrella_header"]
                    header_target_info["hdrs"] = header_target_info0["hdrs"] if header_target_info0["hdrs"]
                    header_target_info["deps"] = [bazel_target_name]

                    header_target_name = get_bazel_target_name_for_swift_header_map(product_module_name)
                    header_target_info = KeyValueStore.get_key_value_store_in_container(target_info_hash_for_bazel, header_target_name)
                    header_target_info["rule"] = "header_map"
                    header_target_info["namespace"] = product_module_name
                    header_target_info["direct_hdr_providers"] = [":" + bazel_target_name]

                end
            end
        end

        target_info_hash_for_xcode.each do | target_name, info_hash |
    
            pch = info_hash[:pch]
            extname_sources_hash = info_hash[:extname_sources_hash]
            header_path_hash_for_target_headermap = info_hash[:header_path_hash_for_target_headermap]
            header_path_hash_for_project_headermap = info_hash[:header_path_hash_for_project_headermap]
    
            product_name = info_hash[:product_name]
            product_module_name = info_hash[:product_module_name]
            modulemap_file = info_hash[:modulemap_file]
            product_file_name = info_hash[:product_file_name]
            info_plist = info_hash[:info_plist]
            bundle_id = info_hash[:bundle_id]
            bundle_version = info_hash[:bundle_version]
            mach_o_type = info_hash[:mach_o_type]
            target_links_hash = info_hash[:target_links_hash]
            resources_files = info_hash[:resources_files]
            dependency_resource_product_file_names = info_hash[:dependency_resource_product_file_names]

            target_c_compile_flags = info_hash[:target_c_compile_flags]
            target_cxx_compile_flags = info_hash[:target_cxx_compile_flags]
            target_swift_compile_flags = info_hash[:target_swift_compile_flags]
            target_link_flags = info_hash[:target_link_flags]
            target_defines = info_hash[:target_defines]
            swift_objc_bridging_header = info_hash[:swift_objc_bridging_header]
            target_header_dirs = info_hash[:target_header_dirs]

            alwayslink = alwayslink_product_file_names.include? product_file_name
            if File.extname(product_file_name) == ".framework" and mach_o_type == "mh_dylib"
                alwayslink = true
            end
    
            dep_bazel_source_targets = Set.new

            extname_sources_hash.each do | extname, files_hash |

                if FileFilter.get_swift_source_file_extnames.include? extname
                    bazel_target_name = get_bazel_target_name_for_product_file_name_and_extname_and_swift_module_name(product_file_name, extname, product_module_name)
                    dep_bazel_source_targets.add bazel_target_name
                    target_info = KeyValueStore.get_key_value_store_in_container(target_info_hash_for_bazel, bazel_target_name)
                    target_info["rule"] = "swift_library"
                    target_info["alwayslink"] = "True"
                    if product_module_name
                        target_info["module_name"] = product_module_name
                    end

                    swift_dep_objc_headers = Set.new
                    if swift_objc_bridging_header
                        target_info["objc_bridging_header"] = swift_objc_bridging_header
                        swift_dep_objc_headers.add swift_objc_bridging_header
                    elsif product_module_name
                        module_map_target_name = get_bazel_target_name_for_module_map(product_module_name, false)
                        if target_info_hash_for_bazel.has_key? module_map_target_name
                            target_info["objc_module_maps"] = Set.new unless target_info["objc_module_maps"]
                            target_info["objc_module_maps"].add module_map_target_name
                            
                            target_info["copts"] = [] unless target_info["copts"]
                            target_info["copts"].push "-import-underlying-module" unless target_info["copts"].include? "-import-underlying-module"

                            module_map_target_info = target_info_hash_for_bazel[module_map_target_name]
                            if module_map_target_info["umbrella_header"]
                                swift_dep_objc_headers.add module_map_target_info["umbrella_header"]
                            end
                            swift_dep_objc_headers.merge module_map_target_info["hdrs"] if module_map_target_info["hdrs"]
                        end
                    end
                    extname_analyze_result = KeyValueStore.get_key_value_store_in_container(analyze_result, extname)
                    file_swift_user_modules_hash = KeyValueStore.get_key_value_store_in_container(extname_analyze_result, :file_swift_user_modules_hash)

                    target_info["srcs"] = Set.new unless target_info["srcs"]
                    user_modules = Set.new
                    files_hash.each do | file, file_hash |        
                        target_info["srcs"].add file
                        user_modules.merge file_swift_user_modules_hash[file]
                    end
                    user_modules.each do | user_module |
                        next if user_module == product_module_name
                        target_info["deps"] = Set.new unless target_info["deps"]
                        target_info["deps"].add get_bazel_target_name_for_product_file_name_and_extname_and_swift_module_name(nil, nil, user_module)

                        header_target_name = get_bazel_target_name_for_module_map(user_module, true)
                        if not target_info_hash_for_bazel.has_key? header_target_name
                            header_target_name = get_bazel_target_name_for_module_map(user_module, false)
                        end
                        if not target_info_hash_for_bazel.has_key? header_target_name
                            next
                        end
                        
                        key = "objc_module_maps"
                        target_info[key] = Set.new unless target_info[key]
                        target_info[key].add header_target_name
        
                        module_map_target_info = target_info_hash_for_bazel[header_target_name]
                        if module_map_target_info["umbrella_header"]
                            swift_dep_objc_headers.add module_map_target_info["umbrella_header"]
                        end
                        swift_dep_objc_headers.merge module_map_target_info["hdrs"] if module_map_target_info["hdrs"]
                    end
                    swift_dep_objc_headers.each do | header |
                        add_deps_for_target_info(target_info, true, header, total_header_module_hash, total_header_namspace_hash, target_info_hash_for_bazel, target_info_hash_for_xcode, analyze_result)

                        FileFilter.get_pure_objc_source_file_extnames.each do | objc_extname |
                            extname_analyze_result = KeyValueStore.get_key_value_store_in_container(analyze_result, objc_extname)
                            file_headers_hash = KeyValueStore.get_key_value_store_in_container(extname_analyze_result, :file_headers_hash)
                            file_includes_hash = KeyValueStore.get_key_value_store_in_container(extname_analyze_result, :file_includes_hash)

                            next unless file_headers_hash[header]
                            file_headers_hash[header].each do | header2 |
                                add_deps_for_target_info(target_info, true, header2, total_header_module_hash, total_header_namspace_hash, target_info_hash_for_bazel, target_info_hash_for_xcode, analyze_result)
                            end
                            target_info["objc_includes"] = Set.new unless target_info["objc_includes"]
                            target_info["objc_includes"].merge file_includes_hash[header] if file_includes_hash[header]
                        end
                    end

                    if target_defines and target_defines.size > 0
                        defines = []
                        target_defines.each do | key, value |
                            defines.push "#{key}=#{value}"
                        end
                        target_info["defines"] = Set.new unless target_info["defines"]
                        target_info["defines"].merge defines
                    end
                    if target_swift_compile_flags and target_swift_compile_flags.size > 0
                        target_info["copts"] = [] unless target_info["copts"]
                        target_info["copts"] = target_info["copts"] + target_swift_compile_flags
                    end
                end

                unless FileFilter.get_source_file_extnames_without_swift.include? extname
                    next
                end

                extname_analyze_result = KeyValueStore.get_key_value_store_in_container(analyze_result, extname)
                file_headers_hash = KeyValueStore.get_key_value_store_in_container(extname_analyze_result, :file_headers_hash)
                file_includes_hash = KeyValueStore.get_key_value_store_in_container(extname_analyze_result, :file_includes_hash)

                bazel_target_name = get_bazel_target_name_for_product_file_name_and_extname(product_file_name, extname)
                dep_bazel_source_targets.add bazel_target_name
                target_info = KeyValueStore.get_key_value_store_in_container(target_info_hash_for_bazel, bazel_target_name)
                type = "cc_library"
                if FileFilter.get_objc_source_file_extnames.include? extname
                    type = "objc_library"
                end
                target_info["rule"] = type
                target_info["alwayslink"] = "True" if alwayslink
                target_info["pch"] = pch if pch

                if FileFilter.get_c_source_file_extnames.include? extname and target_c_compile_flags and target_c_compile_flags.size > 0
                    target_info["copts"] = [] unless target_info["copts"]
                    target_info["copts"] = target_info["copts"] + target_c_compile_flags
                end
                if FileFilter.get_cpp_source_file_extnames.include? extname and target_cxx_compile_flags and target_cxx_compile_flags.size > 0
                    target_info["copts"] = [] unless target_info["copts"]
                    target_info["copts"] = target_info["copts"] + target_cxx_compile_flags
                end
                if target_defines and target_defines.size > 0
                    defines = []
                    target_defines.each do | key, value |
                        defines.push "#{key}=#{value}"
                    end
                    target_info["defines"] = Set.new unless target_info["defines"]
                    target_info["defines"].merge defines
                end
                if target_link_flags and target_link_flags.size > 0
                    target_info["linkopts"] = [] unless target_info["linkopts"]
                    target_info["linkopts"] = target_info["linkopts"] + target_link_flags
                end

                headers = files_hash.keys.map{|e|file_headers_hash[e].to_a}.flatten.to_set

                target_info["deps"] = Set.new unless target_info["deps"]
                headers.each do | header |
                    add_deps_for_target_info(target_info, false, header, total_header_module_hash, total_header_namspace_hash, target_info_hash_for_bazel, target_info_hash_for_xcode, analyze_result)
                end
                includes = files_hash.keys.map{|e|file_includes_hash[e].to_a}.flatten.to_set
                if includes.size > 0
                    target_info["includes"] = Set.new unless target_info["includes"]
                    target_info["includes"].merge includes
                end
                if target_info["includes"] and target_info["includes"].size > 0 and target_header_dirs and target_header_dirs.size > 0
                    # keep original search order
                    target_info["includes"] = (target_header_dirs + target_info["includes"].sort).select{|x| target_info["includes"].include? x}.uniq
                end
                files_hash.each do | file, file_hash |
                    if file_hash["non_arc"] == true and target_info["rule"] == "objc_library"
                        target_info["non_arc_srcs"] = Set.new unless target_info["non_arc_srcs"]
                        target_info["non_arc_srcs"].add file
                    else
                        target_info["srcs"] = Set.new unless target_info["srcs"]
                        target_info["srcs"].add file
                    end
                end
            end
    
            bazel_target_name = get_bazel_target_name_for_product_file_name(product_file_name)
            target_info = KeyValueStore.get_key_value_store_in_container(target_info_hash_for_bazel, bazel_target_name)

            if File.extname(product_file_name) == ".a"
                target_info["rule"] = "static_library"
            elsif File.extname(product_file_name) == ".framework"
                if mach_o_type == "mh_dylib"
                    target_info["rule"] = "ios_framework"
                else
                    target_info["rule"] = "static_library"
                end
            elsif File.extname(product_file_name) == ".app"
                target_info["rule"] = "ios_application"
            elsif File.extname(product_file_name) == ".appex"
                target_info["rule"] = "ios_extension"
            elsif File.extname(product_file_name) == ".bundle"
                target_info["rule"] = "apple_resource_bundle"
            elsif File.extname(product_file_name) == ".xctest"
                # target_info["rule"] = "ios_unit_test"
                next
            else
                raise "unsupported product_file_name #{product_file_name}"
            end

            if target_info["rule"] == "ios_application" or 
                target_info["rule"] == "ios_extension" or
                target_info["rule"] == "ios_framework"
                target_info["bundle_name"] = product_name
                target_info["bundle_id"] = bundle_id if bundle_id
                if bundle_version
                    bundle_version_target_name = generate_bazel_target_name_for_bundle_version(bazel_target_name, bundle_version, target_info_hash_for_bazel)
                    target_info["version"] = ":" + bundle_version_target_name
                end
                if info_plist
                    target_info["infoplists"] = [info_plist]
                end
            end
    
            target_info["deps"] = Set.new unless target_info["deps"]
    
            target_info["deps"].merge dep_bazel_source_targets

            target_links_hash[:user_framework_paths].each do | framework_path |
                dep_bazel_target_name_name = generate_bazel_target_name_for_framework_import(framework_path, target_info_hash_for_bazel)
                target_info["deps"].add dep_bazel_target_name_name
            end
            target_links_hash[:user_library_paths].each do | library_path |
                dep_bazel_target_name_name = generate_bazel_target_name_for_library_import(library_path, target_info_hash_for_bazel)
                target_info["deps"].add dep_bazel_target_name_name
            end
            target_links_hash[:dependency_target_product_file_names].each do | dependency_target_product_file_name |
                dep_bazel_target_name_name = product_file_name_hash[dependency_target_product_file_name]
                unless dep_bazel_target_name_name
                    raise "unexpected #{dependency_target_product_file_name} null"
                end
                dep_bazel_target_name_info = target_info_hash_for_xcode[dep_bazel_target_name_name]
                dep_bazel_target_name_name = get_bazel_target_name_for_product_file_name(dep_bazel_target_name_info[:product_file_name])
                if File.extname(dependency_target_product_file_name) == ".framework" and dep_bazel_target_name_info[:mach_o_type] == "mh_dylib"
                    if target_info["rule"] == "ios_application" or target_info["rule"] == "ios_framework"
                        target_info["frameworks"] = Set.new unless target_info["frameworks"]
                        target_info["frameworks"].add dep_bazel_target_name_name
                        next
                    elsif target_info["rule"] == "static_library"
                        next
                    else
                        # TODO
                        # raise "unexpected #{target_info["rule"]}"
                    end
                end

                if File.extname(dependency_target_product_file_name) == ".appex"
                    if target_info["rule"] == "ios_application"
                        target_info["extensions"] = Set.new unless target_info["extensions"]
                        target_info["extensions"].add dep_bazel_target_name_name
                        next
                    else
                        raise "unexpected #{target_info["rule"]}"
                    end
                end
    
                target_info["deps"].add dep_bazel_target_name_name
            end
    
            total_system_links_size = target_links_hash[:system_frameworks].size + target_links_hash[:system_weak_frameworks].size + target_links_hash[:system_libraries].size
            if total_system_links_size > 0
                system_links_target_name = generate_bazel_target_name_for_system_links(bazel_target_name, target_links_hash[:system_frameworks], target_links_hash[:system_weak_frameworks], target_links_hash[:system_libraries], target_info_hash_for_bazel)
                target_info["deps"].add system_links_target_name
            end

            if target_info["rule"] == "apple_resource_bundle"
                target_info["bundle_name"] = product_name
                target_info["bundle_id"] = bundle_id if bundle_id
                if info_plist
                    target_info["infoplists"] = [info_plist]
                end
            end

            if target_info["rule"] == "apple_resource_bundle" or
                target_info["rule"] == "ios_application" or 
                target_info["rule"] == "ios_framework" or 
                target_info["rule"] == "ios_extension"
                if resources_files.size > 0
                    if target_info["rule"] == "ios_extension"
                        strings_resources = resources_files.select{|e|File.extname(e).downcase == ".strings" and File.extname(File.dirname(e)).downcase == ".lproj" }
                        if strings_resources.size > 0
                            target_info["strings"] = Set.new unless target_info["strings"]
                            target_info["strings"].merge strings_resources
                        end
                        resources_files = resources_files - strings_resources
                    end
                    metal_files = resources_files.select{|e|File.extname(e).downcase == ".metal"}
                    if metal_files.size > 0
                        resources_files = resources_files - metal_files
                        metal_files.each do | metal_file |
                            metal_target_name = get_legal_bazel_target_name(metal_file).downcase
                            metal_target_info = KeyValueStore.get_key_value_store_in_container(target_info_hash_for_bazel, metal_target_name)
                            metal_target_info["rule"] = "metal_library"
                            metal_target_info["hdrs"] = Dir.glob(File.dirname(metal_file) + "/*.h").sort
                            metal_target_info["srcs"] = [metal_file]

                            resources_files.add ":" + metal_target_name
                        end
                    end

                    if resources_files.size > 0
                        target_info["resources"] = Set.new unless target_info["resources"]
                        target_info["resources"].merge resources_files
                    end
                end
                dependency_resource_product_file_names.each do | dependency_resource_product_file_name |
                    target_info["resources"] = Set.new unless target_info["resources"]
                    target_info["resources"].add ":" + get_bazel_target_name_for_product_file_name(dependency_resource_product_file_name)
                end
            end

            provisioning_profile_specifier = info_hash[:provisioning_profile_specifier]
            iphoneos_deployment_target = info_hash[:iphoneos_deployment_target]
            targeted_device_family = info_hash[:targeted_device_family]

            if target_info["rule"] == "ios_application" or 
                target_info["rule"] == "ios_extension" or
                target_info["rule"] == "ios_framework"
                
                unless targeted_device_family.size > 0
                    binding.pry
                    raise "unexpected targeted_device_family null"
                end
                unless iphoneos_deployment_target.size > 0
                    raise "unexpected iphoneos_deployment_target null"
                end

                target_info["families"] = targeted_device_family
                target_info["minimum_os_version"] = iphoneos_deployment_target
            end
            if target_info["rule"] == "ios_application" or 
                target_info["rule"] == "ios_extension"
                
                if provisioning_profile_specifier and provisioning_profile_specifier.size > 0
                    target_info["provisioning_profile"] = provisioning_profile_specifier
                end                

                target_app_icon = info_hash[:target_app_icon]
                if target_app_icon and target_app_icon.size > 0
                    target_info["app_icons"] = [target_app_icon + "/**"]
                end
            end
        end

        # fix up
        target_info_hash_for_bazel.each do | target_name, hash |
            if hash["deps"]
                hash["deps"].to_a.each do | dep |
                    unless target_info_hash_for_bazel.has_key? dep
                        hash["deps"].delete dep
                        if dep.end_with? "_swift"
                            import_target_name = "import_" + get_bazel_target_name_for_product_file_name(dep.sub("_swift", ".framework"))
                            hash["deps"].add import_target_name if target_info_hash_for_bazel.has_key? import_target_name
                        end
                    end
                end
            end
        end

        target_info_hash_for_bazel.sort.each do | target_name, hash |
            hash.keys.each do | key |
                if hash[key].class == Set
                    hash[key] = hash[key].sort.uniq {|x|x.downcase}
                elsif hash[key].class == Array
                    hash[key] = hash[key].uniq {|x|x.downcase}
                end
            end
        end
        return target_info_hash_for_bazel
    end
    
    def generate_bazel_target_name_for_bundle_version(target_name, version, target_info_hash_for_bazel)
        bundle_version_target_name = target_name + "_version"
        target_info = KeyValueStore.get_key_value_store_in_container(target_info_hash_for_bazel, bundle_version_target_name)
        unless target_info.size > 0
            target_info["rule"] = "apple_bundle_version"
            target_info["build_version"] = version
        end
        return bundle_version_target_name
    end
    
    def generate_bazel_target_name_for_system_links(target_name, system_framework, system_weak_frameworks, system_libraries, target_info_hash_for_bazel)
        system_links_target_name = target_name + "_system_library"
        target_info = KeyValueStore.get_key_value_store_in_container(target_info_hash_for_bazel, system_links_target_name)
        unless target_info.size > 0
            target_info["rule"] = "system_library"
            target_info["sdk_dylibs"] = system_libraries.map{|e| e.split(File.extname(e))[0]}.sort if system_libraries.size > 0
            target_info["sdk_frameworks"] = system_framework.map{|e| e.split(File.extname(e))[0]}.sort if system_framework.size > 0
            target_info["weak_sdk_frameworks"] = system_weak_frameworks.map{|e| e.split(File.extname(e))[0]}.sort if system_weak_frameworks.size > 0
        end
        return system_links_target_name
    end
    
    def generate_bazel_target_name_for_framework_import(framework_path, target_info_hash_for_bazel)
        framework_path = FileFilter.get_exist_expand_path(framework_path)
        target_name = get_bazel_target_name_for_framework_import framework_path
        unless target_info_hash_for_bazel.has_key? target_name
            framework_name = File.basename(framework_path).split(".")[0]
            framework_library_path = framework_path + "/" + framework_name
            unless File.exist? framework_library_path
                raise "unexpected #{framework_library_path} not exist"
            end
    
            framework_target_info = KeyValueStore.get_key_value_store_in_container(target_info_hash_for_bazel, target_name)
            is_dynamic = Open3.capture3("file #{framework_library_path}")[0].include? "dynamically linked shared library"
            if is_dynamic == true
                framework_target_info["rule"] = "apple_dynamic_framework_import"
            elsif is_dynamic == false
                framework_target_info["rule"] = "apple_static_framework_import"
                if Dir.glob(framework_path + "/Modules/*.swiftmodule").size > 0
                    framework_target_info["alwayslink"] = "True"
                end
            else
                raise "unexpected #{framework_library_path} is_dynamic"
            end
            framework_target_info["framework_imports"] = framework_library_path
        end
        return target_name
    end
    
    def generate_bazel_target_name_for_library_import(library_path, target_info_hash_for_bazel)
        library_target_name = get_bazel_target_name_for_library_import library_path
        unless target_info_hash_for_bazel.has_key? library_target_name
            target_info = KeyValueStore.get_key_value_store_in_container(target_info_hash_for_bazel, library_target_name)
            target_info["rule"] = "objc_import"
            target_info["archives"] = library_path
        end
        return library_target_name
    end
    
    def add_deps_for_target_info(target_info, is_swift, header, total_header_module_hash, total_header_namspace_hash, target_info_hash_for_bazel, target_info_hash_for_xcode, analyze_result)
        if header
            if header.include? ".framework/"
                framework_path = header.split(".framework/")[0] + ".framework"
                header_target_name = generate_bazel_target_name_for_framework_import(framework_path, target_info_hash_for_bazel)
                target_info["deps"] = Set.new unless target_info["deps"]
                target_info["deps"].add header_target_name
                if target_info["rule"] == "cc_library"
                    target_info["framework_search_paths"] = Set.new unless target_info["framework_search_paths"]
                    target_info["framework_search_paths"].add File.dirname(framework_path)
                end
            elsif total_header_module_hash and total_header_module_hash[header] and (target_info["rule"] == "objc_library" or target_info["rule"] == "swift_library")
                is_mixed = false
                if not is_swift or target_info["module_name"] != total_header_module_hash[header]
                    is_mixed = true
                end
                header_target_name = get_bazel_target_name_for_module_map(total_header_module_hash[header], is_mixed)
                if not target_info_hash_for_bazel.has_key? header_target_name
                    header_target_name = get_bazel_target_name_for_module_map(total_header_module_hash[header], false)
                end
                if not target_info_hash_for_bazel.has_key? header_target_name
                    binding.pry
                end

                key = "module_maps"
                key = "objc_" + key if is_swift
                target_info[key] = Set.new unless target_info[key]
                target_info[key].add header_target_name

                header_target_name = get_bazel_target_name_for_header_map(total_header_namspace_hash, header)
                key = "header_maps"
                key = "objc_" + key if is_swift
                target_info[key] = Set.new unless target_info[key]
                target_info[key].add header_target_name

            elsif total_header_namspace_hash and total_header_namspace_hash[header]
                header_target_name = get_bazel_target_name_for_header_map(total_header_namspace_hash, header)
                key = "header_maps"
                key = "objc_" + key if is_swift
                target_info[key] = Set.new unless target_info[key]
                target_info[key].add header_target_name
            elsif header.end_with? "-Swift.h"
                header_target_name = get_bazel_target_name_for_header_map(total_header_namspace_hash, header)
                key = "header_maps"
                key = "objc_" + key if is_swift
                target_info[key] = Set.new unless target_info[key]
                target_info[key].add header_target_name

                if not is_swift
                    swift_module_target_name = target_info_hash_for_xcode.keys.filter{|e|target_info_hash_for_xcode[e][:product_module_name]}.detect{|e|target_info_hash_for_xcode[e][:product_module_name] +  "_swift_header_map" == header_target_name}
                    if swift_module_target_name
                        swift_objc_bridging_header = target_info_hash_for_xcode[swift_module_target_name][:swift_objc_bridging_header]
                        if swift_objc_bridging_header
                            add_deps_for_target_info(target_info, is_swift, swift_objc_bridging_header, total_header_module_hash, total_header_namspace_hash, target_info_hash_for_bazel, target_info_hash_for_xcode, analyze_result)
                            FileFilter.get_pure_objc_source_file_extnames.each do | objc_extname |
                                extname_analyze_result = KeyValueStore.get_key_value_store_in_container(analyze_result, objc_extname)
                                file_headers_hash = KeyValueStore.get_key_value_store_in_container(extname_analyze_result, :file_headers_hash)
                                file_includes_hash = KeyValueStore.get_key_value_store_in_container(extname_analyze_result, :file_includes_hash)

                                next unless file_headers_hash[swift_objc_bridging_header]
                                file_headers_hash[swift_objc_bridging_header].each do | header2 |
                                    add_deps_for_target_info(target_info, is_swift, header2, total_header_module_hash, total_header_namspace_hash, target_info_hash_for_bazel, target_info_hash_for_xcode, analyze_result)
                                end
                                target_info["includes"] = Set.new unless target_info["includes"]
                                target_info["includes"].merge file_includes_hash[swift_objc_bridging_header] if file_includes_hash[swift_objc_bridging_header]
                            end
                        end
                    end
                end
            else
                header_target_name = get_bazel_target_name_for_general_header(header)
                header_target_info = KeyValueStore.get_key_value_store_in_container(target_info_hash_for_bazel, header_target_name)
                header_target_info["rule"] = "cc_header"
                header_target_info["hdrs"] = Set.new unless header_target_info["hdrs"]
                header_target_info["hdrs"].add header

                key = "deps"

                target_info[key] = Set.new unless target_info[key]
                target_info[key].add header_target_name
            end
        end
    end

    def get_bazel_target_name_for_library_import(library_path)
        return "import_" + get_bazel_target_name_for_product_file_name(File.basename(library_path))
    end

    def get_bazel_target_name_for_framework_import(framework_path)
        return "import_" + get_bazel_target_name_for_product_file_name(File.basename(framework_path))
    end
    
    def get_bazel_target_name_for_product_file_name(product_file_name)
        return get_legal_bazel_target_name(product_file_name)
    end

    def get_bazel_target_name_for_product_file_name_and_extname(product_file_name, extname)
        return get_legal_bazel_target_name(product_file_name + extname)
    end

    def get_bazel_target_name_for_product_file_name_and_extname_and_swift_module_name(product_file_name, extname, module_name)
        if module_name
            return module_name + "_swift"
        else
            return get_bazel_target_name_for_product_file_name_and_extname(product_file_name, extname)
        end
    end

    def get_bazel_target_name_for_swift_header_map(module_name)
        return module_name + "_swift_header_map"
    end

    def get_bazel_target_name_for_header_map(total_header_namspace_hash, header)
        namespace = nil
        if total_header_namspace_hash.has_key? header
            namespace = total_header_namspace_hash[header]
        else
            if header == header.split("/")[0] + "/" + header.split("/")[0] + "-Swift.h"
                namespace = header.split("/")[0]
                return namespace + "_swift_header_map"
            end
        end

        raise unless namespace
        
        if namespace.size > 0
            return namespace + "_header_map"
        else
            path = File.dirname(header) + File.extname(header)
            return get_legal_bazel_target_name(path).downcase + "_header_map"
        end
    end

    def get_bazel_target_name_for_module_map(module_name, is_mixed)
        raise unless module_name and module_name.size > 0
        if is_mixed
            return module_name + "_mixed_module_map"
        else
            return module_name + "_module_map"
        end
    end

    def get_bazel_target_name_for_general_header(path)
        path = File.dirname(path) + File.extname(path)
        return get_legal_bazel_target_name(path).downcase + "_header"
    end

    def get_legal_bazel_target_name(name)
        name = DynamicConfig.filter_content(name)
        return name.gsub(/[^a-zA-Z0-9]/, "_")
    end

end