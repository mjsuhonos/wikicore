# Wiki Core Processing Pipeline

This document describes the complete workflow for building the Wiki Core vocabulary from Wikidata.

## Overview

Wiki Core is built through a 10-step pipeline that:
1. Extracts relevant Wikidata relationships (P31, P279, P361)
2. Splits data for parallel processing
3. Extracts the class backbone (P279, P361)
4. Loads backbone into Apache Jena
5. Materializes transitive relationships and exports core concepts
6. Discovers and generates top-level buckets via SPARQL
7. Partitions instances into buckets (with sitelinks filtering)
8. Sorts, merges, and filters concepts
9. Generates SKOS vocabulary components
10. Merges into final output

## Prerequisites

### Required Software
- **GNU coreutils** (`gsplit`) - for splitting large files
- **pigz** - parallel gzip for decompression
- **ripgrep** (`rg`) - fast text search
- **Apache Jena** - RDF triple store and SPARQL engine
  - `tdb2.tdbloader` - load RDF data
  - `tdb2.tdbupdate` - run SPARQL UPDATE queries
  - `tdb2.tdbquery` - run SPARQL SELECT queries
- **GNU Parallel** - parallel processing
- **Python 3** - for data processing scripts
- **Basic Unix tools** - `awk`, `sort`, `join`, `grep`, etc.

### Required Data Files

Place these in `source.nosync/`:

1. **Wikidata property direct dump** (compressed N-Triples)
   - File: `wikidata-YYYYMMDD-propdirect.nt.gz`
   - Contains P31, P279, P361 relationships
   - ~100GB compressed, ~500GB uncompressed

2. **Wikidata SKOS labels** (compressed N-Triples)
   - File: `wikidata-YYYYMMDD-skos-labels-<LOCALE>.nt.gz`
   - Contains multilingual labels
   - ~50GB compressed

3. **Wikipedia sitelinks** (TSV)
   - File: `sitelinks_<LOCALE>_qids.tsv`
   - Format: `<http://www.wikidata.org/entity/Q123>` (one per line)
   - Contains ~60M items with Wikipedia articles

### Directory Structure

```
wikicore/
├── Makefile                      # Main build pipeline
├── extract_backbone.py           # Step 3: extract P279/P361
├── generate_buckets.py           # Step 6: discover and generate buckets
├── partition_instances.py        # Step 7: partition P31 instances
├── queries/                      # SPARQL queries
│   ├── materialize_ancestors.rq
│   ├── materialize_child_counts.rq
│   ├── export.rq
│   ├── discover_buckets.rq
│   └── bucket_descendants_template.rq
├── source.nosync/                # Input data (not in git)
│   ├── wikidata-YYYYMMDD-propdirect.nt.gz
│   ├── wikidata-YYYYMMDD-skos-labels-en.nt.gz
│   └── sitelinks_en_qids.tsv
└── working.nosync/               # Working files (not in git)
    ├── wikidata-core-props-P31-P279-P361.nt
    ├── concept_backbone.nt
    ├── core_concepts_qids.tsv
    ├── core_nosubject_qids.tsv
    ├── splits/
    ├── jena/
    ├── buckets_qid/
    ├── subjects/
    └── skos/
```

## Pipeline Steps

### Step 1: Extract Core Properties
```bash
make working.nosync/wikidata-core-props-P31-P279-P361.nt
```
- Decompresses the Wikidata dump
- Filters for P31 (instance of), P279 (subclass of), P361 (part of)
- Removes blank nodes
- Output: ~150GB, ~100M triples

### Step 2: Split Into Chunks
```bash
make working.nosync/splits/.split_done
```
- Splits the large file into equal-sized chunks (one per CPU core by default)
- Enables parallel processing in later steps
- Output: `splits/chunk_aa`, `splits/chunk_ab`, ...

### Step 3: Extract Backbone
```bash
make working.nosync/concept_backbone.nt
```
- Extracts only P279 (subclass) and P361 (part-of) from chunks
- Does not process P31 instances yet
- Output: `concept_backbone.nt` (~30M triples)

### Step 4: Load Into Jena
```bash
make working.nosync/jena/tdb2_loaded
```
- Loads backbone into Apache Jena TDB2
- Creates a queryable RDF database for SPARQL operations
- Output: `jena/` directory with TDB2 database files

### Step 5: Materialize and Export
```bash
make working.nosync/core_concepts_qids.tsv
```
- Materializes transitive closure of ancestors (P279/P361)
- Computes child counts for each class
- Exports all core concept QIDs
- Output: `core_concepts_qids.tsv`

### Step 6: Generate Buckets
```bash
make working.nosync/buckets_qid/.buckets_done
```
- Queries Jena for classes 1-2 hops from the root entity (default: Q35120)
- For each top-level class, finds all descendant classes
- Writes one TSV file per bucket containing full URIs
- Customizable root: `make all ROOT_QID=Q16521`
- Output: `working.nosync/buckets_qid/Q*.tsv`

### Step 7: Partition Instances
```bash
make working.nosync/subjects/.partition_done
```
- Extracts P31 (instance-of) triples from chunks
- Filters by sitelinks (keeps only items with Wikipedia articles, ~50% reduction)
- Assigns instances to buckets based on their P31 classes
- Output: `subjects/Q*_subjects.tsv`, `subjects/P31_other_subjects.tsv`

### Step 8: Sort, Merge, and Filter
```bash
make working.nosync/core_nosubject_qids.tsv
```
- Sorts and deduplicates each subject file
- Merges all subject files into a single sorted list
- Removes subjects from concepts (classes that appear as instances are excluded)
- Output: `core_nosubject_qids.tsv`

### Step 9: Generate SKOS
```bash
make working.nosync/skos/
```
Generates four SKOS components:

1. **skos_concepts.nt** - `rdf:type skos:Concept` declarations
2. **skos_concept_scheme.nt** - `skos:inScheme` membership
3. **skos_labels_en.nt** - `skos:prefLabel` labels (locale-specific)
4. **skos_broader.nt** - `skos:broader` hierarchy from backbone

### Step 10: Final Merge
```bash
make wikicore-YYYYMMDD-en.nt
```
- Concatenates all SKOS components into the final vocabulary
- Output: `wikicore-YYYYMMDD-en.nt` (~5GB)

## Usage

### Build Complete Vocabulary
```bash
make all
```

### Build with Custom Settings
```bash
make all LOCALE=fr JOBS=32 ROOT_QID=Q35120
```

### Build Subject-Specific Vocabularies
```bash
make skos_subjects SUBJECTS=Q5
make skos_subjects SUBJECTS="Q5 Q215627 Q488383"
```

### Verify Output
```bash
make verify
```

### Clean
```bash
make clean        # Remove working files only
make clean-all    # Remove working files and outputs
```

## Performance Tuning

### Memory
- **Minimum**: 32GB RAM for Jena
- **Recommended**: 64GB RAM
- Set via: `export JENA_JAVA_OPTS="-Xmx64g"`

### Parallel Processing
- Default uses all CPU cores (`nproc`)
- Custom: `make all JOBS=16`
- More jobs = faster but more memory

### Disk Space
- Source data: ~150GB compressed, ~550GB uncompressed
- Working files: ~200GB
- Final output: ~5GB
- Total: ~800GB recommended

## Troubleshooting

### "tdb2.tdbloader: command not found"
Install Apache Jena and add to PATH:
```bash
export PATH=/path/to/jena/bin:$PATH
```

### Out of memory
Increase Jena heap size:
```bash
export JENA_JAVA_OPTS="-Xmx64g -XX:ParallelGCThreads=16"
```

### Slow processing
- Reduce JOBS if memory constrained: `make all JOBS=8`
- Use SSD storage for `working.nosync/`
- Ensure sitelinks file is sorted: `LC_ALL=C sort -c source.nosync/sitelinks_en_qids.tsv`

### Missing labels in output
Check locale matches between labels file and `LOCALE` setting:
```bash
ls source.nosync/wikidata-*-skos-labels-*.nt.gz
make clean && make all LOCALE=en
```

### Verification failures
```bash
make verify
```
Check that backbone has both P279 and P361 triples, subject files are non-empty, and final output has all 4 SKOS components.

## File Format Reference

### N-Triples
```turtle
<http://www.wikidata.org/entity/Q5> <http://www.w3.org/prop/direct/P279> <http://www.wikidata.org/entity/Q35120> .
```

### TSV (Sitelinks / Subjects)
```
<http://www.wikidata.org/entity/Q5>
<http://www.wikidata.org/entity/Q42>
```

## Development Notes

### Adding New Languages
1. Download SKOS labels for target language
2. Ensure sitelinks file exists for that language
3. Build: `make all LOCALE=fr`

### Custom Materialization Rules
Edit SPARQL queries in `queries/`:
- `materialize_ancestors.rq` - Transitive closure rules
- `materialize_child_counts.rq` - Counting logic
- `export.rq` - Concept selection criteria

### Customizing Bucket Discovery
Edit `queries/discover_buckets.rq` to change bucket granularity:
- `{1}` - direct children of root only (fewer, coarser buckets)
- `{1,2}` - 1-2 hops (default, more buckets)
- Change root entity: `make all ROOT_QID=Q488383`

## References

- [Wikidata](https://www.wikidata.org/)
- [SKOS Specification](https://www.w3.org/TR/skos-reference/)
- [Apache Jena](https://jena.apache.org/)
- [Library of Congress Subject Headings](https://www.loc.gov/aba/cataloging/subject/)
