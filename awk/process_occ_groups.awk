BEGIN {
  FS = "\t"
}

NR==FNR {
  grpmap[$1] = $2
  next
}

$1 in grpmap {
  # Write to chunk-specific temporary files to avoid race conditions
  outfile = dir "/wikicore-" date "-" grpmap[$1] "-" locale ".tsv.chunk" chunk_id
  print $2 "\t<http://www.wikidata.org/entity/" $1 ">" >> outfile
  close(outfile)
}