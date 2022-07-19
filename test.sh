#!/usr/bin/env bash

set -e
set -x

bash xcodeproj2bazel.sh --pwd=examples/empty_app_storyboard_objc --project=examples/empty_app_storyboard_objc/empty_app_storyboard_objc.xcodeproj
pushd examples/empty_app_storyboard_objc
bazel build empty_app_storyboard_objc_app
popd

bash xcodeproj2bazel.sh --pwd=examples/empty_app_storyboard_swift --project=examples/empty_app_storyboard_swift/empty_app_storyboard_swift.xcodeproj
pushd examples/empty_app_storyboard_swift
bazel build empty_app_storyboard_swift_app
popd

# TODO: support GENERATE_INFOPLIST_FILE
# bash xcodeproj2bazel.sh --pwd=examples/empty_app_swiftui --project=examples/empty_app_swiftui/empty_app_swiftui.xcodeproj
# pushd examples/empty_app_swiftui
# bazel build empty_app_swiftui_app
# popd
