# libsystemd_static with its Rust part link_whole'd in.
project('whole', 'c', 'rust', default_options : ['rust_std=2021'])
rs = static_library('rs', '../rs.rs', rust_abi : 'c', rust_args : ['-C', 'panic=abort'])
libsystemd_static = static_library('systemd_static', '../c.c', link_whole : rs)
