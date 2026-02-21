BEGIN {
  seen_count = 0
}

NR==FNR {
  core[$1] = 1
  next
}

$1 in core && !seen[$0]++ {
  print
}