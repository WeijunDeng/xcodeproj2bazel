class BazelTranslator
    def translate_module_map(analyze_result, user_module_hash, target_info_hash_for_xcode, target_info_hash_for_bazel)
        user_module_hash.each do | product_module_name, hash |
            umbrella_header = hash[:umbrella_header]
            moduel_map_headers = hash[:moduel_map_headers]
            module_map_file = hash[:module_map_file]
            has_swift = hash[:has_swift]

            if has_swift
                swift_bazel_target_name = get_bazel_target_name_for_swift_module_name(product_module_name)
                swift_header_target_name = get_bazel_target_name_for_swift_header_map(product_module_name)
                header_target_info = KeyValueStore.get_key_value_store_in_container(target_info_hash_for_bazel, swift_header_target_name)
                header_target_info["rule"] = "header_map"
                header_target_info["namespace"] = product_module_name
                header_target_info["direct_hdr_providers"] = [":" + swift_bazel_target_name]
            end

            next unless module_map_file or umbrella_header
            next unless moduel_map_headers and moduel_map_headers.size > 0
            next if module_map_file and module_map_file.include? ".framework/"

            header_target_name = get_bazel_target_name_for_module_map(product_module_name, false)
            header_target_info = KeyValueStore.get_key_value_store_in_container(target_info_hash_for_bazel, header_target_name)
            header_target_info["rule"] = "module_map"
            header_target_info["module_name"] = product_module_name
            header_target_info["module_map_file"] = module_map_file if module_map_file
            header_target_info["umbrella_header"] = umbrella_header if umbrella_header
            header_target_info["hdrs"] = moduel_map_headers

            if has_swift
                swift_bazel_target_name = get_bazel_target_name_for_swift_module_name(product_module_name)
                mixed_header_target_name = get_bazel_target_name_for_module_map(product_module_name, true)
                header_target_info = KeyValueStore.get_key_value_store_in_container(target_info_hash_for_bazel, mixed_header_target_name)
                header_target_info["rule"] = "module_map"
                header_target_info["module_name"] = product_module_name
                header_target_info["module_map_file"] = module_map_file if module_map_file
                header_target_info["umbrella_header"] = umbrella_header if umbrella_header
                header_target_info["hdrs"] = moduel_map_headers
                header_target_info["deps"] = [swift_bazel_target_name]
            end

            moduel_map_deps = Set.new

            target_info_hash_for_xcode.each do | target_name, info_hash |
                file_deps_hash = KeyValueStore.get_key_value_store_in_container(analyze_result, target_name)
                next unless file_deps_hash
                moduel_map_headers.each do | file |
                    moduel_map_deps.merge file_deps_hash[file] if file_deps_hash[file]
                end
            end
            hash[:moduel_map_deps] = moduel_map_deps
        end
    end

    def translate_header_map(target_info_hash_for_xcode, target_info_hash_for_bazel)
        target_info_hash_for_xcode.each do | target_name, info_hash |
            use_headermap = info_hash[:use_headermap]
            next unless use_headermap
            namespace = info_hash[:namespace]
            target_public_headermap = info_hash[:target_public_headermap]
            target_private_headermap = info_hash[:target_private_headermap]
            
            next if (target_public_headermap.size + target_private_headermap.size) == 0

            public_headers = target_public_headermap.values.map{|x|x.to_a}.flatten.to_set
            if public_headers.size > 0
                header_target_name = get_bazel_target_name_for_header_map(target_name, true)
                header_target_info = KeyValueStore.get_key_value_store_in_container(target_info_hash_for_bazel, header_target_name)
                header_target_info["rule"] = "header_map"
                header_target_info["namespace"] = namespace
                header_target_info["namespace_only"] = "True"
                header_target_info["hdrs"] = public_headers
            end

            private_headers = target_private_headermap.values.map{|x|x.to_a}.flatten.to_set
            if private_headers.size > 0
                header_target_name = get_bazel_target_name_for_header_map(target_name, false)
                header_target_info = KeyValueStore.get_key_value_store_in_container(target_info_hash_for_bazel, header_target_name)
                header_target_info["rule"] = "header_map"
                header_target_info["namespace"] = namespace
                header_target_info["hdrs"] = private_headers
            end
        end
    end

    def translate(target_info_hash_for_xcode, analyze_result)

        target_info_hash_for_bazel = {}

        user_module_hash = analyze_result[:user_module_hash]
        translate_module_map(analyze_result, user_module_hash, target_info_hash_for_xcode, target_info_hash_for_bazel)
        translate_header_map(target_info_hash_for_xcode, target_info_hash_for_bazel)

        total_alwayslink_product_file_names = target_info_hash_for_xcode.values.map{|e|e[:target_links_hash][:alwayslink_product_file_names].to_a}.flatten.map{|x|x.downcase}.to_set

        product_file_name_hash = {}
        target_info_hash_for_xcode.each do | target_name, info_hash |
            product_file_name = info_hash[:product_file_name]
            product_file_name_hash[product_file_name] = target_name
        end

        target_info_hash_for_xcode.each do | target_name, info_hash |
    
            pch = info_hash[:pch]
            flags_sources_hash = info_hash[:flags_sources_hash]
            header_path_hash_for_target_headermap = info_hash[:header_path_hash_for_target_headermap]
            header_path_hash_for_project_headermap = info_hash[:header_path_hash_for_project_headermap]
    
            product_name = info_hash[:product_name]
            enable_modules = info_hash[:enable_modules]
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
            clang_enable_objc_arc = info_hash[:clang_enable_objc_arc]
            target_link_flags = info_hash[:target_link_flags]
            target_defines = info_hash[:target_defines]
            c_target_defines = info_hash[:c_target_defines]
            cxx_target_defines = info_hash[:cxx_target_defines]
            swift_target_defines = info_hash[:swift_target_defines]
            swift_objc_bridging_header = info_hash[:swift_objc_bridging_header]
            target_header_dirs = info_hash[:target_header_dirs].select{|x|x.class==String}
            
            alwayslink = total_alwayslink_product_file_names.include? product_file_name.downcase
            if File.extname(product_file_name) == ".framework" and mach_o_type == "mh_dylib"
                alwayslink = true
            end
    
            relative_sources_files = Set.new
            if product_module_name and user_module_hash[product_module_name]
                umbrella_header = user_module_hash[product_module_name][:umbrella_header]
                if umbrella_header
                    relative_sources_files.add umbrella_header
                end
                module_map_file = user_module_hash[product_module_name][:module_map_file]
                if module_map_file
                    relative_sources_files.merge user_module_hash[product_module_name][:moduel_map_headers]
                end
            end
            if pch
                relative_sources_files.add pch
            end
            if swift_objc_bridging_header
                relative_sources_files.add swift_objc_bridging_header
            end

            dep_bazel_source_targets = Set.new
            swift_bazel_target_name = nil

            flags_index_hash = {}
            extname_count_hash = {}
            flags_sources_hash.each do | flags, source_files |
                extname = flags[0]
                extname_count_hash[extname] = 0 unless extname_count_hash[extname]
                flags_index_hash[flags] = extname_count_hash[extname]
                extname_count_hash[extname] = extname_count_hash[extname] + 1

                if FileFilter.get_source_file_extnames_swift.include? extname
                    binding.pry if extname_count_hash[extname] > 1
                end
            end

            file_deps_hash = KeyValueStore.get_key_value_store_in_container(analyze_result, target_name)

            flags_sources_hash.each do | flags, source_files |
                extname = flags[0]
                file_compiler_flags = flags[1]

                if FileFilter.get_source_file_extnames_d.include? extname
                    dtrace_target_name = get_bazel_target_name_for_product_file_name_and_extname_and_index_and_count(product_file_name, extname, 0, 0)
                    binding.pry if target_info_hash_for_bazel.include? dtrace_target_name
                    target_info = KeyValueStore.get_key_value_store_in_container(target_info_hash_for_bazel, dtrace_target_name)
                    target_info["rule"] = "dtrace_compile"
                    target_info["srcs"] = source_files

                    dtrace_headermap_target_name = target_name + "_dtrace_header_map"
                    binding.pry if target_info_hash_for_bazel.include? dtrace_headermap_target_name
                    target_info = KeyValueStore.get_key_value_store_in_container(target_info_hash_for_bazel, dtrace_headermap_target_name)
                    target_info["rule"] = "header_map"
                    target_info["hdrs"] = [":#{dtrace_target_name}"]
                end

                if FileFilter.get_source_file_extnames_swift.include? extname
                    binding.pry unless product_module_name
                    bazel_target_name = get_bazel_target_name_for_swift_module_name(product_module_name)
                    binding.pry if target_info_hash_for_bazel.include? bazel_target_name
                    dep_bazel_source_targets.add bazel_target_name
                    swift_bazel_target_name = bazel_target_name
                    target_info = KeyValueStore.get_key_value_store_in_container(target_info_hash_for_bazel, bazel_target_name)
                    target_info["rule"] = "swift_library"
                    target_info["alwayslink"] = "True"
                    target_info["module_name"] = product_module_name
                    add_file_deps([:user_module, product_module_name], target_info, target_info_hash_for_bazel, target_info_hash_for_xcode, user_module_hash, info_hash, Set.new)

                    if swift_objc_bridging_header
                        target_info["objc_bridging_header"] = swift_objc_bridging_header
                    end

                    target_info["srcs"] = Set.new unless target_info["srcs"]
                    source_files.each do | file |        
                        target_info["srcs"].add file
                    end

                    (relative_sources_files + source_files).uniq.each do | file |
                        next unless file_deps_hash[file]
                        file_deps_hash[file].each do | dep_info |
                            add_file_deps(dep_info, target_info, target_info_hash_for_bazel, target_info_hash_for_xcode, user_module_hash, info_hash, Set.new)
                        end
                    end

                    if target_info["objc_includes"] and target_info["objc_includes"].size > 0 and target_header_dirs.size > 0
                        # keep original search order
                        target_info["objc_includes"] = (target_header_dirs + target_info["objc_includes"].sort).select{|x| target_info["objc_includes"].include? x}.uniq
                    end

                    if target_info["objc_header_maps"] and target_info["objc_header_maps"].size > 1
                        target_info["objc_header_maps"] = target_info["objc_header_maps"].sort_by { | x |
                            if x.end_with? "_public_header_map"
                                "0 " + x
                            elsif x.end_with? "_private_header_map"
                                "1 " + x
                            elsif x.end_with? "_project_header_map"
                                "2 " + x
                            else
                                "3 " + x
                            end
                        }
                    end

                    if target_defines and target_defines.size > 0
                        target_info["objc_defines"] = Set.new unless target_info["objc_defines"]
                        target_info["objc_defines"].merge target_defines
                    end
                    if c_target_defines and c_target_defines.size > 0
                        target_info["objc_defines"] = Set.new unless target_info["objc_defines"]
                        target_info["objc_defines"].merge c_target_defines
                    end
                    if swift_target_defines.size > 0
                        target_info["defines"] = Set.new unless target_info["defines"]
                        target_info["defines"].merge swift_target_defines
                    end
                    if target_swift_compile_flags and target_swift_compile_flags.size > 0
                        target_info["copts"] = [] unless target_info["copts"]
                        target_info["copts"] = target_info["copts"] + target_swift_compile_flags
                    end
                    if file_compiler_flags.size > 0
                        target_info["copts"] = [] unless target_info["copts"]
                        target_info["copts"] = target_info["copts"] + file_compiler_flags
                    end
                    if target_link_flags.size > 0
                        target_info["linkopts"] = [] unless target_info["linkopts"]
                        target_info["linkopts"] = target_info["linkopts"] + target_link_flags
                    end
                end

                if FileFilter.get_source_file_extnames_c_type.include? extname
                    bazel_target_name = get_bazel_target_name_for_product_file_name_and_extname_and_index_and_count(product_file_name, extname, flags_index_hash[flags], extname_count_hash[extname])
                    binding.pry if target_info_hash_for_bazel.include? bazel_target_name
                    dep_bazel_source_targets.add bazel_target_name
                    target_info = KeyValueStore.get_key_value_store_in_container(target_info_hash_for_bazel, bazel_target_name)
                    type = "cc_library"
                    if FileFilter.get_source_file_extnames_mixed_objective_c.include? extname
                        type = "objc_library"
                    end
                    target_info["rule"] = type
                    target_info["alwayslink"] = "True" if alwayslink
                    target_info["pch"] = pch if pch

                    if target_info["rule"] == "objc_library"
                        if enable_modules
                            target_info["enable_modules"] = "True"
                        else
                            target_info["enable_modules"] = "False"
                        end
                        if product_module_name
                            add_file_deps([:user_module, product_module_name], target_info, target_info_hash_for_bazel, target_info_hash_for_xcode, user_module_hash, info_hash, Set.new)
                        end
                    end
                    target_info["defines"] = Set.new unless target_info["defines"]
                    target_info["defines"].merge target_defines
                    if FileFilter.get_source_file_extnames_mixed_c.include? extname
                        target_info["copts"] = [] unless target_info["copts"]
                        target_info["copts"] = target_info["copts"] + target_c_compile_flags

                        target_info["defines"].merge c_target_defines
                    end
                    if FileFilter.get_source_file_extnames_mixed_cpp.include? extname
                        target_info["copts"] = [] unless target_info["copts"]
                        target_info["copts"] = target_info["copts"] + target_cxx_compile_flags

                        target_info["defines"].merge cxx_target_defines
                    end

                    target_info["deps"] = Set.new unless target_info["deps"]
                    
                    (relative_sources_files + source_files).uniq.each do | file |
                        next unless file_deps_hash[file]
                        file_deps_hash[file].each do | dep_info |
                            add_file_deps(dep_info, target_info, target_info_hash_for_bazel, target_info_hash_for_xcode, user_module_hash, info_hash, Set.new)
                        end
                    end

                    if target_info["includes"] and target_info["includes"].size > 0 and target_header_dirs and target_header_dirs.size > 0
                        # keep original search order
                        target_info["includes"] = (target_header_dirs + target_info["includes"].sort).select{|x| target_info["includes"].include? x}.uniq
                    end
                    if target_info["header_maps"] and target_info["header_maps"].size > 1
                        target_info["header_maps"] = target_info["header_maps"].sort_by { | x |
                            if x.end_with? "_public_header_map"
                                "0 " + x
                            elsif x.end_with? "_private_header_map"
                                "1 " + x
                            elsif x.end_with? "_project_header_map"
                                "2 " + x
                            else
                                "3 " + x
                            end
                        }
                    end
                    source_files.each do | file |
                        if target_info["rule"] == "objc_library"
                            binding.pry if file_compiler_flags.include? "-fobjc-arc" and file_compiler_flags.include? "-fno-objc-arc"
                            if clang_enable_objc_arc == true and not file_compiler_flags.include? "-fno-objc-arc"
                                target_info["srcs"] = Set.new unless target_info["srcs"]
                                target_info["srcs"].add file
                            else
                                target_info["non_arc_srcs"] = Set.new unless target_info["non_arc_srcs"]
                                target_info["non_arc_srcs"].add file
                            end
                        else
                            target_info["srcs"] = Set.new unless target_info["srcs"]
                            target_info["srcs"].add file
                        end
                    end
                    if file_compiler_flags.size > 0
                        target_info["copts"] = [] unless target_info["copts"]
                        target_info["copts"] = target_info["copts"] + file_compiler_flags
                    end
                    if target_link_flags.size > 0
                        target_info["linkopts"] = [] unless target_info["linkopts"]
                        target_info["linkopts"] = target_info["linkopts"] + target_link_flags
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
                    if target_info["rule"] == "ios_application" or 
                        target_info["rule"] == "ios_framework" or 
                        target_info["rule"] == "ios_static_framework"
                        target_info["frameworks"] = Set.new unless target_info["frameworks"]
                        target_info["frameworks"].add dep_bazel_target_name_name
                        next
                    elsif target_info["rule"] == "static_library"
                        next
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
            if target_info["rule"] == "ios_application" or 
                target_info["rule"] == "ios_extension" or
                target_info["rule"] == "ios_framework" or
                target_info["rule"] == "ios_static_framework"
                iphoneos_deployment_target = info_hash[:iphoneos_deployment_target]
                if iphoneos_deployment_target.size > 0
                    target_info["minimum_os_version"] = iphoneos_deployment_target
                end
            end
            if target_info["rule"] == "ios_application" or 
                target_info["rule"] == "ios_extension" or
                target_info["rule"] == "ios_framework" or
                target_info["rule"] == "ios_static_framework"
                targeted_device_family = info_hash[:targeted_device_family]
                if targeted_device_family.size > 0
                    target_info["families"] = targeted_device_family
                end
                target_app_icon = info_hash[:target_app_icon]
                if target_app_icon and target_app_icon.size > 0
                    target_info["app_icons"] = [target_app_icon + "/**"]
                end
                provisioning_profile_specifier = info_hash[:provisioning_profile_specifier]
                if provisioning_profile_specifier and provisioning_profile_specifier.size > 0
                    target_info["provisioning_profile"] = provisioning_profile_specifier
                end
                if product_module_name and product_module_name.size > 0
                    target_info["bundle_name"] = product_module_name
                else
                    target_info["bundle_name"] = product_name
                end
            end
        end

        target_info_hash_for_bazel.sort.each do | target_name, hash |
            hash.keys.each do | key |
                if hash[key].class == Set
                    hash[key].each do | v |
                        binding.pry if v == nil
                    end
                    hash[key] = hash[key].sort.uniq {|x|x.downcase}
                elsif hash[key].class == Array
                    hash[key].each do | v |
                        binding.pry if v == nil
                    end
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
        if framework_path.include? ".xcframework/"
            xcframework_path = framework_path.split(".xcframework/")[0] + ".xcframework"
            target_name = generate_bazel_target_name_for_xcframework_import(xcframework_path, target_info_hash_for_bazel)
            return target_name
        else
            framework_path = FileFilter.get_exist_expand_path_dir(framework_path)
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
                framework_target_info["framework_imports"] = framework_path
            end
            return target_name
        end
    end
    
    def generate_bazel_target_name_for_xcframework_import(xcframework_path, target_info_hash_for_bazel)
        xcframework_path = FileFilter.get_exist_expand_path_dir(xcframework_path)
        target_name = get_bazel_target_name_for_framework_import xcframework_path
        unless target_info_hash_for_bazel.has_key? target_name
            framework_name = File.basename(xcframework_path).split(".")[0]

            xcframework_info = FileFilter.get_match_xcframework_info(xcframework_path)
            binding.pry unless xcframework_info
            library_path = xcframework_info[:LibraryPath]
            if library_path.end_with? ".framework"
                library_path = library_path + "/" + framework_name
            end
            binding.pry unless File.exist? library_path

            framework_target_info = KeyValueStore.get_key_value_store_in_container(target_info_hash_for_bazel, target_name)
            framework_target_info["xcframework_imports"] = xcframework_path
            if Open3.capture3("file #{library_path}")[0].include? "dynamically linked shared library"
                framework_target_info["rule"] = "apple_dynamic_xcframework_import"
            else
                framework_target_info["rule"] = "apple_static_xcframework_import"
            end
        end
        return target_name
    end

    def generate_bazel_target_name_for_library_import(library_path, target_info_hash_for_bazel)
        if library_path.include? ".xcframework/"
            xcframework_path = library_path.split(".xcframework/")[0] + ".xcframework"
            target_name = generate_bazel_target_name_for_xcframework_import(xcframework_path, target_info_hash_for_bazel)
            return target_name
        else
            target_name = get_bazel_target_name_for_library_import library_path
            unless target_info_hash_for_bazel.has_key? target_name
                target_info = KeyValueStore.get_key_value_store_in_container(target_info_hash_for_bazel, target_name)
                target_info["rule"] = "objc_import"
                target_info["archives"] = library_path
            end
            return target_name
        end
    end
    
    def add_file_deps(dep_info, target_info, target_info_hash_for_bazel, target_info_hash_for_xcode, user_module_hash, info_hash, file_deps_set)
        binding.pry unless dep_info.class == Array

        return if file_deps_set.include? dep_info
        file_deps_set.add dep_info

        if dep_info[0] == :system_framework
            system_framework = dep_info[1]
            # TODO
            return
        end
        if dep_info[0] == :system_library
            system_library = dep_info[1]
            info_hash[:target_links_hash][:system_libraries].add system_library
            return
        end
        if dep_info[0] == :private_headermap
            header_target_name = get_bazel_target_name_for_header_map(dep_info[2], false)
            key = "header_maps"
            key = "objc_" + key if target_info["rule"] == "swift_library"
            target_info[key] = Set.new unless target_info[key]
            target_info[key].add header_target_name
            return
        end

        if dep_info[0] == :public_headermap
            header_target_name = get_bazel_target_name_for_header_map(dep_info[2], true)
            key = "header_maps"
            key = "objc_" + key if target_info["rule"] == "swift_library"
            target_info[key] = Set.new unless target_info[key]
            target_info[key].add header_target_name
            return
        end

        if dep_info[0] == :project_headermap
            header = dep_info[1]
            header_target_name = "#{dep_info[2]}_project_header_map"
            header_target_info = KeyValueStore.get_key_value_store_in_container(target_info_hash_for_bazel, header_target_name)
            header_target_info["rule"] = "header_map"
            header_target_info["hdrs"] = Set.new unless header_target_info["hdrs"]
            header_target_info["hdrs"].add header

            key = "header_maps"
            key = "objc_" + key if target_info["rule"] == "swift_library"
            target_info[key] = Set.new unless target_info[key]
            target_info[key].add header_target_name
            return
        end

        if dep_info[0] == :headers
            header = dep_info[1]
            
            header_target_name = nil
            if header.downcase.include? ".framework/"
                framework_path = header.downcase.split(".framework/")[0] + ".framework"
                framework_path = FileFilter.get_exist_expand_path_dir(framework_path)
                header_target_name = generate_bazel_target_name_for_framework_import(framework_path, target_info_hash_for_bazel)
                if target_info["rule"] == "cc_library"
                    target_info["framework_search_paths"] = Set.new unless target_info["framework_search_paths"]
                    target_info["framework_search_paths"].add File.dirname(framework_path)
                end
            elsif header.downcase.include? ".xcframework/"
                framework_path = header.downcase.split(".xcframework/")[0] + ".xcframework"
                framework_path = FileFilter.get_exist_expand_path_dir(framework_path)
                header_target_name = generate_bazel_target_name_for_xcframework_import(framework_path, target_info_hash_for_bazel)
                if target_info["rule"] == "cc_library"
                    target_info["framework_search_paths"] = Set.new unless target_info["framework_search_paths"]
                    target_info["framework_search_paths"].add File.dirname(framework_path)
                end
            else
                header_target_name = get_bazel_target_name_for_general_header(header)
                header_target_info = KeyValueStore.get_key_value_store_in_container(target_info_hash_for_bazel, header_target_name)
                header_target_info["rule"] = "cc_header"
                header_target_info["hdrs"] = Set.new unless header_target_info["hdrs"]
                header_target_info["hdrs"].add header
            end
    
            key = "deps"
            target_info[key] = Set.new unless target_info[key]
            target_info[key].add header_target_name
            
            search_path = dep_info[2]
            if search_path
                key = "includes"
                key = "objc_" + key if target_info["rule"] == "swift_library"
                target_info[key] = Set.new unless target_info[key]
                target_info[key].add search_path
            end
            return
        end

        if dep_info[0] == :user_module
            user_module = dep_info[1]
            return if target_info["rule"] == "cc_library"
            binding.pry unless user_module_hash[user_module]
            
            module_map_file = user_module_hash[user_module][:module_map_file]
            if module_map_file and module_map_file.include? ".framework/"
                framework_path = module_map_file.split(".framework/")[0] + ".framework"
                header_target_name = generate_bazel_target_name_for_framework_import(framework_path, target_info_hash_for_bazel)
                key = "deps"
                target_info[key] = Set.new unless target_info[key]
                target_info[key].add header_target_name
            else
                is_mixed = true
                if target_info["rule"] == "swift_library" and target_info["module_name"] == user_module
                    is_mixed = false
                end
                header_target_name = get_bazel_target_name_for_module_map(user_module, is_mixed)
                if not target_info_hash_for_bazel.has_key? header_target_name
                    header_target_name = get_bazel_target_name_for_module_map(user_module, false)
                end
                if target_info_hash_for_bazel.has_key? header_target_name
                    if target_info["module_name"] == user_module
                        if target_info["rule"] == "swift_library"
                            target_info["copts"] = [] unless target_info["copts"]
                            target_info["copts"].push "-import-underlying-module" unless target_info["copts"].include? "-import-underlying-module"
                        end
                    end
    
                    key = "module_maps"
                    key = "objc_" + key if target_info["rule"] == "swift_library"
                    target_info[key] = Set.new unless target_info[key]
                    target_info[key].add header_target_name
    
                    user_module_hash[user_module][:moduel_map_deps].each do | moduel_map_dep |
                        add_file_deps(moduel_map_dep, target_info, target_info_hash_for_bazel, target_info_hash_for_xcode, user_module_hash, info_hash, file_deps_set)
                    end
                end
            end

            if target_info["rule"] == "swift_library" and user_module_hash[user_module][:has_swift] and target_info["module_name"] != user_module
                swift_target_name = get_bazel_target_name_for_swift_module_name(user_module)
                key = "deps"
                target_info[key] = Set.new unless target_info[key]
                target_info[key].add swift_target_name
            end
            return
        end

        if dep_info[0] == :swift_header
            swift_header = dep_info[1]
            module_name = File.basename(swift_header).sub("-Swift.h", "")
            binding.pry unless swift_header == "#{module_name}/#{module_name}-Swift.h" or swift_header == "#{module_name}-Swift.h"
            swift_header_target_name = get_bazel_target_name_for_swift_header_map(module_name)
            if target_info_hash_for_bazel.has_key? swift_header_target_name
                key = "header_maps"
                key = "objc_" + key if target_info["rule"] == "swift_library"
                target_info[key] = Set.new unless target_info[key]
                target_info[key].add swift_header_target_name
            else
                binding.pry
            end

            return
        end

        if dep_info[0] == :dtrace_header
            dtrace_headermap_target_name = dep_info[2] + "_dtrace_header_map"
            key = "header_maps"
            key = "objc_" + key if target_info["rule"] == "swift_library"
            target_info[key] = Set.new unless target_info[key]
            target_info[key].add dtrace_headermap_target_name
            return
        end

        binding.pry
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

    def get_bazel_target_name_for_swift_module_name(swift_module_name)
        return swift_module_name + "_swift"
    end

    def get_bazel_target_name_for_product_file_name_and_extname_and_index_and_count(product_file_name, extname, index, count)
        suffix = ""
        if count > 1
            suffix = "_" + index.to_s
        end
        return get_legal_bazel_target_name(product_file_name + extname + suffix)
    end

    def get_bazel_target_name_for_swift_header_map(module_name)
        return module_name + "_swift_header_map"
    end

    def get_bazel_target_name_for_header_map(target_name, is_public)
        if is_public
            return get_legal_bazel_target_name(target_name) + "_public_header_map"
        else
            return get_legal_bazel_target_name(target_name) + "_private_header_map"
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
        return name.gsub(/\W/, "_")
    end

end