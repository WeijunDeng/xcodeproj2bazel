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

pushd examples/swift_app_with_pod_no_use_frameworks
pod update
popd
bash xcodeproj2bazel.sh --pwd=examples/swift_app_with_pod_no_use_frameworks --workspace=examples/swift_app_with_pod_no_use_frameworks/swift_app_with_pod_no_use_frameworks.xcworkspace
pushd examples/swift_app_with_pod_no_use_frameworks
bazel build swift_app_with_pod_no_use_frameworks_app
popd

pushd examples/swift_app_with_pod_use_frameworks
pod update
popd
bash xcodeproj2bazel.sh --pwd=examples/swift_app_with_pod_use_frameworks --workspace=examples/swift_app_with_pod_use_frameworks/swift_app_with_pod_use_frameworks.xcworkspace
pushd examples/swift_app_with_pod_use_frameworks
bazel build swift_app_with_pod_use_frameworks_app
popd

mkdir -p examples/Kingfisher/Kingfisher
[[ -d examples/Kingfisher/Kingfisher/.git ]] || git clone https://github.com/onevcat/Kingfisher.git examples/Kingfisher/Kingfisher --depth=1
bash xcodeproj2bazel.sh --pwd=examples/Kingfisher --workspace=examples/Kingfisher/Kingfisher/Kingfisher.xcworkspace
pushd examples/Kingfisher
bazel build Kingfisher_Demo_app
popd

# TODO: support GENERATE_INFOPLIST_FILE
# bash xcodeproj2bazel.sh --pwd=examples/empty_app_swiftui --project=examples/empty_app_swiftui/empty_app_swiftui.xcodeproj
# pushd examples/empty_app_swiftui
# bazel build empty_app_swiftui_app
# popd
