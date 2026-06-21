# Stamp a `reviewed:` approval marker into a doc's YAML frontmatter (the one fs side effect).

# Upsert a `reviewed:` key in YAML frontmatter. Creates a block if none; preserves other keys.
# Rewrites in place via `cat > doc` (keeps the doc's mode/owner); aborts without clobbering on failure.
sr_stamp_marker() { # $1 = doc path, $2 = value
  local doc="$1" val="$2" tmp
  tmp="$(mktemp)" || return 1
  if [ "$(sed -n 1p "$doc")" = "---" ] && sed -n '2,$p' "$doc" | grep -qx -- '---'; then
    awk -v val="$val" '
      NR==1 && $0=="---" { print; infm=1; next }
      infm && $0=="---"  { if(!done) print "reviewed: " val; infm=0; print; next }
      infm && /^reviewed:/ { print "reviewed: " val; done=1; next }
      { print }
    ' "$doc" > "$tmp" || { rm -f "$tmp"; return 1; }
  else
    { printf -- '---\nreviewed: %s\n---\n' "$val"; cat "$doc"; } > "$tmp" || { rm -f "$tmp"; return 1; }
  fi
  cat "$tmp" > "$doc" || { rm -f "$tmp"; return 1; }   # `>` preserves doc's existing mode/inode
  rm -f "$tmp"
}
