
def cc_library(
        pch = None, 
        copts = [], 
        hdrs = [], 
        deps = [], 
        includes = [], 
        framework_search_paths = [],
        header_maps = [],
        **kwargs):

    new_deps = []
    new_deps += header_maps

    new_hdrs = []
    new_copts = []

    if pch:
        new_hdrs.append(pch)
        new_copts.append("-include '%s'" % pch)
    
    for include in includes:
        new_copts += ["-I%s" % include]
    for header_map in header_maps:
        new_copts += ["-I$(location %s)" % header_map]
    if len(header_maps) > 0:
        new_copts += ["-I."]
    for framework_search_path in framework_search_paths:
        new_copts += ["-F%s" % framework_search_path]

    native.cc_library(
        copts = copts + new_copts,
        deps = deps + new_deps,
        hdrs = hdrs + new_hdrs,
        **kwargs)