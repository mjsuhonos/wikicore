BEGIN {
  FS = "\t"
}

NR==FNR {
  instmap[$1] = $2
  next
}

$1 in instmap {
  # Write to chunk-specific temporary files to avoid race conditions
  class_qid = instmap[$1]
  outfile = dir "/wikicore-" date "-" class_qid "-" locale ".tsv.chunk" chunk_id
  print $2 "\t<http://www.wikidata.org/entity/" $1 ">" >> outfile
  close(outfile)
}