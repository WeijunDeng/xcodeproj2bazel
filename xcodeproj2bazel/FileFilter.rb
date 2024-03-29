require 'open3'
require 'set'
require 'find'
require 'json'

class FileFilter

    @@xcode_developer_headers_set = Set.new
    @@xcode_developer_name_framework_hash = {}
    @@xcode_developer_name_library_hash = {}
    @@xcode_default_iphoneos_deployment_target = nil

    def self.load_xcode_developer_path
        xcode_developer_path_result = Open3.capture3("xcode-select -p")
        xcode_developer_path = xcode_developer_path_result[0].strip
        unless xcode_developer_path_result[2] == 0 and xcode_developer_path.size > 0
            raise "unexpected #{xcode_developer_path_result}"
        end
        @@xcode_developer_headers_set.merge Dir.glob("#{xcode_developer_path}/Toolchains/XcodeDefault.xctoolchain/usr/lib/clang/*/include/*").map{|e|File.basename(e).downcase}
        @@xcode_developer_headers_set.merge Dir.glob("#{xcode_developer_path}/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS.sdk/usr/include/*").map{|e|File.basename(e).downcase}
        @@xcode_developer_headers_set.merge Dir.glob("#{xcode_developer_path}/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS.sdk/usr/include/*/*").map{|e|e.split("/")[-2..-1].join("/").downcase}
        @@xcode_developer_headers_set.merge Dir.glob("#{xcode_developer_path}/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS.sdk/System/Library/Frameworks/*.framework/Headers/*").map{|e|e.split("/")[-3..-1].join("/").downcase.sub(".framework/headers", "")}
        (Dir.glob("#{xcode_developer_path}/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS.sdk/System/Library/Frameworks/*.framework") + Dir.glob("#{xcode_developer_path}/Platforms/iPhoneOS.platform/Developer/Library/Frameworks/*.framework")).each do | path |
            framework = File.basename(path)
            name = framework.split(File.extname(framework))[0].downcase
            @@xcode_developer_name_framework_hash[name] = framework
        end
        Dir.glob("#{xcode_developer_path}/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS.sdk/usr/lib/lib*.tbd").each do | path |
            library = File.basename(path)
            name = library.split(File.extname(library))[0].downcase[3..-1]
            @@xcode_developer_name_library_hash[name] = library
        end
        @@xcode_developer_name_library_hash["stdc++"] = "libstdc++.tbd"


        sdksettings_json_file = "#{xcode_developer_path}/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS.sdk/SDKSettings.json"
        if File.exist? sdksettings_json_file
            json_object = JSON.parse(File.read(sdksettings_json_file))
            @@xcode_default_iphoneos_deployment_target = json_object["DefaultProperties"]["IPHONEOS_DEPLOYMENT_TARGET"] if json_object["DefaultProperties"]
        end
    end

    def self.get_default_iphoneos_deployment_target
        return @@xcode_default_iphoneos_deployment_target
    end

    def self.is_system_header(import_file_path, is_angled_import)
        if is_angled_import or import_file_path.include? "/"
            if @@xcode_developer_headers_set.include? import_file_path.downcase
                return true
            end
        end
        return false
    end

    def self.get_system_framework_by_name(name)
        return @@xcode_developer_name_framework_hash[name.downcase]
    end

    def self.get_system_library_by_name(name)
        return @@xcode_developer_name_library_hash[name.downcase]
    end

    def self.get_full_path(origin_path)
        path = $xcodeproj2bazel_pwd + "/" + origin_path
        return path
    end

    def self.get_short_path(origin_path)
        if origin_path and origin_path.downcase.start_with? $xcodeproj2bazel_pwd.downcase + "/"
            return origin_path[$xcodeproj2bazel_pwd.size+1..-1]
        end
        return origin_path
    end

    def self.get_real_exist_expand_path_file(origin_path)
        path = get_exist_expand_path_file(origin_path)
        if path
            path = File.realpath path
            binding.pry unless path.downcase.start_with? $xcodeproj2bazel_pwd.downcase + "/"
        end
        return path
    end


    def self.get_exist_expand_path_file(origin_path)
        path = get_exist_expand_path(origin_path)
        if path
            unless File.file? path
                binding.pry
                path = nil
            end
        end
        return path
    end

    def self.get_exist_expand_path_dir(origin_path)
        path = get_exist_expand_path(origin_path)
        if path
            if File.file? path
                binding.pry
                path = nil
            end
        end
        return path
    end

    @@expand_path_downcase_hash = {}
    def self.get_exist_expand_path(origin_path)
        unless origin_path
            return nil
        end
        unless origin_path.size > 0
            return nil
        end
        path = origin_path
        unless File.exist? path
            fix_path = $xcodeproj2bazel_pwd + "/" + path
            if File.exist? fix_path
                fix_path = File.expand_path(fix_path)
                if fix_path.start_with? $xcodeproj2bazel_pwd + "/"
                    path = fix_path
                end
            end
            unless File.exist? path
                return nil
            end
        end
        path = File.expand_path(path)
        if @@expand_path_downcase_hash[path.downcase]
            path = @@expand_path_downcase_hash[path.downcase]
        else
            @@expand_path_downcase_hash[path.downcase] = path
        end
        return path
    end

    @@recursive_dirs_hash = {}
    def self.get_recursive_dirs(path)
        path = get_exist_expand_path_dir(path)
        dirs = @@recursive_dirs_hash[path]
        unless dirs
            dirs = []
            # export EXCLUDED_RECURSIVE_SEARCH_PATH_SUBDIRECTORIES\=\*.nib\ \*.lproj\ \*.framework\ \*.gch\ \*.xcode\*\ \*.xcassets\ \(\*\)\ .DS_Store\ CVS\ .svn\ .git\ .hg\ \*.pbproj\ \*.pbxproj
            exclude_patten = /(\.nib($|\/))|(\.lproj($|\/))|(\.framework($|\/))|(\.gch($|\/))|(\.xcode($|\/))|(\.xcassets($|\/))|(\.svn($|\/))|(\.git($|\/))|(\.hg($|\/))|(\.pbproj($|\/))|(\.pbxproj($|\/))/
            Find.find(path).each{|e| dirs.push e if not File.file? e and not e.match exclude_patten}
            @@recursive_dirs_hash[path] = dirs
        end
        return dirs
    end

    @@xcframework_path_info_hash = {}
    def self.get_match_xcframework_info(xcframework_path)
        return nil unless xcframework_path
        origin_xcframework_path = xcframework_path
        hash = @@xcframework_path_info_hash[origin_xcframework_path]
        return hash if hash
        binding.pry unless File.exist? xcframework_path
        xcframework_path = get_exist_expand_path_dir xcframework_path
        binding.pry unless File.exist? xcframework_path
        info_plist_path = xcframework_path + "/Info.plist"
        binding.pry unless File.exist? info_plist_path
        convert_result = Open3.capture3("plutil -convert json \"#{info_plist_path}\" -o -")
        binding.pry unless convert_result[2] == 0
        json_content = convert_result[0]
        json_object = JSON.parse(json_content)
        binding.pry unless json_object and json_object["AvailableLibraries"]
        match_libraries = []
        json_object["AvailableLibraries"].each do | x |
            next unless x["SupportedPlatform"] == DynamicConfig.get_build_platform
            next if DynamicConfig.get_build_platform_variant.size > 0 and x["SupportedPlatformVariant"] != DynamicConfig.get_build_platform_variant
            next if DynamicConfig.get_build_arch.size > 0 and not x["SupportedArchitectures"].include? DynamicConfig.get_build_arch
            match_libraries.push x
        end
        binding.pry unless match_libraries.size == 1
        binding.pry unless match_libraries[0]["LibraryIdentifier"]
        binding.pry unless match_libraries[0]["LibraryPath"]

        path = xcframework_path + "/" + match_libraries[0]["LibraryIdentifier"]
        hash = {}
        if match_libraries[0]["LibraryPath"]
            hash[:LibraryPath] = path + "/" + match_libraries[0]["LibraryPath"]
            binding.pry unless File.exist? hash[:LibraryPath]
        end
        if match_libraries[0]["HeadersPath"]
            hash[:HeadersPath] = path + "/" + match_libraries[0]["HeadersPath"]
            binding.pry unless File.exist? hash[:HeadersPath]
        end
        @@xcframework_path_info_hash[origin_xcframework_path] = hash
        return hash
    end

    def self.get_source_file_extnames_all
        return get_source_file_extnames_swift + 
        get_source_file_extnames_cpp + 
        get_source_file_extnames_objective_c + 
        get_source_file_extnames_objective_cpp + 
        get_source_file_extnames_c + 
        get_source_file_extnames_d
    end

    def self.get_source_file_extnames_c_type
        return get_source_file_extnames_cpp + 
        get_source_file_extnames_objective_c + 
        get_source_file_extnames_objective_cpp + 
        get_source_file_extnames_c
    end


    def self.get_source_file_extnames_mixed_objective_c
        return get_source_file_extnames_objective_c + get_source_file_extnames_objective_cpp
    end

    def self.get_source_file_extnames_mixed_cpp
        return get_source_file_extnames_objective_cpp + get_source_file_extnames_cpp
    end

    def self.get_source_file_extnames_mixed_c
        return get_source_file_extnames_objective_c + get_source_file_extnames_c
    end

    def self.get_source_file_extnames_swift
        return [".swift"]
    end

    def self.get_source_file_extnames_cpp
        return [".cc", ".cpp"]
    end

    def self.get_source_file_extnames_objective_c
        return [".m"]
    end

    def self.get_source_file_extnames_objective_cpp
        return [".mm"]
    end

    def self.get_source_file_extnames_c
        return [".c", ".s", ".S"]
    end

    def self.get_source_file_extnames_d
        # https://github.com/bazelbuild/rules_apple/blob/master/doc/rules-dtrace.md
        return [".d"]
    end

    def self.get_header_file_extnames
        return [".h", ".hxx", ".pch", ".hh", ".hpp", ".inc"]
    end

end