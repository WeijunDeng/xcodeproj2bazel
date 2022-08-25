
def static_library(
    name = None, 
    deps = [],
    alwayslink = False,
    ):
    native.objc_library(
        name = name, 
        deps = deps,
        alwayslink = alwayslink,
    )
