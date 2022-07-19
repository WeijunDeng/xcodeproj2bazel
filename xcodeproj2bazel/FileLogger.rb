class FileLogger
    @@xcodeproj2bazel_logs = []
    def self.add_verbose_log(log)
        @@xcodeproj2bazel_logs.push log
    end

    def self.write
        if @@xcodeproj2bazel_logs.size > 0
            File.write("xcodeproj2bazel.log", @@xcodeproj2bazel_logs.join("\n"))
        end
    end
end