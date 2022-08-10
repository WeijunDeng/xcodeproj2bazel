
def static_library(
    name = None, 
    deps = [],
    ):
    native.objc_library(
        name = name, 
        deps = deps,
    )
