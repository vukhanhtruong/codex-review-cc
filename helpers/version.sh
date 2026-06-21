# Semantic-version comparison — pure bash, no GNU sort -V dependency.

# rc 0 iff dotted-numeric version $1 >= minimum $2.
sr_version_ge() { # $1 = have, $2 = min
  local IFS=. ; local -a a=($1) b=($2) ; local i x y
  for i in 0 1 2; do
    x=${a[i]:-0}; y=${b[i]:-0}
    if ((10#$x > 10#$y)); then return 0; fi
    if ((10#$x < 10#$y)); then return 1; fi
  done
  return 0
}
