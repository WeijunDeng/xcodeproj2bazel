require 'open3'
require 'set'
require 'find'

class FileFilter

    @@xcode_developer_headers_set = Set.new
    @@xcode_developer_name_framework_hash = {}
    @@xcode_developer_name_library_hash = {}

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
        Dir.glob("#{xcode_developer_path}/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS.sdk/System/Library/Frameworks/*.framework").each do | path |
            framework = File.basename(path)
            name = framework.split(File.extname(framework))[0].downcase
            @@xcode_developer_name_framework_hash[name] = framework
        end
        Dir.glob("#{$xcode_developer_path}/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS.sdk/usr/lib/lib*.tbd").each do | path |
            library = File.basename(path)
            name = framework.split(File.extname(framework))[0].downcase[3..-1]
            @@xcode_developer_name_library_hash[name] = library
        end
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

    @@expand_path_downcase_hash = {}
    def self.get_exist_expand_path(origin_path)
        unless origin_path
            return nil
        end
        unless origin_path.size > 0
            return nil
        end
        path = origin_path
        unless origin_path.downcase.start_with? File.dirname($xcodeproj2bazel_pwd).downcase
            path = $xcodeproj2bazel_pwd + "/" + origin_path
        end
        unless File.exist? path
            return nil
        end
        path = File.expand_path(path)
        unless path.downcase.start_with? $xcodeproj2bazel_pwd.downcase + "/" or path.downcase == $xcodeproj2bazel_pwd.downcase
            binding.pry
            return nil
        end
        if @@expand_path_downcase_hash[path.downcase]
            path = @@expand_path_downcase_hash[path.downcase]
        else
            @@expand_path_downcase_hash[path.downcase] = path
        end
        return path
    end

    @@recursive_dirs_hash = {}
    def self.get_recursive_dirs(path)
        path = get_exist_expand_path(path)
        dirs = @@recursive_dirs_hash[path]
        unless dirs
            dirs = []
            Find.find(path).each{|e| dirs.push e if not File.file? e}
            @@recursive_dirs_hash[path] = dirs
        end
        return dirs
    end

    def self.get_source_file_extnames_without_swift
        return [".cc", ".c", ".m", ".mm", ".s", ".cpp"]
    end

    def self.get_source_file_extnames
        return [".cc", ".c", ".m", ".mm", ".s", ".cpp", ".swift"]
    end

    def self.get_swift_source_file_extnames
        return [".swift"]
    end

    def self.get_objc_source_file_extnames
        return [".m", ".mm"]
    end

    def self.get_cpp_source_file_extnames
        return [".mm", ".cc", ".cpp"]
    end

    def self.get_pure_objc_source_file_extnames
        return [".m"]
    end

    def self.get_c_source_file_extnames
        return [".m", ".c"]
    end

    def self.get_header_file_extnames
        return [".h", ".hxx", ".pch", ".hh"]
    end

end