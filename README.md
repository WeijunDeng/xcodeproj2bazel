# xcodeproj2bazel

Automatically parse xcode projects and build with Bazel, then you can choose Bazel or Xcode as you like.

# Usage

```
git clone https://github.com/WeijunDeng/xcodeproj2bazel.git
cd xcodeproj2bazel
bash xcodeproj2bazel.sh --pwd=<path_of_your_working_repo> --workspace=<your_xcworkspace_path>
cd <path_of_your_working_repo>
# then <path_of_your_working_repo>/BUILD.bazel will exist.
bazel build <your_app>
```

if you use xcodeproj instead of xcworkspace
```
bash xcodeproj2bazel.sh --pwd=<path_of_your_working_repo> --project=<your_xcodeproj_path>
```

if you want to hook , or just change provisioning profile
```
cp xcodeproj2bazel/DynamicConfig.rb <your_dynamic_config_path>
# hook in <your_dynamic_config_path>
bash xcodeproj2bazel.sh --pwd=<path_of_your_working_repo> --workspace=<your_xcworkspace_path> --config=<your_dynamic_config_path>
```

# Test

```
bash test.sh
```

# Feature

- Support mixed objc and swift
- Support header map
- Support module map
- Support compile file extname
    - .c
    - .cc
    - .cpp
    - .d
    - .h
    - .hh
    - .hpp
    - .hxx
    - .inc
    - .m
    - .mm
    - .pch
    - .pch
    - .s
    - .swift
- Support .bundle, .xib, .storyboard, .metal, .xcassets, .appiconset and more
- Support import header dependency simulation
- Support objc modules
- Support objc modules cache with sandbox
- Support objc auto link framework
- Support auto remove absolute path
- Support CMake/Cocoapods generated project
- Support static library, static framework and dynamic framework
- Support iOS app and extension
- Support major xcode build settings
    - ASSETCATALOG_COMPILER_APPICON_NAME
    - ATTRIBUTES
    - CLANG_CXX_LANGUAGE_STANDARD
    - CLANG_CXX_LIBRARY
    - CLANG_ENABLE_OBJC_ARC
    - COMPILER_FLAGS
    - CONFIGURATION
    - CURRENT_PROJECT_VERSION
    - DEAD_CODE_STRIPPING
    - DEFINES_MODULE
    - EFFECTIVE_PLATFORM_NAME
    - FRAMEWORK_SEARCH_PATHS
    - GCC_C_LANGUAGE_STANDARD
    - GCC_PREFIX_HEADER
    - GCC_PREPROCESSOR_DEFINITIONS
    - HEADER_SEARCH_PATHS
    - INFOPLIST_FILE
    - IPHONEOS_DEPLOYMENT_TARGET
    - LIBRARY_SEARCH_PATHS
    - MACH_O_TYPE
    - MODULEMAP_FILE
    - OTHER_CFLAGS
    - OTHER_CPLUSPLUSFLAGS
    - OTHER_LDFLAGS
    - OTHER_SWIFT_FLAGS
    - PRODUCT_BUNDLE_IDENTIFIER
    - PRODUCT_MODULE_NAME
    - PRODUCT_NAME
    - PROJECT_DIR
    - PROVISIONING_PROFILE_SPECIFIER
    - SRCROOT
    - SWIFT_ACTIVE_COMPILATION_CONDITIONS
    - SWIFT_OBJC_BRIDGING_HEADER
    - TARGET_NAME
    - TARGETED_DEVICE_FAMILY
    - USE_HEADERMAP
    - USER_HEADER_SEARCH_PATHS
    - WARNING_CFLAGS

# Todo

Too much ...

Doing or Planning:

- incremental run script
- use for dependency detect and isolate
- parse file with defined macro
- use tulsi to generate a xcode project, building with bazel, indexing with xcode
- support more xcode build settings such as GENERATE_INFOPLIST_FILE
- read iOS default template build settings to parse
- test for xcode 14 (xcode 13 now)
- more examples
- support xcframework


