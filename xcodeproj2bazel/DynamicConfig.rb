class DynamicConfig
    def self.get_build_configuration_name
        env_config = ENV["CONFIGURATION"]
        if env_config and env_config.size > 0
            return env_config
        end
        
        return "Debug"
    end

    def self.get_build_arch
        return "x86_64" # arm64
    end

    def self.get_build_sdk
        return "iphonesimulator" # iphoneos # macosx
    end

    def self.get_build_sdk_version
        return "15.0"
    end

    def self.get_build_effective_platform_name
        return "-" + get_build_sdk
    end

    def self.get_build_platform
        return "ios"
    end

    def self.get_build_platform_variant
        return "simulator"
    end

    def self.get_build_settings_condition
        # https://developer.apple.com/documentation/xcode/adding-a-build-configuration-file-to-your-project?changes=l_3
        hash = {}
        hash["sdk"] = "#{get_build_sdk}#{get_build_sdk_version}"
        hash["arch"] = get_build_arch
        hash["config"] = get_build_configuration_name
        return hash
    end

    def self.filter_content(content)
        content = content.gsub(/#{$xcodeproj2bazel_pwd + "/"}/i, "").gsub(/#{$xcodeproj2bazel_pwd}/i, ".")
        
        return content
    end

    def self.hook_target_info_hash_for_bazel(target_info_hash_for_bazel)

        target_info_hash_for_bazel.sort.each do | target_name, hash |
            hash.delete("provisioning_profile")
            # hash["XXX Development Profile"] = "xxx/XXX_Development_Profile.mobileprovision"
        end

        return target_info_hash_for_bazel
    end

end
