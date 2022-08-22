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

rm -rf examples/Masonry/Masonry
mkdir -p examples/Masonry/Masonry
git clone https://github.com/SnapKit/Masonry.git examples/Masonry/Masonry --depth=1
bash xcodeproj2bazel.sh --pwd=examples/Masonry --workspace=examples/Masonry/Masonry/Masonry.xcworkspace
pushd examples/Masonry
bazel build Masonry_iOS_Examples_app
popd

rm -rf examples/AFNetworking/AFNetworking
mkdir -p examples/AFNetworking/AFNetworking
git clone https://github.com/AFNetworking/AFNetworking.git examples/AFNetworking/AFNetworking --depth=1
bash xcodeproj2bazel.sh --pwd=examples/AFNetworking --workspace=examples/AFNetworking/AFNetworking/AFNetworking.xcworkspace
pushd examples/AFNetworking
bazel build iOS_Example_app
popd

rm -rf examples/SDWebImage/SDWebImage
mkdir -p examples/SDWebImage/SDWebImage
git clone https://github.com/SDWebImage/SDWebImage.git examples/SDWebImage/SDWebImage --depth=1
pushd examples/SDWebImage/SDWebImage
pod update
popd
bash xcodeproj2bazel.sh --pwd=examples/SDWebImage --workspace=examples/SDWebImage/SDWebImage/SDWebImage.xcworkspace
pushd examples/SDWebImage
bazel build SDWebImage_iOS_Demo_app
popd

rm -rf examples/Kingfisher/Kingfisher
mkdir -p examples/Kingfisher/Kingfisher
git clone https://github.com/onevcat/Kingfisher.git examples/Kingfisher/Kingfisher --depth=1
bash xcodeproj2bazel.sh --pwd=examples/Kingfisher --workspace=examples/Kingfisher/Kingfisher/Kingfisher.xcworkspace
pushd examples/Kingfisher
bazel build Kingfisher_Demo_app
popd

pushd examples/swift_app_with_pod_use_frameworks
pod update
popd
bash xcodeproj2bazel.sh --pwd=examples/swift_app_with_pod_use_frameworks --workspace=examples/swift_app_with_pod_use_frameworks/swift_app_with_pod_use_frameworks.xcworkspace
pushd examples/swift_app_with_pod_use_frameworks
bazel build swift_app_with_pod_use_frameworks_app
popd

pushd examples/swift_app_with_pod_no_use_frameworks
pod update
popd
bash xcodeproj2bazel.sh --pwd=examples/swift_app_with_pod_no_use_frameworks --workspace=examples/swift_app_with_pod_no_use_frameworks/swift_app_with_pod_no_use_frameworks.xcworkspace
pushd examples/swift_app_with_pod_no_use_frameworks
bazel build swift_app_with_pod_no_use_frameworks_app
popd
