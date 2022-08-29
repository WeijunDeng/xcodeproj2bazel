#!/usr/bin/env ruby

require 'xcodeproj'
require 'set'
require 'open3'
require 'yaml'
require 'digest'
require 'find'
require 'pry'
require "./xcodeproj2bazel/XcodeprojParser.rb"
require "./xcodeproj2bazel/DependencyAnalyzer.rb"
require "./xcodeproj2bazel/BazelTranslator.rb"
require "./xcodeproj2bazel/BazelFormatter.rb"
require "./xcodeproj2bazel/KeyValueStore.rb"
require "./xcodeproj2bazel/FileFilter.rb"

$xcodeproj2bazel_pwd = nil

class Xcodeproj2Bazel
    def get_argument(key)
        a = ARGV.detect{|x|x.start_with? key}
        a = a.sub(key, "") if a
        return a
    end

    def main
        $xcodeproj2bazel_pwd = get_argument("--pwd=")
        raise "please set --pwd=/full/path" unless $xcodeproj2bazel_pwd 
        if File.exist? $xcodeproj2bazel_pwd
            $xcodeproj2bazel_pwd = File.realpath(File.expand_path($xcodeproj2bazel_pwd))
        else
            raise "#{$xcodeproj2bazel_pwd} should exist"
        end
        workspace_path = get_argument("--workspace=")
        project_path = get_argument("--project=")
        raise "please set --workspace=/full/path/xxx.xcworkspace or --project=/full/path/xxx.xcodeproj" unless workspace_path or project_path
        if workspace_path and project_path
            raise "workspace and project should not set both"
        end
        if workspace_path
            if File.exist? workspace_path
                puts workspace_path
                workspace_path = File.realpath(File.expand_path(workspace_path))
            else
                raise "#{workspace_path} should exist"
            end
        end
        if project_path
            if File.exist? project_path
                puts project_path
                project_path = File.realpath(File.expand_path(project_path))
            else
                raise "#{project_path} should exist"
            end
        end
        config_path = get_argument("--config=")
        if config_path
            if File.exist? config_path
                config_path = File.realpath(File.expand_path(config_path))
                puts config_path
                require config_path
            else
                raise "#{config_path} should exist"
            end
        else
            require './xcodeproj2bazel/DynamicConfig.rb'
        end

        start_time = Time.now

        puts DynamicConfig.get_build_configuration_name
        
        FileFilter.load_xcode_developer_path
        puts "duration after load_xcode_developer_path : #{(Time.now - start_time).to_f} s"
        target_info_hash_for_xcode = XcodeprojParser.new.parse_xcodeproj(workspace_path, project_path)
        puts "duration after XcodeprojParser : #{(Time.now - start_time).to_f} s"
        analyze_result = DependencyAnalyzer.new.analyze(target_info_hash_for_xcode)
        puts "duration after DependencyAnalyzer : #{(Time.now - start_time).to_f} s"
        target_info_hash_for_bazel = BazelTranslator.new.translate(target_info_hash_for_xcode, analyze_result)
        puts "duration after BazelTranslator : #{(Time.now - start_time).to_f} s"
        target_info_hash_for_bazel = DynamicConfig.hook_target_info_hash_for_bazel(target_info_hash_for_bazel)
        puts "duration after hook_target_info_hash_for_bazel : #{(Time.now - start_time).to_f} s"
        BazelFormatter.new.format(target_info_hash_for_bazel)
        puts "duration after BazelFormatter : #{(Time.now - start_time).to_f} s"
        
    end
end

if __FILE__ == $0
    Xcodeproj2Bazel.new.main
end