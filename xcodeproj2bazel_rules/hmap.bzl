load("xcodeproj2bazel_rules/types.bzl", "HEADERS_FILE_TYPES")

"""Header Map rules"""

HeaderMapInfo = provider(
    doc = "Propagates header maps",
    fields = {
        "files": "depset with header_maps",
    },
)

def _make_hmap(actions, header_map_builder, output, namespace, hdrs_lists, namespace_only):
    """Makes an hmap file.

    Args:
        actions: a ctx.actions struct
        header_map_builder: an executable pointing to @bazel_build_rules_ios//rules/hmap:hmaptool
        output: the output file that will contain the built hmap
        namespace: the prefix to be used for header imports
        hdrs_lists: an array of enumerables containing headers to be added to the hmap
    """

    args = actions.args()
    if namespace:
        args.add("--namespace", namespace)

    args.add("--output", output)

    if namespace_only == True:
        args.add("--namespace_only")

    for hdrs in hdrs_lists:
        args.add_all(hdrs)

    args.set_param_file_format(format = "multiline")
    args.use_param_file("@%s")

    actions.run(
        mnemonic = "HmapCreate",
        arguments = [args],
        executable = header_map_builder,
        outputs = [output],
    )

def _make_header_map_impl(ctx):
    """Implementation of the header_map() rule.

    It creates a text file with
    the mappings and creates an action that calls out to the hmapbuild
    tool included here to create the actual .hmap file.

    :param ctx: context for this rule. See
           https://docs.bazel.build/versions/master/starlark/lib/ctx.html

    :return: provider with the info for this rule
    """
    hdrs_list = []
    for hdr in ctx.files.hdrs:
        if "." + hdr.extension in HEADERS_FILE_TYPES:
            hdrs_list.append(hdr)
    
    hdrs_lists = []
    if len(hdrs_list) > 0:
        hdrs_lists = [hdrs_list]
    for provider in ctx.attr.direct_hdr_providers:
        if apple_common.Objc in provider:
            hdrs_lists.append(provider[apple_common.Objc].direct_headers)
        if CcInfo in provider:
            hdrs_lists.append(provider[CcInfo].compilation_context.direct_headers)

        if len(hdrs_lists) == 1:
            # means neither apple_common.Objc nor CcInfo in hdr provider target
            fail("direct_hdr_provider %s must contain either 'CcInfo' or 'objc' provider" % provider)

    hmap.make_hmap(
        actions = ctx.actions,
        header_map_builder = ctx.executable._header_map_builder,
        output = ctx.outputs.header_map,
        namespace = ctx.attr.namespace,
        namespace_only = ctx.attr.namespace_only,
        hdrs_lists = hdrs_lists,
    )
    outputs = []
    for hdrs_list in hdrs_lists:
        outputs += hdrs_list
    outputs += [ctx.outputs.header_map]
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
                files = depset([ctx.outputs.header_map]),
            ),
            objc_provider,
            cc_info,
        ],
    )

# Derive a header_map from transitive header_maps
# hdrs: a file group containing headers for this rule
# namespace: the Apple style namespace these header should be under
_header_map = rule(
    implementation = _make_header_map_impl,
    output_to_genfiles = True,
    attrs = {
        "namespace": attr.string(
            mandatory = False,
            doc = "The prefix to be used for header imports",
        ),
        "namespace_only": attr.bool(
            default = False,
        ),
        "hdrs": attr.label_list(
            mandatory = False,
            allow_files = True,
            doc = "The list of headers included in the header_map",
        ),
        "direct_hdr_providers": attr.label_list(
            mandatory = False,
            doc = "Targets whose direct headers should be added to the list of hdrs",
        ),
        "_header_map_builder": attr.label(
            executable = True,
            cfg = "host",
            default = Label(
                "//xcodeproj2bazel_rules/hmap:hmaptool",
            ),
        ),
    },
    outputs = {"header_map": "%{name}.hmap"},
    doc = """\
Creates a binary header_map file from the given headers,
suitable for passing to clang.

This can be used to allow headers to be imported at a consistent path,
regardless of the package structure being used.
    """,
)

hmap = struct(
    make_hmap = _make_hmap,
)

def header_map(name, hdrs = [], **kwargs):
    _header_map(
        name = name,
        hdrs = hdrs,
        **kwargs
    )
    native.cc_library(
        name = name + "_headers",
        hdrs = hdrs,
    )
