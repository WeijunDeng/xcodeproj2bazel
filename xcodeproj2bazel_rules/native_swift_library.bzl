load("@build_bazel_rules_swift//swift:swift.bzl", "swift_library")

def native_swift_library(**kwargs):
    swift_library(**kwargs)
