class BazelTranslator
    def translate_module_map(analyze_result, user_module_hash, target_module_name_hash, target_info_hash_for_bazel)
        user_module_hash.each do | module_name, hash |
            umbrella_header = hash[:umbrella_header]
            module_map_headers = hash[:module_map_headers]
            module_map_file = hash[:module_map_file]
            has_swift = hash[:has_swift]

            next if module_map_file and module_map_file.include? ".framework/"

            if module_map_file or umbrella_header
                header_target_name = get_bazel_target_name_for_module_map(module_name, false)
                header_target_info = KeyValueStore.get_key_value_store_in_container(target_info_hash_for_bazel, header_target_name)
                header_target_info["rule"] = "module_map"
                header_target_info["module_name"] = module_name
                header_target_info["module_map_file"] = module_map_file if module_map_file
                header_target_info["umbrella_header"] = umbrella_header if umbrella_header
                header_target_info["hdrs"] = module_map_headers if module_map_headers and module_map_headers.size > 0
            end

            if has_swift
                swift_bazel_target_name = get_bazel_target_name_for_swift_module_name(module_name)
                mixed_header_target_name = get_bazel_target_name_for_module_map(module_name, true)
                header_target_info = KeyValueStore.get_key_value_store_in_container(target_info_hash_for_bazel, mixed_header_target_name)
                header_target_info["rule"] = "module_map"
                header_target_info["module_name"] = module_name
                header_target_info["module_map_file"] = module_map_file if module_map_file
                header_target_info["umbrella_header"] = umbrella_header if umbrella_header
                header_target_info["hdrs"] = module_map_headers if module_map_headers and module_map_headers.size > 0
                header_target_info["deps"] = [swift_bazel_target_name]
            end
        end
    end

    def translate_header_map(target_info_hash_for_xcode, target_module_name_hash, target_info_hash_for_bazel)
        target_info_hash_for_xcode.each do | target_name, info_hash |
            has_swift = info_hash[:has_swift]

            if has_swift
                module_name = target_module_name_hash[target_name]
                binding.pry unless module_name
                swift_bazel_target_name = get_bazel_target_name_for_swift_module_name(module_name)
                swift_header_target_name = get_bazel_target_name_for_swift_header_map(module_name)
                header_target_info = KeyValueStore.get_key_value_store_in_container(target_info_hash_for_bazel, swift_header_target_name)
                header_target_info["rule"] = "header_map"
                header_target_info["namespace"] = module_name
                header_target_info["direct_hdr_providers"] = [":" + swift_bazel_target_name]
            end

            use_header_map = info_hash[:use_header_map]
            next unless use_header_map
            namespace = info_hash[:namespace]

            target_public_header_map = info_hash[:target_public_header_map]
            target_private_header_map = info_hash[:target_private_header_map]
            
            public_headers = target_public_header_map.values.to_set
            if public_headers.size > 0
                header_target_name = get_bazel_target_name_for_header_map(namespace, true)
                header_target_info = KeyValueStore.get_key_value_store_in_container(target_info_hash_for_bazel, header_target_name)
                header_target_info["rule"] = "header_map"
                header_target_info["namespace"] = namespace
                header_target_info["namespace_only"] = "True"
                header_target_info["hdrs"] = public_headers
            end

            private_headers = target_private_header_map.values.to_set
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
        target_module_name_hash = analyze_result[:target_module_name_hash]
        target_product_hash = analyze_result[:target_product_hash]

        translate_module_map(analyze_result, user_module_hash, target_module_name_hash, target_info_hash_for_bazel)
        translate_header_map(target_info_hash_for_xcode, target_module_name_hash, target_info_hash_for_bazel)

        total_alwayslink_product_file_names = target_info_hash_for_xcode.values.map{|e|e[:target_links_hash][:alwayslink_product_file_names].to_a}.flatten.to_set

        product_file_name_hash = {}
        target_info_hash_for_xcode.each do | target_name, info_hash |
            product_file_name = info_hash[:product_file_name]
            product_file_name_hash[product_file_name] = target_name
        end

        target_info_hash_for_xcode.each do | target_name, info_hash |
    
            pch = info_hash[:pch]
            flags_sources_hash = info_hash[:flags_sources_hash]
            header_path_hash_for_target_header_map = info_hash[:header_path_hash_for_target_header_map]
            header_path_hash_for_project_header_map = info_hash[:header_path_hash_for_project_header_map]

            module_name = target_module_name_hash[target_name]
            product_name = info_hash[:product_name]
            enable_modules = info_hash[:enable_modules]
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
            extension_safe = info_hash[:extension_safe]
            target_defines = info_hash[:target_defines]
            c_target_defines = info_hash[:c_target_defines]
            cxx_target_defines = info_hash[:cxx_target_defines]
            swift_target_defines = info_hash[:swift_target_defines]
            swift_objc_bridging_header = info_hash[:swift_objc_bridging_header]
            target_header_dirs = info_hash[:target_header_dirs].select{|x|x.class==String}
            
            alwayslink = total_alwayslink_product_file_names.include? product_file_name
            if File.extname(product_file_name) == ".framework" and mach_o_type == "mh_dylib"
                alwayslink = true
            end
    
            relative_sources_files = Set.new
            if module_name
                relative_sources_files.merge user_module_hash[module_name][:module_map_headers]
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
                    dtrace_target_name = get_bazel_target_name_for_xcode_target_name_and_extname_and_index_and_count(target_name, extname, 0, 0)
                    binding.pry if target_info_hash_for_bazel.include? dtrace_target_name
                    target_info = KeyValueStore.get_key_value_store_in_container(target_info_hash_for_bazel, dtrace_target_name)
                    target_info["rule"] = "dtrace_compile"
                    target_info["srcs"] = source_files

                    dtrace_header_map_target_name = target_name + "_dtrace_header_map"
                    binding.pry if target_info_hash_for_bazel.include? dtrace_header_map_target_name
                    target_info = KeyValueStore.get_key_value_store_in_container(target_info_hash_for_bazel, dtrace_header_map_target_name)
                    target_info["rule"] = "header_map"
                    target_info["hdrs"] = [":#{dtrace_target_name}"]
                end

                if FileFilter.get_source_file_extnames_swift.include? extname
                    binding.pry unless module_name
                    bazel_target_name = get_bazel_target_name_for_swift_module_name(module_name)
                    binding.pry if target_info_hash_for_bazel.include? bazel_target_name
                    dep_bazel_source_targets.add bazel_target_name
                    swift_bazel_target_name = bazel_target_name
                    target_info = KeyValueStore.get_key_value_store_in_container(target_info_hash_for_bazel, bazel_target_name)
                    target_info["rule"] = "swift_library"
                    target_info["alwayslink"] = "True" if alwayslink
                    target_info["module_name"] = module_name
                    add_file_deps([:user_module, module_name], target_info, target_info_hash_for_bazel, target_info_hash_for_xcode, user_module_hash, info_hash, Set.new)

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
                    bazel_target_name = get_bazel_target_name_for_xcode_target_name_and_extname_and_index_and_count(target_name, extname, flags_index_hash[flags], extname_count_hash[extname])
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
                        if module_name
                            add_file_deps([:user_module, module_name], target_info, target_info_hash_for_bazel, target_info_hash_for_xcode, user_module_hash, info_hash, Set.new)
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
    
            bazel_target_name = get_bazel_target_name_for_xcode_target_name(target_name)
            target_info = KeyValueStore.get_key_value_store_in_container(target_info_hash_for_bazel, bazel_target_name)

            if File.extname(product_file_name) == ".a" and mach_o_type == "staticlib"
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
            else
                raise "unsupported product_file_name #{product_file_name}"
            end

            if target_info["rule"] == "ios_framework"
                target_info["extension_safe"] = "True" if extension_safe
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

            target_links_hash[:dependency_target_product_file_names].each do | dependency_target_product_file_name |
                extname = File.extname(dependency_target_product_file_name)
                dependency_product_info = target_product_hash[dependency_target_product_file_name]
                next unless dependency_product_info
                if dependency_product_info[0] == :target_name
                    dependency_target_name = dependency_product_info[1]
                    dependency_target_info = target_info_hash_for_xcode[dependency_target_name]
                    if extname == ".framework"
                        if dependency_target_info[:mach_o_type] == "mh_dylib"
                            if target_info["rule"] == "ios_application" or 
                                target_info["rule"] == "ios_framework" or
                                target_info["rule"] == "ios_extension"
                                target_info["frameworks"] = Set.new unless target_info["frameworks"]
                                target_info["frameworks"].add get_bazel_target_name_for_xcode_target_name(dependency_target_name)
                            end
                            next
                        else
                            target_info["deps"].add get_bazel_target_name_for_xcode_target_name(dependency_target_name)
                            next
                        end
                    elsif extname == ".a"
                        target_info["deps"].add get_bazel_target_name_for_xcode_target_name(dependency_target_name)
                        next
                    elsif extname == ".appex"
                        binding.pry unless target_info["rule"] == "ios_application"
                        target_info["extensions"] = Set.new unless target_info["extensions"]
                        target_info["extensions"].add get_bazel_target_name_for_xcode_target_name(dependency_target_name)
                        next
                    end
                elsif dependency_product_info[0] == :import_path
                    import_path = dependency_target_product_file_name
                    if extname == ".framework"
                        dependency_target_name = generate_bazel_target_name_for_framework_import(import_path, target_info_hash_for_bazel)
                        target_info["deps"].add dependency_target_name
                        next
                    end
                    if extname == ".a"
                        dependency_target_name = generate_bazel_target_name_for_library_import(import_path, target_info_hash_for_bazel)
                        target_info["deps"].add dependency_target_name
                        next
                    end
                end
                binding.pry
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
                target_info["resources"] = Set.new unless target_info["resources"]
                resources_files.each do | resources_file |
                    if target_product_hash[resources_file]
                        if target_product_hash[resources_file][0] == :target_name
                            target_info["resources"].add ":" + get_bazel_target_name_for_xcode_target_name(target_product_hash[resources_file][1])
                        else
                            binding.pry
                        end
                    elsif File.extname(resources_file) == ".metal"
                        metal_file = resources_file
                        metal_target_name = get_legal_bazel_target_name(metal_file)
                        metal_target_info = KeyValueStore.get_key_value_store_in_container(target_info_hash_for_bazel, metal_target_name)
                        metal_target_info["rule"] = "metal_library"
                        metal_target_info["hdrs"] = Dir.glob(File.dirname(metal_file) + "/*.h").sort
                        metal_target_info["srcs"] = [metal_file]

                        target_info["resources"].add ":" + metal_target_name
                    else
                        target_info["resources"].add resources_file
                    end
                end
            end
            if target_info["rule"] == "ios_application" or 
                target_info["rule"] == "ios_extension" or
                target_info["rule"] == "ios_framework"
                iphoneos_deployment_target = info_hash[:iphoneos_deployment_target]
                if iphoneos_deployment_target and iphoneos_deployment_target.size > 0
                    target_info["minimum_os_version"] = iphoneos_deployment_target
                else
                    target_info["minimum_os_version"] = FileFilter.get_default_iphoneos_deployment_target
                end
            end
            if target_info["rule"] == "ios_application" or 
                target_info["rule"] == "ios_extension" or
                target_info["rule"] == "ios_framework"
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
                target_info["bundle_name"] = product_name
            end
        end

        ios_framework_static_library_set_hash = {}
        target_info_hash_for_bazel.each do | target_name, hash |
            if hash["rule"] == "ios_framework"
                static_library_set = Set.new
                find_static_library_in_target_name(target_name, target_info_hash_for_bazel, static_library_set)
                ios_framework_static_library_set_hash[target_name] = static_library_set
            end
        end
        ios_framework_static_library_set_hash.keys.each do | ios_framework_a |
            next unless target_info_hash_for_bazel[ios_framework_a]["frameworks"]
            target_info_hash_for_bazel[ios_framework_a]["frameworks"].each do | ios_framework_b |
                same_library_set = ios_framework_static_library_set_hash[ios_framework_a] & ios_framework_static_library_set_hash[ios_framework_b]
                if same_library_set.size > 0
                    # fix because ios_framework rule avoid deps in https://github.com/bazelbuild/rules_apple/blob/8f6485fe22977adefff996391daa212f0b3bbc7f/apple/internal/ios_rules.bzl#L180
                    target_info_hash_for_bazel[ios_framework_a]["not_avoid_deps"] = Set.new unless target_info_hash_for_bazel[ios_framework_a]["not_avoid_deps"]
                    target_info_hash_for_bazel[ios_framework_a]["not_avoid_deps"].merge same_library_set
                end
            end
        end

        target_info_hash_for_bazel.sort.each do | target_name, hash |
            hash.keys.each do | key |
                if hash[key].class == Set
                    hash[key] = hash[key].select{|x|x and x.size > 0}.sort.uniq {|x|x.downcase}
                elsif hash[key].class == Array
                    hash[key] = hash[key].select{|x|x and x.size > 0}.uniq {|x|x.downcase}
                end
            end
        end

        downcase_target_names = Set.new
        target_info_hash_for_bazel.each do | target_name, hash |
            binding.pry if downcase_target_names.include? target_name.downcase
            downcase_target_names.add target_name.downcase
        end

        return target_info_hash_for_bazel
    end
    
    def find_static_library_in_target_name(target_name, target_info_hash_for_bazel, static_library_set)
        target_info = target_info_hash_for_bazel[target_name]
        if target_info["rule"] == "objc_library" or target_info["rule"] == "cc_library"
            static_library_set.add ":" + target_name
        elsif target_info["rule"] == "apple_static_framework_import"
            framework_path = target_info["framework_imports"]
            framework_name = File.basename(framework_path).split(".")[0]
            static_library_set.add framework_path + "/" + framework_name
        elsif target_info["rule"] == "objc_import"
            static_library_set.add target_info["archives"]
        else
            if target_info["deps"]
                target_info["deps"].each do | dep |
                    find_static_library_in_target_name(dep, target_info_hash_for_bazel, static_library_set)
                end
            end
        end
    end

    def generate_bazel_target_name_for_bundle_version(target_name, version, target_info_hash_for_bazel)
        bundle_version_target_name = get_legal_bazel_target_name(target_name + "_version")
        target_info = KeyValueStore.get_key_value_store_in_container(target_info_hash_for_bazel, bundle_version_target_name)
        unless target_info.size > 0
            target_info["rule"] = "apple_bundle_version"
            target_info["build_version"] = version
        end
        return bundle_version_target_name
    end
    
    def generate_bazel_target_name_for_system_links(target_name, system_framework, system_weak_frameworks, system_libraries, target_info_hash_for_bazel)
        system_links_target_name = get_legal_bazel_target_name(target_name + "_system_library")
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
                unless Open3.capture3("lipo -archs #{framework_library_path}")[0].strip.split(" ").include? DynamicConfig.get_build_arch
                    return nil
                end

                framework_target_info = KeyValueStore.get_key_value_store_in_container(target_info_hash_for_bazel, target_name)
                is_dynamic = Open3.capture3("file #{framework_library_path}")[0].include? "dynamically linked shared library"
                if is_dynamic == true
                    framework_target_info["rule"] = "apple_dynamic_framework_import"
                elsif is_dynamic == false
                    framework_target_info["rule"] = "apple_static_framework_import"
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
            unless Open3.capture3("lipo -archs #{library_path}")[0].strip.split(" ").include? DynamicConfig.get_build_arch
                return nil
            end
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
        if dep_info[0] == :private_header_map
            header_target_name = get_bazel_target_name_for_header_map(dep_info[2], false)
            key = "header_maps"
            key = "objc_" + key if target_info["rule"] == "swift_library"
            target_info[key] = Set.new unless target_info[key]
            target_info[key].add header_target_name
            return
        end

        if dep_info[0] == :public_header_map
            header_target_name = get_bazel_target_name_for_header_map(dep_info[2], true)
            key = "header_maps"
            key = "objc_" + key if target_info["rule"] == "swift_library"
            target_info[key] = Set.new unless target_info[key]
            target_info[key].add header_target_name
            return
        end

        if dep_info[0] == :project_header_map
            header = dep_info[1]
            header_target_name = get_downcase_legal_bazel_target_name "#{dep_info[2]}_project_header_map"
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

        if dep_info[0] == :virtual_header_map
            header = dep_info[1]
            namespace = dep_info[2]
            name = dep_info[3]
            real_header = dep_info[4]
            header = real_header if real_header

            header_target_name = nil
            if namespace and namespace.size > 0
                header_target_name = get_downcase_legal_bazel_target_name "#{name}_#{namespace}_virtual_header_map"
            else
                header_target_name = get_downcase_legal_bazel_target_name "#{name}_virtual_header_map"
            end
            
            header_target_info = KeyValueStore.get_key_value_store_in_container(target_info_hash_for_bazel, header_target_name)
            header_target_info["rule"] = "header_map"
            header_target_info["namespace"] = namespace if namespace and namespace.size > 0
            header_target_info["namespace_only"] = "True" if namespace and namespace.size > 0
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
            search_path = dep_info[2]

            header_target_name = nil
            if header.include? ".framework/"
                framework_path = header.split(".framework/")[0] + ".framework"
                framework_path = FileFilter.get_exist_expand_path_dir(framework_path)
                header_target_name = generate_bazel_target_name_for_framework_import(framework_path, target_info_hash_for_bazel)
                if target_info["rule"] == "cc_library"
                    target_info["framework_search_paths"] = Set.new unless target_info["framework_search_paths"]
                    target_info["framework_search_paths"].add File.dirname(framework_path)
                end
            elsif header.include? ".xcframework/"
                framework_path = header.split(".xcframework/")[0] + ".xcframework"
                framework_path = FileFilter.get_exist_expand_path_dir(framework_path)
                header_target_name = generate_bazel_target_name_for_xcframework_import(framework_path, target_info_hash_for_bazel)
                if target_info["rule"] == "cc_library"
                    target_info["framework_search_paths"] = Set.new unless target_info["framework_search_paths"]
                    target_info["framework_search_paths"].add File.dirname(framework_path)
                end
            elsif search_path and search_path.downcase.include? "/pods/"
                # support include a defined string header
                header_target_name = get_downcase_legal_bazel_target_name(search_path + "_recursive_headers")
                header_target_info = KeyValueStore.get_key_value_store_in_container(target_info_hash_for_bazel, header_target_name)
                header_target_info["rule"] = "cc_header"
                header_target_info["hdrs_dir"] = search_path
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
    
                    user_module_hash[user_module][:module_deps].each do | module_dep |
                        add_file_deps(module_dep, target_info, target_info_hash_for_bazel, target_info_hash_for_xcode, user_module_hash, info_hash, file_deps_set)
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
            dtrace_header_map_target_name = dep_info[2] + "_dtrace_header_map"
            key = "header_maps"
            key = "objc_" + key if target_info["rule"] == "swift_library"
            target_info[key] = Set.new unless target_info[key]
            target_info[key].add dtrace_header_map_target_name
            return
        end

        binding.pry
    end

    def get_bazel_target_name_for_library_import(library_path)
        return "import_" + get_downcase_legal_bazel_target_name(File.basename(library_path))
    end

    def get_bazel_target_name_for_framework_import(framework_path)
        return "import_" + get_downcase_legal_bazel_target_name(File.basename(framework_path))
    end

    def get_bazel_target_name_for_swift_module_name(swift_module_name)
        return "swift_module_" + swift_module_name
    end

    def get_bazel_target_name_for_xcode_target_name(target_name)
        return get_legal_bazel_target_name(target_name)
    end

    def get_bazel_target_name_for_xcode_target_name_and_extname_and_index_and_count(target_name, extname, index, count)
        suffix = ""
        if count > 1
            suffix = "_" + index.to_s
        end
        return get_legal_bazel_target_name(target_name + extname + suffix)
    end

    def get_bazel_target_name_for_swift_header_map(module_name)
        return module_name + "_swift_header_map"
    end

    def get_bazel_target_name_for_header_map(target_name, is_public)
        if is_public
            return get_downcase_legal_bazel_target_name(target_name) + "_public_header_map"
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
        return get_downcase_legal_bazel_target_name(path + "_header")
    end

    def get_legal_bazel_target_name(name)
        name = DynamicConfig.filter_content(name)
        return name.gsub(/\W/, "_")
    end

    def get_downcase_legal_bazel_target_name(name)
        return get_legal_bazel_target_name(name).downcase
    end

end