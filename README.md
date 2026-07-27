# Wiki Core

Makefile toolkit to extract SKOS controlled vocabularies from Wikidata RDF dump, build fulltext corpora from the WD5M dataset, and load/train/evaluate vocabularies using the Annif toolkit.

## SKOS targets
### vocab
Generates vocabularies as SKOS files:
- class (41)
- occupation (19)
- core (1)

### fulltext
Generates test/train/eval splits for each vocabulary using WD5M as fulltext source.

### skos
Generate both vocabs and fulltext.

## Annif targets
### config
Generate Annif project configurations.

### load
Load vocabularies into Annif.

### train
Train and evaluate vocabularies with Annif using fulltext files.

### annif
Generate configs, load vocabs, and train models.

## Utility targets
### compress
Compress vocabs and fulltext using pigz.

### decompress
Extract vocabs and fulltext (cloned from GitHub) using pigz.