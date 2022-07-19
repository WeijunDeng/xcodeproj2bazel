def cc_header(name = None, hdrs = []):
    native.cc_library(
        name = name,
        hdrs = hdrs,
    )

