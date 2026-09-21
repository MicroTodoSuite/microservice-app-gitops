# Flatten a multi-document Kustomize render into one line per scalar:
#
#   <document-index><TAB><dotted.path>=<value>
#
# List items appear as `path[]` and maps inside list items keep the `[]`
# segment, so `spec.template.spec.containers[].image=...` is one line per
# container. Block scalars (`|`, `>`) are emitted once with the literal marker
# as their value and their body is skipped; tests that need a block body read
# the raw render instead.
#
# It understands the normalized YAML that `kustomize build` emits (two-space
# indentation, sequences at their parent key's indentation). It is not a
# general YAML parser and is only ever fed kustomize output.
function indent_of(s) { match(s, /^ */); return RLENGTH }
function strip(v) {
  sub(/^[ \t]+/, "", v); sub(/[ \t]+$/, "", v)
  if (v ~ /^".*"$/ || v ~ /^'.*'$/) v = substr(v, 2, length(v) - 2)
  return v
}
function path(   i, p) {
  p = ""
  for (i = 1; i <= depth; i++) {
    if (stack_key[i] == "[]") p = p "[]"
    else p = (p == "" ? stack_key[i] : p "." stack_key[i])
  }
  return p
}
function join(p, k) { return p == "" ? k : p "." k }
function emit_pair(body, ind,   k, v, colon) {
  colon = index(body, ": ")
  if (colon > 0) {
    k = substr(body, 1, colon - 1); v = strip(substr(body, colon + 2))
  } else {
    k = substr(body, 1, length(body) - 1); v = ""
  }
  if (v == "" ) {
    depth++; stack_key[depth] = k; stack_ind[depth] = ind
  } else {
    printf "%d\t%s=%s\n", doc, join(path(), k), v
    if (v ~ /^[|>][-+]?[0-9]*$/) { skip_above = ind }
  }
}
BEGIN { doc = 0; depth = 0; skip_above = -1 }
/^---[ \t]*$/ { doc++; depth = 0; skip_above = -1; next }
{
  line = $0
  if (line ~ /^[ \t]*$/ || line ~ /^[ \t]*#/) next
  ind = indent_of(line)
  if (skip_above >= 0) {
    if (ind > skip_above) next
    skip_above = -1
  }
  body = substr(line, ind + 1)
  if (body ~ /^- / || body == "-") {
    while (depth > 0 && stack_ind[depth] > ind) depth--
    item = (body == "-") ? "" : substr(body, 3)
    if (item ~ /^[^ "'][^:]*:( |$)/ ) {
      depth++; stack_key[depth] = "[]"; stack_ind[depth] = ind + 1
      emit_pair(item, ind + 2)
    } else if (item == "") {
      depth++; stack_key[depth] = "[]"; stack_ind[depth] = ind + 1
    } else {
      printf "%d\t%s[]=%s\n", doc, path(), strip(item)
    }
    next
  }
  while (depth > 0 && stack_ind[depth] >= ind) depth--
  if (body ~ /^[^ "'][^:]*:( |$)/) emit_pair(body, ind)
}
