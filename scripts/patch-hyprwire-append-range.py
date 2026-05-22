#!/usr/bin/env python3
import re, pathlib

base = pathlib.Path("/home/franky/proyectos/Hyprland-on-debian/hyprbuild/hyprwire")
files = [
    "src/core/message/messages/BindProtocol.cpp",
    "src/core/message/messages/HandshakeBegin.cpp",
    "src/core/message/messages/FatalProtocolError.cpp",
    "src/core/message/messages/HandshakeProtocols.cpp",
    "src/core/socket/SocketHelpers.cpp",
    "src/core/wireObject/IWireObject.cpp",
]
pat = re.compile(r'^(\s*)([\w.]+)\.append_range\((.*)\);\s*$')
total = 0
for rel in files:
    p = base / rel
    text = p.read_text()
    out = []
    n = 0
    for line in text.splitlines(keepends=True):
        m = pat.match(line)
        if m:
            indent, target, expr = m.group(1), m.group(2), m.group(3)
            new = f"{indent}{{ auto&& _r = {expr}; {target}.insert({target}.end(), _r.begin(), _r.end()); }}\n"
            out.append(new)
            n += 1
        else:
            out.append(line)
    p.write_text("".join(out))
    print(f"{rel}: {n} replacements")
    total += n
print(f"TOTAL: {total}")
