def system_library(
        name = None, 
        sdk_dylibs = [], 
        sdk_frameworks = [], 
        weak_sdk_frameworks = []):
    native.objc_library(
        name = name, 
        sdk_dylibs = sdk_dylibs, 
        sdk_frameworks = sdk_frameworks, 
        weak_sdk_frameworks = weak_sdk_frameworks
    )
