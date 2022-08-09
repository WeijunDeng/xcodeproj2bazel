class BazelFormatter
    def get_prefix_lines
        lines = []
        
        lines.push 'load("xcodeproj2bazel_rules/cc_header.bzl", "cc_header")'
        lines.push 'load("xcodeproj2bazel_rules/cc_library.bzl", "cc_library")'
        lines.push 'load("xcodeproj2bazel_rules/objc_library.bzl", "objc_library")'
        lines.push 'load("xcodeproj2bazel_rules/metal_library.bzl", "metal_library")'
        lines.push 'load("xcodeproj2bazel_rules/static_library.bzl", "static_library")'
        lines.push 'load("xcodeproj2bazel_rules/system_library.bzl", "system_library")'
        lines.push 'load("xcodeproj2bazel_rules/swift_library.bzl", "swift_library")'
        lines.push 'load("xcodeproj2bazel_rules/module_map.bzl", "module_map")'
        lines.push 'load("xcodeproj2bazel_rules/hmap.bzl", "header_map")'
        
        lines.push 'load("@build_bazel_rules_apple//apple:ios.bzl", "ios_application", "ios_extension", "ios_unit_test")'
        lines.push 'load("@build_bazel_rules_apple//apple:ios.bzl", "ios_framework", "ios_static_framework")'
        lines.push 'load("@build_bazel_rules_apple//apple:apple.bzl", "apple_static_framework_import", "apple_dynamic_framework_import")'
        lines.push 'load("@build_bazel_rules_apple//apple:apple.bzl", "apple_static_xcframework_import", "apple_dynamic_xcframework_import")'
        lines.push 'load("@build_bazel_rules_apple//apple:dtrace.bzl", "dtrace_compile")'
        lines.push 'load("@build_bazel_rules_apple//apple:versioning.bzl", "apple_bundle_version")'
        lines.push 'load("@build_bazel_rules_apple//apple:resources.bzl", "apple_resource_bundle", "apple_resource_group", "apple_bundle_import")'
        
        lines = lines.sort

        lines.push 'package(default_visibility = ["//visibility:public"])'
        return lines
    end

    def format(target_info_hash_for_bazel)
        lines = []
        target_info_hash_for_bazel.keys.each do | target_name |
            unless target_info_hash_for_bazel[target_name]["rule"]
                target_info_hash_for_bazel.delete(target_name)
            end
        end
        target_names = target_info_hash_for_bazel.keys.sort_by{|target_name| target_info_hash_for_bazel[target_name]["rule"] + " " + target_name }
        target_names.each do | target_name |
            hash = target_info_hash_for_bazel[target_name]
            lines.push "#{hash["rule"]}("
            lines.push "    name = \"#{target_name}\","
    
            hash.keys.sort.each do | key |
                next if key == "rule"
                next if key == "name"
                next if hash[key].size == 0
                if hash[key] == "True" or hash[key] == "False" or key == "families"
                    lines.push "    #{key} = #{hash[key]},"
                elsif hash["rule"] == "genrule" and ["srcs", "outs"].include? key
                    lines.push "    #{key} = [\n#{hash[key].sort.uniq.map{|e| "        \"#{e}\",\n"}.join("")}    ]," if hash[key].size > 0
                elsif key == "resources"
                    xcassets = hash[key].select{|e| e.end_with? ".xcassets"}
                    xcassets_excludes = xcassets.map{|e|"#{e}/*.appiconset/**"}
                    other_files = hash[key] - xcassets
                    other_files_pattern = ""
                    if other_files.size > 0
                        other_files_pattern = "[\n#{other_files.sort.uniq.map{|e| "        \"#{e}\",\n"}.join("")}    ]"
                    end
                    xcassets_pattern = ""
                    if xcassets.size > 0 and xcassets_excludes.size > 0
                        xcassets_pattern = "glob([\n#{xcassets.sort.uniq.map{|e| "        \"#{e}/**\",\n"}.join("")}    ], exclude=[\n#{xcassets_excludes.sort.map{|e| "        \"#{e}\",\n"}.join("")}    ])"
                    elsif xcassets.size > 0
                        xcassets_pattern = "glob([\n#{xcassets.sort.uniq.map{|e| "        \"#{e}/**\",\n"}.join("")}    ])"
                    end
                    if other_files_pattern.size > 0 and xcassets_pattern.size > 0
                        other_files_pattern = other_files_pattern + " + "
                    end
                    lines.push "    #{key} = #{other_files_pattern}#{xcassets_pattern},"
                elsif key == "strings" or key == "infoplists"
                    lines.push "    #{key} = [\n#{hash[key].sort.uniq.map{|e| "        \"#{e}\",\n"}.join("")}    ]," if hash[key].size > 0
                elsif key == "app_icons"
                    lines.push "    #{key} = glob([\n#{hash[key].sort.uniq.map{|e| "        \"#{e}\",\n"}.join("")}    ])," if hash[key].size > 0
                elsif hash[key] and (hash[key].class == Set or hash[key].class == Array) and hash[key].size == 1 and hash[key][0].start_with? ":"
                    lines.push "    #{key} = #{hash[key].to_s},"
                elsif ["hdrs", "srcs", "non_arc_srcs"].include? key
                    if hash[key] and hash[key].size > 0
                        src_files = hash[key]
                        src_pattern = "[\n#{src_files.sort.map{|file| "        \"#{file}\",\n"}.join("")}    ],"
                        lines.push "    #{key} = #{src_pattern}" if src_pattern
                    end
                elsif key == "deps" or key == "frameworks" or key == "extensions" or key.end_with? "header_maps" or key.end_with? "module_maps" or key == "swiftc_inputs"
                    lines.push "    #{key} = [\n#{hash[key].uniq.map{|e| "        \":#{e}\",\n"}.join("")}    ]," if hash[key].size > 0
                elsif key == "framework_imports" or key == "xcframework_imports"
                    lines.push "    #{key} = glob([\"#{hash[key]}/**\"]),"
                elsif key == "archives" or key == "bundle_imports"
                    lines.push "    #{key} = [\"#{hash[key]}\"],"
                elsif key == "includes"
                    lines.push "    #{key} = [\n#{hash[key].map{|e|"        \"#{e}\",\n"}.join("")}    ],"
                elsif hash[key].class == Set.new
                    lines.push "    #{key} = [\n#{hash[key].sort.map{|e|"        \"#{e}\",\n"}.join("")}    ],"
                elsif hash[key].class == Array
                    lines.push "    #{key} = [\n#{hash[key].uniq.map{|e|"        \"#{e}\",\n"}.join("")}    ],"
                else
                    lines.push "    #{key} = \"#{hash[key]}\","
                end
            end
    
            lines.push ")"
        end

        bazel_build_content = (get_prefix_lines + lines).join("\n") + "\n"
        bazel_build_content = DynamicConfig.filter_content(bazel_build_content)
        output_build_file = FileFilter.get_full_path("BUILD.bazel")
        unless File.exist? output_build_file and File.read(output_build_file) == bazel_build_content
            File.write(output_build_file, bazel_build_content)
        end
        system "cp -rf WORKSPACE \"#{$xcodeproj2bazel_pwd}\""
        system "cp -rf xcodeproj2bazel_rules \"#{$xcodeproj2bazel_pwd}\""
        system "cp -rf .bazelrc \"#{$xcodeproj2bazel_pwd}\""
        system "cp -rf .bazelversion \"#{$xcodeproj2bazel_pwd}\""
        system "chmod 777 \"#{$xcodeproj2bazel_pwd}/xcodeproj2bazel_rules/modify_module_map.sh\""
    end
end


