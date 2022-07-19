def static_library(
    name = None, 
    deps = [], 
    linkopts = []):
    native.objc_library(
        name = name, 
        deps = deps, 
        linkopts = linkopts
    )
