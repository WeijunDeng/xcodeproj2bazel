#!/usr/bin/env bash

set -e
set -x

# 安装 bazel
which bazelisk

if ! [ -x "$(which bazelisk)" ]; then
    brew install bazelisk
fi

which bazel

bazel --version

bundle install --path vendor_bundle
bundle exec "ruby xcodeproj2bazel/Xcodeproj2Bazel.rb $*"
