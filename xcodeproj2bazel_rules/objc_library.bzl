
def objc_library(
        module_maps = [],
        header_maps = [],
        includes = [],
        copts = [],
        deps = [],
        enable_modules = False,
        **kwargs):

    new_deps = []
    new_deps += module_maps
    new_deps += header_maps

    new_copts = []

    for module_map in module_maps:
        new_copts += ["-F$(GENDIR)/%s" % module_map.replace(":", "")]
    for include in includes:
        new_copts += ["-I%s" % include]
    for header_map in header_maps:
        new_copts += ["-I$(location %s)" % header_map]
    if len(header_maps) > 0:
        new_copts += ["-I."]

    native.objc_library(
        copts = copts + new_copts,
        deps = deps + new_deps,
        enable_modules = enable_modules,
        **kwargs)