BEGIN {
  FS = "\t"
}

NR==FNR {
  instmap[$1] = $2
  next
}

$1 in instmap {
  # Direct approach: write to final file for specific QID
  class_qid = instmap[$1]
  if (qid == "" || class_qid == qid) {
    outfile = dir "/wikicore-" date "-" class_qid "-" locale ".tsv"
    print $2 "\t<http://www.wikidata.org/entity/" $1 ">" >> outfile
    close(outfile)
  }
}