# Wiki Core

Makefile pipeline to extract SKOS controlled vocabularies from Wikidata RDF dump, build fulltext corpora from the WD5M dataset, and load/train/evaluate vocabularies using the Annif toolkit.

## Targets
### skos
Generates vocabularies as SKOS files:
- class (41)
- occupation (19)
- core (1)

### fulltext
Generates test/train/eval splits for each vocabulary using WD5M as fulltext source.

### all
Generate both skos and fulltext.

### annif
Generate Annif project configurations for vocabularies.

### load
Load vocabularies into Annif.

### train
Train and evaluate vocabularies with Annif using fulltext files.
