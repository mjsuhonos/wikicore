# Wiki Core

Toolkit to extract SKOS controlled vocabularies from Wikidata RDF dump, build fulltext corpora from the WD5M dataset, and load/train/evaluate vocabularies using the Annif toolkit.

```shell
Usage: make [TARGET] [-j N] [OPTIONS]
   eg. make annif -j 4 LOCALE=fr BACKEND=omikuji

Targets:
skos
  vocab		Generate SKOS vocabs (.nt)
  fulltext	Generate fulltext splits (.tsv)

annif
  config	Generate Annif project configs (.cfg)
  load		Load vocabs into Annif
  train		Train and evaluate vocabs (.json)

  compress	Compress vocabs and fulltext (.gz)
  decompress	Extract vocabs and fulltext

Options:
  -j N		Number of parallel jobs ('-j' alone means all CPUs)
  RUN_DATE	Default '20260727' (eg. YYYYMMDD)
  LOCALE	Default 'en'
  BACKEND	Default 'mllm'
```

## SKOS targets (make skos)
### vocab
Generates vocabularies as SKOS files using Wikidata RDF dump as source:
- class (41)
- occupation (19)
- core (1)

### fulltext
Generates test/train/eval splits for each vocabulary using WD5M as fulltext source.

## Annif targets (make annif)
### config
Generate Annif project configurations.

### load
Load vocabularies into Annif.

### train
Train and evaluate vocabularies with Annif using fulltext files.

## Utility targets
### compress
Compress vocabs and fulltext using pigz.

### decompress
Extract vocabs and fulltext (cloned from GitHub) using pigz.