load("xcodeproj2bazel_rules/native_swift_library.bzl", "native_swift_library")

def swift_library(
        objc_module_maps = [],
        objc_header_maps = [],
        objc_includes = [],
        objc_defines = [],
        copts = [],
        private_deps = [],
        swiftc_inputs = [],
        module_name = None,
        objc_bridging_header = None, 
        **kwargs):

    new_swiftc_inputs = []
    new_swiftc_inputs += objc_module_maps
    new_swiftc_inputs += objc_header_maps

    new_deps = []

    new_copts = []
    for define in objc_defines:
        new_copts += ["-Xcc", "-D%s" % define]
    for include in objc_includes:
        new_copts += ["-Xcc", "-I%s" % include]
    for module_map in objc_module_maps:
        new_copts += ["-Xcc", "-fmodule-map-file=$(location %s)" % module_map]
        new_deps += [module_map + "_headers"]
    for header_map in objc_header_maps:
        new_copts += ["-Xcc", "-I$(location %s)" % header_map]
        new_deps += [header_map + "_headers"]
    if len(objc_header_maps) > 0:
        new_copts += ["-Xcc", "-I."]
    if objc_bridging_header:
        new_copts += ["-import-objc-header", objc_bridging_header]
        if not objc_bridging_header in swiftc_inputs:
            new_swiftc_inputs += [objc_bridging_header]

    generated_header_name = None
    generates_header = False
    if module_name:
        generated_header_name = "%s-Swift.h" % module_name
        generates_header = True
    native_swift_library(
        copts = copts + new_copts,
        private_deps = private_deps + new_deps,
        swiftc_inputs = swiftc_inputs + new_swiftc_inputs,
        generated_header_name = generated_header_name,
        generates_header = generates_header,
        module_name = module_name,
        features = ["swift.no_generated_module_map", "swift.use_pch_output_dir"],
        **kwargs)