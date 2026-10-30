"""render_rexglue_cmake.py <sdk> <out>: render resources/templates/init/rexglue_cmake.inja for LARecomp without the
xex (what `rexglue codegen` writes as generated/rexglue.cmake). Android/cross builds also need codegen to run with
the *host* rexglue binary, so the codegen command uses REXGLUE_HOST_TOOL when it is set."""
import re
import sys

sdk, out = sys.argv[1], sys.argv[2]
t = open(f"{sdk}/resources/templates/init/rexglue_cmake.inja", encoding="utf-8").read()
t = re.sub(r'\{\{\s*cmake_var\("([A-Za-z_]+)"\)\s*\}\}', r"${\1}", t)
t = t.replace("{{ sdk_version }}", "0.10.0")
t = t.replace("{{ entrypoint_out_dir }}", "generated")
t = t.replace("{{ names.snake_case }}", "larecomp")
left = re.findall(r"\{\{.*?\}\}|\{%.*?%\}", t)
if left:
    sys.exit(f"unrendered: {left}")
# android: cross builds run the host's rexglue for codegen (the target's binary cannot run on the build machine).
t = t.replace("COMMAND $<TARGET_FILE:rex::rexglue> codegen",
              "COMMAND ${_rexglue_codegen_tool} codegen")
t = t.replace("add_custom_command(\n    OUTPUT",
              'if(REXGLUE_HOST_TOOL)\n    set(_rexglue_codegen_tool "${REXGLUE_HOST_TOOL}")\nelse()\n'
              '    set(_rexglue_codegen_tool $<TARGET_FILE:rex::rexglue>)\nendif()\nadd_custom_command(\n    OUTPUT', 1)
# android: REXGLUE_SKIP_CODEGEN compiles the hand-written sources without running codegen (no xex yet).
n = t.count("add_dependencies(${target_name} larecomp_codegen)")
t = t.replace("add_dependencies(${target_name} larecomp_codegen)",
              "if(NOT REXGLUE_SKIP_CODEGEN)\n        add_dependencies(${target_name} larecomp_codegen)\n    endif()")
if n != 1:
    sys.exit(f"expected 1 host codegen dependency, found {n}")
open(out, "w", encoding="utf-8", newline="\n").write(t)
print("wrote", out)
