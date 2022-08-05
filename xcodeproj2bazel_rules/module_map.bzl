# Copyright 2020 LINE Corporation
#
# LINE Corporation licenses this file to you under the Apache License,
# version 2.0 (the "License"); you may not use this file except in compliance
# with the License. You may obtain a copy of the License at:
#
#    https://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
# WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the
# License for the specific language governing permissions and limitations
# under the License.

load("@build_bazel_rules_swift//swift:swift.bzl", "SwiftInfo")
load("xcodeproj2bazel_rules/types.bzl", "HEADERS_FILE_TYPES")

def _module_map_content(
        module_name,
        umbrella_header,
        hdrs,
        swift_generated_header,
        module_map_path):
    # Up to the execution root
    # bazel-out/<platform-config>/bin/<path/to/package>/<target-name>.modulemaps/<module-name>
    slashes_count = module_map_path.count("/") - 1
    relative_path = "".join(["../"] * slashes_count)

    content = "module " + module_name + " {\n"

    if umbrella_header:
        content += "  umbrella header \"%s%s\"\n" % (relative_path, umbrella_header.path)
    else:
        for hdr in hdrs:
            content += "  header \"%s%s\"\n" % (relative_path, hdr.path)
    
    content += "\n"
    content += "  export *\n"
    if umbrella_header:
        content += "  module * { export * }\n"
    content += "}\n"

    # Add a Swift submodule if a Swift generated header exists
    if swift_generated_header:
        content += "\n"
        content += "module " + module_name + ".Swift {\n"
        content += "  header \"%s%s\"\n" % (relative_path, swift_generated_header.path)
        content += "  requires objc\n"
        content += "}\n"

    return content


def _module_map_impl(ctx):
    hdrs = []
    hdrs += ctx.files.hdrs
    swift_generated_header = None
    for dep in ctx.attr.deps:
        if CcInfo in dep:
            objc_headers = dep[CcInfo].compilation_context.headers.to_list()
            for hdr in objc_headers:
                if "." + hdr.extension in HEADERS_FILE_TYPES:
                    hdrs.append(hdr)
                    if SwiftInfo in dep:
                        if hdr.owner == dep.label:
                            swift_generated_header = hdr
                            break

    umbrella_header = None
    if len(ctx.files.umbrella_header) == 1:
        umbrella_header = ctx.files.umbrella_header[0]

    output_module_map = ctx.outputs.out
    if len(ctx.files.module_map_file) == 1:
        module_map_file = ctx.files.module_map_file[0]

        slashes_count = output_module_map.path.count("/") - 1
        relative_path = "".join(["../"] * slashes_count)

        args = ctx.actions.args()
        args.add(module_map_file)
        args.add(output_module_map)
        args.add(relative_path)
        if swift_generated_header:
            args.add(swift_generated_header)
        else:
            args.add("empty")
        args.add(ctx.attr.module_name)
        args.add_all(hdrs)

        ctx.actions.run(
            mnemonic = "ModifyModuleMap",
            arguments = [args],
            executable = ctx.executable._module_map_builder,
            inputs = [module_map_file] + hdrs,
            outputs = [output_module_map],
        )
    else:
        ctx.actions.write(
            content = _module_map_content(
                module_name = ctx.attr.module_name,
                umbrella_header = umbrella_header,
                hdrs = hdrs,
                swift_generated_header = swift_generated_header,
                module_map_path = output_module_map.path,
            ),
            output = output_module_map,
        )

    outputs = []
    outputs += hdrs
    outputs += [output_module_map]
    if umbrella_header:
        outputs += [umbrella_header]

    objc_provider = apple_common.new_objc_provider(
        header = depset(outputs),
    )

    compilation_context = cc_common.create_compilation_context(
        headers = depset(outputs),
    )
    cc_info = CcInfo(
        compilation_context = compilation_context,
    )

    return struct(
        providers = [
            DefaultInfo(
                files = depset([output_module_map]),
            ),
            objc_provider,
            cc_info,
        ],
    )

_module_map = rule(
    implementation = _module_map_impl,
    attrs = {
        "module_name": attr.string(
            mandatory = True,
            doc = "The name of the module.",
        ),
        "hdrs": attr.label_list(
            allow_files = HEADERS_FILE_TYPES,
        ),
        "deps": attr.label_list(
            providers = [CcInfo],
        ),
        "umbrella_header": attr.label(
            allow_files = [".h"],
        ),
        "module_map_file": attr.label(
            allow_files = [".modulemap"],
        ),
        "out": attr.output(
            doc = "The name of the output module map file.",
        ),
        "_module_map_builder": attr.label(
            executable = True,
            cfg = "host",
            allow_files = [".sh"],
            default = "xcodeproj2bazel_rules/modify_module_map.sh",
        ),
    },
    doc = "Generates a module map given a list of header files.",
)

def module_map(name, hdrs = [], module_name = None, module_map_file = None, deps = [], **kwargs):
    native.cc_library(
        name = name + "_headers",
        hdrs = hdrs,
    )
     
    _module_map(
        name = name,
        hdrs = hdrs,
        deps = deps,
        module_name = module_name,
        module_map_file = module_map_file,
        out = name + "/" + module_name + ".framework/Modules/module.modulemap",
        **kwargs
    )
