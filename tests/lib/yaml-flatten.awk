# Flatten a multi-document Kustomize render into one line per scalar:
#
#   <document-index><TAB><dotted.path>=<value><TAB><item-chain>
#
# The item chain lists the ids of the enclosing list items, outermost first,
# joined by "/" (empty outside any list), so fields of the same list item can
# be joined: an env entry's name and value share one chain, and a volume's
# nested token source carries its volume's chain as a prefix.
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
function chain(   i, c) {
  c = ""
  for (i = 1; i <= depth; i++) if (stack_key[i] == "[]") c = (c == "" ? stack_id[i] : c "/" stack_id[i])
  return c
}
function push_item(ind) { depth++; stack_key[depth] = "[]"; stack_ind[depth] = ind + 1; stack_id[depth] = ++items }
function emit_pair(body, ind,   k, v, colon) {
  colon = index(body, ": ")
  if (colon > 0) {
    k = substr(body, 1, colon - 1); v = strip(substr(body, colon + 2))
  } else {
    k = substr(body, 1, length(body) - 1); v = ""
  }
  if ((v ~ /^'/ && v !~ /^'.*'$/) || (v ~ /^"/ && v !~ /^".*"$/) || v == "'" || v == "\"") {
    # A quoted flow scalar that kustomize folded onto following lines.
    pending = 1; pending_key = join(path(), k); pending_value = v; pending_chain = chain()
    pending_quote = substr(v, 1, 1)
    return
  }
  if (v == "" ) {
    depth++; stack_key[depth] = k; stack_ind[depth] = ind
  } else {
    printf "%d\t%s=%s\t%s\n", doc, join(path(), k), v, chain()
    if (v ~ /^[|>][-+]?[0-9]*$/) { skip_above = ind }
  }
}
BEGIN { doc = 0; depth = 0; skip_above = -1; items = 0; pending = 0 }
/^---[ \t]*$/ { doc++; depth = 0; skip_above = -1; pending = 0; next }
{
  line = $0
  if (pending) {
    part = line; sub(/^[ \t]+/, "", part)
    pending_value = pending_value " " part
    if (substr(part, length(part), 1) == pending_quote) {
      printf "%d\t%s=%s\t%s\n", doc, pending_key, strip(pending_value), pending_chain
      pending = 0
    }
    next
  }
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
      push_item(ind)
      emit_pair(item, ind + 2)
    } else if (item == "") {
      push_item(ind)
    } else {
      push_item(ind)
      printf "%d\t%s=%s\t%s\n", doc, path(), strip(item), chain()
      depth--
    }
    next
  }
  while (depth > 0 && stack_ind[depth] >= ind) depth--
  if (body ~ /^[^ "'][^:]*:( |$)/) emit_pair(body, ind)
}
