# Prints "name variadic|va_list extern|inline" for each such sd_*() function.
# va_list decays to an architecture-specific type, so take it from the probe.
(.inner[] | select(.name == "va_list_probe") | .inner[0].type.qualType) as $va_list
| .inner[]
| select(.kind == "FunctionDecl" and (.isImplicit | not) and (.name | startswith("sd_")))
| (if .variadic then "variadic"
   elif any(.inner[]?; .kind == "ParmVarDecl" and .type.qualType == $va_list) then "va_list"
   else empty end) as $kind
| "\(.name) \($kind) \(if .inline then "inline" else "extern" end)"
