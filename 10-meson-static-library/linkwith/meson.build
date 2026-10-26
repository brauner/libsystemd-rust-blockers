# For comparison, an internal static library may link_with the Rust one.
project('linkwith', 'c', 'rust', default_options : ['rust_std=2021'])
rs = static_library('rs', '../rs.rs', rust_abi : 'c', rust_args : ['-C', 'panic=abort'])
libsystemd_static = static_library('systemd_static', '../c.c', link_with : rs)
