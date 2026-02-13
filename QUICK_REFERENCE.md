# Wiki Core Quick Reference

## Quick Start

```bash
# 1. Validate setup
bash setup_check.sh

# 2. Build everything
make all

# 3. Verify output
make verify
```

## Common Commands

### Building

```bash
# Full pipeline
make all

# With options
make all LOCALE=fr JOBS=16 ROOT_QID=Q488383

# Step by step (for debugging)
make working.nosync/wikidata-core-props-P31-P279-P361.nt  # 1. Extract
make working.nosync/splits/.split_done                     # 2. Split
make working.nosync/concept_backbone.nt                    # 3. Backbone
make working.nosync/jena/tdb2_loaded                       # 4. Jena
make working.nosync/core_concepts_qids.tsv                 # 5. Materialize
make working.nosync/buckets_qid/.buckets_done              # 6. Buckets
make working.nosync/subjects/.partition_done                # 7. Partition
make working.nosync/core_nosubject_qids.tsv                # 8. Filter
make working.nosync/skos/                                  # 9. SKOS
make wikicore-YYYYMMDD-en.nt                               # 10. Merge
```

### Subject Vocabularies

```bash
make skos_subjects SUBJECTS=Q5
make skos_subjects SUBJECTS="Q5 Q215627 Q488383"
```

### Cleaning

```bash
make clean        # Remove working files (keep outputs)
make clean-all    # Remove everything
```

### Verification

```bash
make verify

# Manual checks
wc -l wikicore-YYYYMMDD-en.nt
ls -lh working.nosync/subjects/*_subjects.tsv | wc -l
grep -c "P279>" working.nosync/concept_backbone.nt
grep -c "P361>" working.nosync/concept_backbone.nt
```

## Pipeline Stages

| Step | Target | What It Does | Output |
|------|--------|--------------|--------|
| 1 | `core-props.nt` | Extract P31/P279/P361 | ~150GB filtered triples |
| 2 | `.split_done` | Split into chunks | ~32 chunk files |
| 3 | `concept_backbone.nt` | Extract P279/P361 only | Backbone for Jena |
| 4 | `tdb2_loaded` | Load into Jena | TDB2 database |
| 5 | `core_concepts_qids.tsv` | Materialize + export | Core concept QIDs |
| 6 | `.buckets_done` | Discover top-level buckets | Bucket files |
| 7 | `.partition_done` | Partition instances | Subject files per bucket |
| 8 | `core_nosubject_qids.tsv` | Sort, merge, filter | Final concept list |
| 9 | `skos/*.nt` | Generate SKOS | SKOS components |
| 10 | `wikicore-*.nt` | Merge output | Final vocabulary |

## Key Files

### Inputs (source.nosync/)
- `wikidata-YYYYMMDD-propdirect.nt.gz` - Wikidata dump (~100GB)
- `wikidata-YYYYMMDD-skos-labels-en.nt.gz` - Labels (~50GB)
- `sitelinks_en_qids.tsv` - Wikipedia articles (~60M items)

### Working Files (working.nosync/)
- `wikidata-core-props-P31-P279-P361.nt` - Filtered properties (~150GB)
- `concept_backbone.nt` - Class hierarchy (~5GB)
- `splits/chunk_*` - Data chunks for parallel processing
- `buckets_qid/Q*.tsv` - Top-level bucket definitions
- `subjects/Q*_subjects.tsv` - Instances per bucket
- `jena/` - TDB2 database
- `skos/*.nt` - SKOS components

### Outputs
- `wikicore-YYYYMMDD-en.nt` - Main vocabulary (~5GB)
- `wikicore-YYYYMMDD-Q5-en.nt` - Subject-specific vocab

## Troubleshooting

### Out of memory during Jena loading
```bash
export JENA_JAVA_OPTS="-Xmx64g -XX:ParallelGCThreads=16"
```

### Slow processing
```bash
make all JOBS=8                  # Reduce parallelism
LC_ALL=C sort -c source.nosync/sitelinks_en_qids.tsv  # Check sort order
```

### Invalid triples in output
```bash
grep -v "^<.*> <.*> <.*> \.$" wikicore-YYYYMMDD-en.nt
riot --validate wikicore-YYYYMMDD-en.nt
```

### Missing labels
```bash
wc -l working.nosync/skos/skos_labels_en.nt
ls source.nosync/wikidata-*-skos-labels-*.nt.gz
make clean && make all LOCALE=en
```

## Statistics

```bash
# Concepts, labels, broader relations
grep -c "skos:Concept" wikicore-YYYYMMDD-en.nt
grep -c "skos:prefLabel" wikicore-YYYYMMDD-en.nt
grep -c "skos:broader" wikicore-YYYYMMDD-en.nt

# Instance distribution across buckets
for f in working.nosync/subjects/*_subjects.tsv; do
  bucket=$(basename $f _subjects.tsv)
  count=$(wc -l < $f)
  printf "%-20s %10d instances\n" "$bucket" "$count"
done | sort -k2 -rn
```

## Performance Tips

- Use SSD storage for `working.nosync/`
- Pre-sort sitelinks: `LC_ALL=C sort -o source.nosync/sitelinks_en_qids.tsv source.nosync/sitelinks_en_qids.tsv`
- Monitor disk: `du -sh working.nosync/ source.nosync/`
- Pipeline requires ~800GB total disk space

## Help

```bash
make help          # Makefile targets and options
bash setup_check.sh  # Validate prerequisites
```

See `README_WORKFLOW.md` for full pipeline documentation.
