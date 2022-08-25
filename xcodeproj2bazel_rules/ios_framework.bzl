load("xcodeproj2bazel_rules/ios_dynamic_framework.bzl", "ios_dynamic_framework")
load("@bazel_skylib//lib:paths.bzl", "paths")

def ios_framework(
        not_avoid_deps = [],
        linkopts = [],
        additional_linker_inputs = [],
        **kwargs):

    new_linkopts = []
    new_additional_linker_inputs = []

    for not_avoid_dep in not_avoid_deps:
        # fix because ios_framework rule avoid deps in https://github.com/bazelbuild/rules_apple/blob/8f6485fe22977adefff996391daa212f0b3bbc7f/apple/internal/ios_rules.bzl#L180
        new_additional_linker_inputs.append(not_avoid_dep)
        if not_avoid_dep.endswith(".a") or paths.dirname(not_avoid_dep).endswith(".framework"):
            new_linkopts.append(not_avoid_dep)
        else:
            new_linkopts.append("$(location %s)" % not_avoid_dep)

    ios_dynamic_framework(
        linkopts = linkopts + new_linkopts,
        additional_linker_inputs = additional_linker_inputs + new_additional_linker_inputs,
        **kwargs)