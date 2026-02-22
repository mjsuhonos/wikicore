BEGIN {
  FS = "\t"
}

NR==FNR {
  grpmap[$1] = $2
  next
}

$1 in grpmap {
  # Direct approach: write to final file for specific group
  if (group == "" || grpmap[$1] == group) {
    outfile = dir "/wikicore-" date "-" grpmap[$1] "-" locale ".tsv"
    print $2 "\t<http://www.wikidata.org/entity/" $1 ">" >> outfile
    close(outfile)
  }
}