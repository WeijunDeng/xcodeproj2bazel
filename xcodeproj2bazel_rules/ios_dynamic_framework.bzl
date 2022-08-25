load("@build_bazel_rules_apple//apple:ios.bzl", "ios_framework")

def ios_dynamic_framework(**kwargs):
    ios_framework(**kwargs)