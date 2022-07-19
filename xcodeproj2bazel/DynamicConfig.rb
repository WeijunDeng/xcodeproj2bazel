class DynamicConfig
    def self.get_build_configuration_name
        env_config = ENV["CONFIGURATION"]
        if env_config and env_config.size > 0
            return env_config
        end
        
        return "Debug"
    end

    def self.filter_content(content)
        content = content.gsub($xcodeproj2bazel_pwd + "/", "").gsub($xcodeproj2bazel_pwd, ".")
        
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
