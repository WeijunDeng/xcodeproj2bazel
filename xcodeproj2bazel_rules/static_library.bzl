
def static_library(
    name = None, 
    deps = [],
    swift_deps = [],
    minimum_os_version = None,
    linkopts = []
    ):
    apple_static_library_name = name + ".apple_static_library"
    native.apple_static_library(
        name = apple_static_library_name,
        deps = deps,
        linkopts = linkopts,
        minimum_os_version = minimum_os_version,
        platform_type = str(apple_common.platform_type.ios),
    )
    objc_import_name = name + ".objc_import"
    native.objc_import(
        name = objc_import_name,
        archives = [apple_static_library_name]
    )
    native.objc_library(
        name = name, 
        deps = [objc_import_name] + swift_deps,
    )
