#!/bin/sh
# platform: macOS-only -- nm reads Mach-O archives
# platform: Apple clang 6 on 10.9 emits a <sym>.eh beside each function; the pair is one definition
duplicate_report() {
  for _dr_a in "$@"; do
    "${NM:-nm}" -gU -A "$_dr_a" | awk '
      NF >= 3 && $(NF-1) ~ /^[A-Za-z]$/ && $NF !~ /\.eh$/ {
        member = $1; sub(/^.*\.a:/, "", member); sub(/:$/, "", member)
        print $NF, member
      }'
  done | LC_ALL=C sort | awk '
    $1 == prev { dup[$1] = dup[$1] " " $2; n[$1] = 1 }
    { if ($1 != prev) first[$1] = $2; prev = $1 }
    END { for (s in n) print s, first[s] dup[s] }
  ' | LC_ALL=C sort | while read -r _dr_sym _dr_members; do
    _dr_pub="${_dr_sym#___recaulk_impl_}"
    [ "$_dr_pub" = "$_dr_sym" ] || _dr_pub="_$_dr_pub"
    _dr_mp=0; _dr_ours=0
    for _dr_m in $_dr_members; do
      case "$_dr_m" in recaulk-*) _dr_ours=1 ;; *) _dr_mp=1 ;; esac
    done
    if [ "$_dr_mp" = 1 ] && [ "$_dr_ours" = 1 ]; then
      _dr_why="MacPorts now carries $_dr_pub: delete ours"
    elif [ "$_dr_ours" = 1 ]; then
      _dr_why="every one of them is ours: delete our own duplicate"
    else
      _dr_why="every one of them is MacPorts': report it upstream"
    fi
    echo "FAIL: $_dr_pub is defined by more than one member: $_dr_members -- $_dr_why (README, rule 2)"
  done
}
