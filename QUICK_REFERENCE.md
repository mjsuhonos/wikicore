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
# Full pipeline (buckets auto-generated)
make all

# With custom root entity for buckets
make all ROOT_QID=Q488383

# With custom locale
make all LOCALE=fr

# With custom parallelism
make all JOBS=16

# Step by step (for debugging)
make working.nosync/wikidata-core-props-P31-P279-P361.nt
make working.nosync/splits/.split_done
make working.nosync/backbone_only.nt
make working.nosync/jena/tdb2_loaded
make working.nosync/buckets_qid/.buckets_generated  # Auto-generates buckets
make working.nosync/concept_backbone.nt
make working.nosync/core_concepts_qids.tsv
make working.nosync/core_nosubject_qids.tsv
make working.nosync/skos/
make wikicore-YYYYMMDD-en.nt
```

### Bucket Management

```bash
# Force regenerate buckets
make regenerate_buckets

# Regenerate with different root entity
make regenerate_buckets ROOT_QID=Q2424752

# Check existing buckets
ls -lh buckets_qid/*.tsv
wc -l buckets_qid/*.tsv

# View bucket statistics
for f in buckets_qid/*.tsv; do echo "$f: $(wc -l < $f) classes"; done | sort -t: -k2 -rn
```

### Subject Vocabularies

```bash
# Single subject (e.g., humans - Q5)
make skos_subjects SUBJECTS=Q5

# Multiple subjects
make skos_subjects SUBJECTS="Q5 Q215627 Q488383"
```

### Cleaning

```bash
# Remove working files (keep outputs)
make clean

# Remove everything (including final outputs)
make clean-all
```

### Verification

```bash
# Check pipeline outputs
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
| 3 | `backbone_only.nt` | Extract P279/P361 only | Backbone for Jena |
| 4 | `tdb2_loaded` | Load into Jena | TDB2 database |
| 5 | `.buckets_generated` | Auto-generate buckets | Bucket files |
| 6 | `concept_backbone.nt` | Partition instances | Backbone + subject files |
| 7 | `core_concepts_qids.tsv` | Materialize + export | Core concept QIDs |
| 8 | `core_nosubject_qids.tsv` | Filter subjects | Final concept list |
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
- `subjects/Q*_subjects.tsv` - Instances per bucket
- `jena/` - TDB2 database

### Outputs
- `wikicore-YYYYMMDD-en.nt` - Main vocabulary (~5GB)
- `wikicore-YYYYMMDD-Q5-en.nt` - Subject-specific vocab

## Bucket Management

### Automatic Bucket Generation

Buckets are automatically generated in Step 5 of the pipeline. No manual intervention needed!

**How it works:**
1. Pipeline loads backbone into Jena (Step 4)
2. Queries Jena to discover top-level classes from root entity
3. For each top-level class, finds all descendants
4. Creates `buckets_qid/Q*.tsv` files automatically

**Customization:**
```bash
# Use different root entity
make all ROOT_QID=Q488383  # object
make all ROOT_QID=Q2424752  # abstract object

# Force regenerate (e.g., after changing root)
make regenerate_buckets ROOT_QID=Q488383
```

**Verification:**
```bash
# Check bucket files exist
ls -lh buckets_qid/*.tsv

# Count classes per bucket
for f in buckets_qid/*.tsv; do 
  echo "$(basename $f .tsv): $(wc -l < $f) classes"
done | sort -t: -k2 -rn

# Check for overlaps (expected!)
cat buckets_qid/*.tsv | sort | uniq -c | awk '$1 > 1 {count++} END {print count " classes in multiple buckets"}'
```

### Manual Bucket Creation (Advanced)

1. **Load backbone into Jena** (Step 4)

2. **Query for top-level buckets:**
```bash
tdb2.tdbquery --loc working.nosync/jena \
  --query=queries/discover_buckets.rq \
  --results=TSV > buckets_list.tsv
```

Example query (`queries/discover_buckets.rq`):
```sparql
PREFIX wdt: <http://www.wikidata.org/prop/direct/>
PREFIX wd:  <http://www.wikidata.org/entity/>

SELECT DISTINCT ?bucket
WHERE {
  ?bucket (wdt:P279|wdt:P361){1,2} wd:Q35120 .
}
```

3. **For each bucket, export descendant classes:**
```bash
# Create buckets directory
mkdir -p buckets_qid

# For each bucket QID (e.g., Q115095765)
tdb2.tdbquery --loc working.nosync/jena \
  --query=queries/bucket_descendants.rq \
  --results=TSV \
  | grep "http://www.wikidata.org/entity" \
  > buckets_qid/Q115095765.tsv
```

Example query (`queries/bucket_descendants.rq`):
```sparql
PREFIX wdt: <http://www.wikidata.org/prop/direct/>
PREFIX wd:  <http://www.wikidata.org/entity/>

SELECT DISTINCT ?class
WHERE {
  ?class (wdt:P279|wdt:P361)+ wd:Q115095765 .
}
```

4. **Verify buckets:**
```bash
# Count classes per bucket
for f in buckets_qid/*.tsv; do
  echo "$f: $(wc -l < $f) classes"
done

# Check for overlaps (expected!)
cat buckets_qid/*.tsv | sort | uniq -d | wc -l
```

## Troubleshooting

### Problem: "Buckets directory not found"
**Solution:**
```bash
mkdir -p buckets_qid
# Generate bucket files using SPARQL queries above
```

### Problem: Out of memory during Jena loading
**Solution:**
```bash
export JENA_JAVA_OPTS="-Xmx64g -XX:ParallelGCThreads=16"
make working.nosync/jena/tdb2_loaded
```

### Problem: Slow partitioning (Step 3)
**Solution:**
```bash
# Reduce parallelism
make working.nosync/concept_backbone.nt JOBS=8

# Or check sitelinks file is sorted
LC_ALL=C sort -c source.nosync/sitelinks_en_qids.tsv
```

### Problem: Invalid triples in output
**Solution:**
```bash
# Check for malformed lines
grep -v "^<.*> <.*> <.*> \.$" wikicore-YYYYMMDD-en.nt

# Validate N-Triples syntax
riot --validate wikicore-YYYYMMDD-en.nt
```

### Problem: Missing labels in output
**Solution:**
```bash
# Check labels were extracted
wc -l working.nosync/skos/skos_labels_en.nt

# Verify locale matches
ls source.nosync/wikidata-*-skos-labels-*.nt.gz

# Rebuild with correct locale
make clean
make all LOCALE=en
```

## Performance Tips

### Faster Processing
1. **Use SSD storage** for working.nosync/
2. **Increase parallelism** if you have RAM: `JOBS=32`
3. **Pre-sort sitelinks file:**
   ```bash
   LC_ALL=C sort -o source.nosync/sitelinks_en_qids.tsv \
     source.nosync/sitelinks_en_qids.tsv
   ```

### Memory Optimization
1. **Reduce Jena heap** if constrained: `JENA_JAVA_OPTS="-Xmx16g"`
2. **Process fewer chunks:** `JOBS=8`
3. **Monitor memory usage:**
   ```bash
   watch -n 1 free -h
   ```

### Disk Space Management
1. **Monitor space:**
   ```bash
   du -sh working.nosync/
   du -sh source.nosync/
   ```

2. **Clean intermediate files:**
   ```bash
   rm -rf working.nosync/splits/
   rm -rf working.nosync/subjects/*_subjects.tsv
   ```

3. **Compress old outputs:**
   ```bash
   pigz wikicore-20260101-en.nt
   ```

## Statistics and Analysis

### Count Concepts
```bash
grep -c "skos:Concept" wikicore-YYYYMMDD-en.nt
```

### Count Labels
```bash
grep -c "skos:prefLabel" wikicore-YYYYMMDD-en.nt
```

### Count Broader Relations
```bash
grep -c "skos:broader" wikicore-YYYYMMDD-en.nt
```

### Top-Level Concepts (no broader)
```bash
# Get all concepts
grep "skos:Concept" wikicore-YYYYMMDD-en.nt | cut -d' ' -f1 | sort -u > all_concepts.txt

# Get all concepts with broader
grep "skos:broader" wikicore-YYYYMMDD-en.nt | cut -d' ' -f1 | sort -u > has_broader.txt

# Find top-level (no broader)
comm -23 all_concepts.txt has_broader.txt > top_level.txt
wc -l top_level.txt
```

### Bucket Statistics
```bash
echo "Bucket Statistics:"
echo "=================="
for f in working.nosync/subjects/*_subjects.tsv; do
  bucket=$(basename $f _subjects.tsv)
  count=$(wc -l < $f)
  printf "%-20s %10d instances\n" "$bucket" "$count"
done | sort -k2 -rn
```

### Depth Analysis
```bash
# Query Jena for depth statistics
cat > queries/depth_analysis.rq << 'EOF'
PREFIX wdt: <http://www.wikidata.org/prop/direct/>

SELECT ?depth (COUNT(?concept) AS ?count)
WHERE {
  ?concept wdt:P279+ ?root .
  ?concept wdt:P279{1,10} ?root .
  BIND(STRLEN(REPLACE(str(?path), "[^/]", "")) AS ?depth)
}
GROUP BY ?depth
ORDER BY ?depth
EOF

tdb2.tdbquery --loc working.nosync/jena \
  --query=queries/depth_analysis.rq
```

## Environment Setup

### Recommended .bashrc / .zshrc
```bash
# Wiki Core environment
export WIKICORE_ROOT="$HOME/projects/wikicore"
export JENA_HOME="/path/to/apache-jena-5.0.0"
export PATH="$JENA_HOME/bin:$PATH"
export JENA_JAVA_OPTS="-Xmx32g -XX:ParallelGCThreads=$(nproc)"

# Locale settings for proper sorting
export LC_ALL=C

# Aliases
alias wc-build='cd $WIKICORE_ROOT && make all'
alias wc-verify='cd $WIKICORE_ROOT && make verify'
alias wc-clean='cd $WIKICORE_ROOT && make clean'
```

## Data Download

### Wikidata Dumps
```bash
# Visit: https://dumps.wikimedia.org/wikidatawiki/entities/
# Download latest:
# - wikidata-YYYYMMDD-all.nt.gz (or -truthy.nt.gz)
# Or filtered: wikidata-YYYYMMDD-propdirect.nt.gz

wget https://dumps.wikimedia.org/wikidatawiki/entities/latest-all.nt.gz
```

### SKOS Labels
```bash
# These are generated from Wikidata dumps
# Or download from: https://www.wikidata.org/wiki/Wikidata:Database_download

# Labels are in the main dump, extract with:
pigz -dc latest-all.nt.gz | \
  rg -F 'www.w3.org/2004/02/skos/core#prefLabel' | \
  rg -F '@en' > wikidata-YYYYMMDD-skos-labels-en.nt
```

### Sitelinks
```bash
# Generate from Wikidata JSON dumps or SPARQL
# Format: One QID per line (full URI)

# Example generation from JSON dump:
jq -r 'select(.sitelinks.enwiki) | 
  "<http://www.wikidata.org/entity/\(.id)>"' \
  wikidata-YYYYMMDD-all.json.gz | \
  LC_ALL=C sort -u > sitelinks_en_qids.tsv
```

## Help

### Get Makefile Help
```bash
make help
```

### Check Setup
```bash
bash setup_check.sh
```

### Full Documentation
See `README_WORKFLOW.md` for complete pipeline documentation.
