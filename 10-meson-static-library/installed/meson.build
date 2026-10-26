# An installed static library with Rust code, like libsystemd.a.
project('installed', 'c', 'rust', default_options : ['rust_std=2021'])
rs = static_library('rs', '../rs.rs', rust_abi : 'c', rust_args : ['-C', 'panic=abort'])
static_library('systemd', '../c.c', link_with : rs, install : true)
