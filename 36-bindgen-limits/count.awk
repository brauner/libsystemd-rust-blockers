# Count macros, static inline functions and bitfields per directory.
FNR == 1 { cont = 0; split(FILENAME, p, "/"); dir = p[2] }
{
        if ($0 ~ /^[ \t]*#[ \t]*define[ \t]+[A-Za-z_][A-Za-z0-9_]*\(/) macros[dir]++
        if ($0 ~ /(^|[^A-Za-z0-9_])static[ \t]+(__)?inline(__)?[ \t]/) {
                if (cont || $0 ~ /\\$/) minline[dir]++; else inline[dir]++
        }
        if ($0 ~ /^[ \t]+[A-Za-z_][A-Za-z0-9_ \t*]*[ \t*][A-Za-z_][A-Za-z0-9_]*[ \t]*:[ \t]*[0-9]+[ \t]*[;,]/) bitf[dir]++
        cont = ($0 ~ /\\$/)
}
END {
        printf "%-12s %7s %7s %8s %6s\n", "dir", "macros", "inline", "minline", "bitf"
        n = split("fundamental basic libsystemd systemd", ds, " ")
        for (i = 1; i <= n; i++) {
                d = ds[i]
                printf "%-12s %7d %7d %8d %6d\n", d, macros[d], inline[d], minline[d], bitf[d]
                tm += macros[d]; ti += inline[d]; tmi += minline[d]; tb += bitf[d]
        }
        printf "%-12s %7d %7d %8d %6d\n", "total", tm, ti, tmi, tb
}
