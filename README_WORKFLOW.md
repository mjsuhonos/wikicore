# Wiki Core Processing Pipeline

This document describes the complete workflow for building the Wiki Core vocabulary from Wikidata.

## Overview

Wiki Core is built through a 10-step pipeline that:
1. Extracts relevant Wikidata relationships (P31, P279, P361)
2. Splits data for parallel processing
3. Extracts backbone (class hierarchy)
4. Loads backbone into Apache Jena
5. **Automatically discovers and generates buckets** via SPARQL
6. Partitions instances into buckets with early sitelinks filtering
7. Materializes transitive relationships
8. Filters concepts (removes instances)
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
- **Python 3** - for data partitioning scripts
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
├── partition_all_chunks.py       # Instance partitioning script
├── queries/                      # SPARQL queries
│   ├── materialize_ancestors.rq
│   ├── materialize_child_counts.rq
│   └── export.rq
├── buckets_qid/                  # Bucket definitions (generated)
│   ├── Q115095765.tsv
│   ├── Q13196193.tsv
│   └── ...
├── source.nosync/                # Input data (not in git)
│   ├── wikidata-YYYYMMDD-propdirect.nt.gz
│   ├── wikidata-YYYYMMDD-skos-labels-en.nt.gz
│   └── sitelinks_en_qids.tsv
└── working.nosync/               # Working files (not in git)
    ├── wikidata-core-props-P31-P279-P361.nt
    ├── concept_backbone.nt
    ├── splits/
    ├── subjects/
    ├── jena/
    └── skos/
```

## Pipeline Workflow

### Phase 1: Data Preparation

#### Step 1: Extract Core Properties
```bash
make working.nosync/wikidata-core-props-P31-P279-P361.nt
```

**What it does:**
- Decompresses the Wikidata dump
- Filters for three key properties:
  - **P31** (instance of) - links items to their classes
  - **P279** (subclass of) - builds class hierarchy
  - **P361** (part of) - compositional relationships
- Removes blank nodes (invalid references)

**Output:** `wikidata-core-props-P31-P279-P361.nt` (~150GB, ~100M triples)

#### Step 2: Split Into Chunks
```bash
make working.nosync/splits/.split_done
```

**What it does:**
- Splits the large file into equal-sized chunks
- Number of chunks = `JOBS` (default: number of CPU cores)
- Enables parallel processing

**Output:** `splits/chunk_aa`, `splits/chunk_ab`, ... (~32 files)

#### Step 3: Extract Backbone Only
```bash
make working.nosync/backbone_only.nt
```

**What it does:**
- Extracts **only** P279 (subclass) and P361 (part-of) relationships from chunks
- Does NOT partition instances yet (that happens after bucket generation in Step 6)
- Creates complete class hierarchy graph

**Output:** `backbone_only.nt` - All subclass/part-of relationships (~30M triples)

### Phase 2: Semantic Graph Discovery & Bucket Generation

#### Step 4: Load Into Jena
```bash
make working.nosync/jena/tdb2_loaded
```

**What it does:**
- Loads the complete backbone into Apache Jena TDB2
- Creates a queryable RDF database
- Enables SPARQL queries for discovery

**Output:** `jena/` directory with TDB2 database files

#### Step 5: Generate Buckets (Automatic)
```bash
make working.nosync/buckets_qid/.buckets_generated
```

**What it does:**
1. **Discovers top-level buckets** - Queries Jena for classes 1-2 hops from root entity (default: Q35120)
2. **For each bucket, finds all descendants** - Queries for all classes via transitive P279/P361 relationships
3. **Generates bucket files** - Creates `buckets_qid/Q*.tsv` with full URIs of classes

**Critical notes:**
- Buckets are **automatically generated** if they don't exist
- To regenerate buckets: `make generate_buckets` or `make regenerate_buckets`
- Can customize root entity: `make all ROOT_QID=Q488383` (use "object" instead of "entity")
- Buckets **can overlap** - a class may appear in multiple buckets

**Output:**
- `buckets_qid/.buckets_generated` - Marker file
- `buckets_qid/Q115095765.tsv` - Bucket files (one per top-level class)
- Each bucket file contains full URIs: `<http://www.wikidata.org/entity/Q123>`

**Required SPARQL queries:**
- `queries/discover_buckets.rq` - Find top-level buckets from root
- `queries/bucket_descendants.rq` - Find all descendant classes for a bucket

**Script:**
- `generate_buckets.py` - Python script that runs SPARQL queries and generates files

#### Step 6: Partition Instances Into Buckets
```bash
make working.nosync/concept_backbone.nt
```

**What it does:**
- **Single-pass processing** of all chunks:
  - Extracts P31 (instance-of) → **bucketed subjects**
  - Re-extracts P279/P361 (subclass/part-of) → **concept_backbone.nt** (for final output)
- **Early sitelinks filtering**: Only keeps instances with Wikipedia articles
- Assigns instances to buckets based on their classes (using the bucket files from Step 5)

**Critical optimization:** This step filters by sitelinks immediately, reducing instance data by ~50% (116M → 60M items)

**Output:**
- `concept_backbone.nt` - Complete class hierarchy (final version for SKOS output)
- `subjects/Q*_subjects.tsv` - Instances per bucket (~24 files)
- `subjects/P31_other_subjects.tsv` - Uncategorized instances

### Phase 3: Vocabulary Materialization

#### Step 7: Materialize and Export
```bash
make working.nosync/concept_backbone.nt
```

**What it does:**
- **Single-pass processing** of all chunks:
  - Extracts P279 (subclass) and P361 (part-of) → **backbone**
  - Extracts P31 (instance-of) → **bucketed subjects**
- **Early sitelinks filtering**: Only keeps instances with Wikipedia articles
- Assigns instances to buckets based on their classes

**Critical optimization:** This step filters by sitelinks immediately, reducing instance data by ~50% (116M → 60M items)

**Output:**
- `concept_backbone.nt` - Complete class hierarchy (~30M triples)
- `subjects/Q*_subjects.tsv` - Instances per bucket (~24 files)
- `subjects/P31_other_subjects.tsv` - Uncategorized instances

### Phase 3: Vocabulary Materialization

#### Step 7: Materialize and Export
```bash
make working.nosync/core_concepts_qids.tsv
```

**What it does:**
1. **Materialize ancestors** - Computes transitive closure of P279/P361
2. **Materialize child counts** - Counts descendants for each class
3. **Export core concepts** - Extracts all classes that meet criteria

**Output:** `core_concepts_qids.tsv` - List of core concept QIDs

### Phase 4: Final Filtering & SKOS Generation

#### Step 8: Filter and Sort
```bash
make working.nosync/core_nosubject_qids.tsv
```

**What it does:**
1. Sorts and deduplicates each bucket's subjects
2. Merges all buckets into single sorted list
3. **Removes subjects from concepts** - Classes that appear as instances are excluded

**Why this matters:** We want concepts (classes), not instances, in our vocabulary. For example, "human" (Q5) is a concept, but "Albert Einstein" (instance of Q5) is not.

**Output:** `core_nosubject_qids.tsv` - Final filtered concept list

#### Step 9: Generate SKOS
```bash
make working.nosync/skos/
```

**What it does:**
Generates four SKOS components:

1. **skos_concepts.nt** - Type declarations
   ```turtle
   <http://www.wikidata.org/entity/Q123> <rdf:type> <skos:Concept> .
   ```

2. **skos_concept_scheme.nt** - Vocabulary metadata
   ```turtle
   <https://wikicore.ca/20260209> <rdf:type> <skos:ConceptScheme> .
   <http://www.wikidata.org/entity/Q123> <skos:inScheme> <https://wikicore.ca/20260209> .
   ```

3. **skos_labels_en.nt** - Multilingual labels
   ```turtle
   <http://www.wikidata.org/entity/Q123> <skos:prefLabel> "example"@en .
   ```

4. **skos_broader.nt** - Hierarchical relationships
   ```turtle
   <http://www.wikidata.org/entity/Q456> <skos:broader> <http://www.wikidata.org/entity/Q123> .
   ```

#### Step 10: Merge Final Output
```bash
make wikicore-YYYYMMDD-en.nt
```

**What it does:**
- Concatenates all SKOS components
- Creates final publishable vocabulary

**Output:** `wikicore-20260209-en.nt` - Complete SKOS vocabulary

## Bucket Discovery Workflow

Buckets are **automatically generated** during the pipeline (Step 5) by querying the loaded backbone in Jena.

### How Automatic Bucket Generation Works

When you run `make all`, the pipeline:

1. **Loads the complete backbone** into Jena (Step 4)
2. **Queries for top-level buckets** (Step 5)
   - Finds classes 1-2 hops from a root entity via P279/P361
   - Default root: Q35120 (entity)
3. **For each bucket, discovers all descendant classes**
   - Queries for all classes reachable via transitive P279/P361
4. **Generates bucket files** automatically
   - Creates `buckets_qid/Q*.tsv` files
   - Each contains full URIs of classes in that bucket

### Customizing Bucket Generation

**Change the root entity:**
```bash
# Use Q488383 (object) as root instead of Q35120 (entity)
make all ROOT_QID=Q488383

# Use Q2424752 (abstract object) for a more focused vocabulary
make all ROOT_QID=Q2424752
```

**Force regenerate buckets:**
```bash
# Regenerate buckets with current settings
make regenerate_buckets

# Regenerate with different root
make regenerate_buckets ROOT_QID=Q488383
```

**Check what buckets will be generated:**
```bash
# After Step 4 (loading Jena), manually run:
tdb2.tdbquery --loc working.nosync/jena \
  --query=queries/discover_buckets.rq \
  --results=TSV
```

### Bucket Properties

- **Not disjoint** - Classes can appear in multiple buckets (overlap is expected and allowed)
- **Full URIs** - Each line contains complete `<http://www.wikidata.org/entity/QXXX>` format
- **No headers** - One URI per line
- **File naming** - `<QID>.tsv` where QID is the bucket's Wikidata ID
- **Automatic detection** - If buckets exist, they won't be regenerated unless forced

### SPARQL Query Templates

The bucket generation uses two SPARQL queries:

**1. `queries/discover_buckets.rq`** - Find top-level buckets:
```sparql
PREFIX wdt: <http://www.wikidata.org/prop/direct/>
PREFIX wd:  <http://www.wikidata.org/entity/>

SELECT DISTINCT ?bucket
WHERE {
  ?bucket (wdt:P279|wdt:P361){1,2} wd:Q35120 .
}
ORDER BY ?bucket
```

**2. `queries/bucket_descendants.rq`** - Find descendant classes:
```sparql
PREFIX wdt: <http://www.wikidata.org/prop/direct/>
PREFIX wd:  <http://www.wikidata.org/entity/>

SELECT DISTINCT ?class
WHERE {
  ?class (wdt:P279|wdt:P361)+ wd:BUCKET_QID .
}
ORDER BY ?class
```

### Manual Bucket Creation (Advanced)

If you need more control over bucket selection, you can manually create bucket files before running the pipeline:

1. **Choose a root concept** (e.g., Q35120 - entity)

2. **Query for top-level buckets** (1-2 hops from root):
   ```sparql
   PREFIX wdt: <http://www.wikidata.org/prop/direct/>
   PREFIX wd:  <http://www.wikidata.org/entity/>
   
   SELECT DISTINCT ?bucket
   WHERE {
     ?bucket (wdt:P279|wdt:P361){1,2} wd:Q35120 .
   }
   ```

3. **For each bucket, find all descendant classes:**
   ```sparql
   PREFIX wdt: <http://www.wikidata.org/prop/direct/>
   PREFIX wd:  <http://www.wikidata.org/entity/>
   
   SELECT DISTINCT ?class
   WHERE {
     ?class (wdt:P279|wdt:P361)+ wd:Q115095765 .
   }
   ```

4. **Export to bucket files:**
   ```bash
   mkdir -p buckets_qid
   
   # For each bucket Q123, create buckets_qid/Q123.tsv with full URIs:
   echo "<http://www.wikidata.org/entity/Q456>" >> buckets_qid/Q123.tsv
   echo "<http://www.wikidata.org/entity/Q789>" >> buckets_qid/Q123.tsv
   ```

### Bucket Properties

- **Not disjoint** - Classes can appear in multiple buckets
- **Full URIs** - Must use complete `<http://www.wikidata.org/entity/QXXX>` format
- **No headers** - One URI per line
- **File naming** - `<QID>.tsv` where QID is the bucket's Wikidata ID

## Usage

### Build Complete Vocabulary
```bash
make all
```

### Build with Custom Settings
```bash
make all LOCALE=fr JOBS=32
```

### Build Subject-Specific Vocabularies
```bash
# Build vocabulary for Q5 (human)
make skos_subjects SUBJECTS=Q5

# Build multiple subject vocabularies
make skos_subjects SUBJECTS="Q5 Q215627 Q488383"
```

### Verify Output
```bash
make verify
```

### Clean Working Files
```bash
make clean        # Remove working files only
make clean-all    # Remove working files and outputs
```

## Performance Tuning

### Memory Requirements
- **Minimum**: 32GB RAM for Jena
- **Recommended**: 64GB RAM for large datasets
- Set via: `export JENA_JAVA_OPTS="-Xmx64g"`

### Parallel Processing
- **Default**: Uses all CPU cores (`nproc`)
- **Custom**: `make all JOBS=16`
- **Trade-off**: More jobs = faster but more memory

### Disk Space
- **Source data**: ~150GB compressed, ~550GB uncompressed
- **Working files**: ~200GB
- **Final output**: ~5GB
- **Total**: ~800GB recommended

## Optimization Summary

### Early Sitelinks Filtering (Step 3)
**Before optimization:**
- Process all 116M P31 triples
- Store all instances in memory
- Filter at the end (Step 6)

**After optimization:**
- Process 116M P31 triples
- **Filter immediately** - only keep 60M with sitelinks
- 50% memory reduction
- Faster sorts and joins downstream

### Why We Don't Filter the Backbone
The backbone (P279/P361 relationships) is kept complete because:
1. Need full class hierarchy even for classes without articles
2. Example: Q1 ↔ Q2 ↔ Q3. If Q2 has no article but Q1 and Q3 do, we still need Q2
3. Backbone is much smaller than instances (millions vs billions)

## Troubleshooting

### Error: "Buckets directory not found"
**Solution:** Create bucket files first using the SPARQL workflow above.

### Error: "tdb2.tdbloader: command not found"
**Solution:** Install Apache Jena and add to PATH:
```bash
export PATH=/path/to/jena/bin:$PATH
```

### Error: "Out of memory"
**Solution:** Increase Jena heap size:
```bash
export JENA_JAVA_OPTS="-Xmx64g -XX:ParallelGCThreads=16"
```

### Slow processing on Step 3
**Solution:**
- Reduce JOBS if memory constrained: `make all JOBS=8`
- Use faster storage (SSD preferred)
- Ensure sitelinks file is sorted

### Verification failures
**Solution:** Run verification to identify issues:
```bash
make verify
```

Check:
- Backbone has both P279 and P361 triples
- Subject files are non-empty
- Final output has all 4 SKOS components

## File Format Reference

### N-Triples Format
```
<subject> <predicate> <object> .
```

Example:
```turtle
<http://www.wikidata.org/entity/Q5> <http://www.w3.org/prop/direct/P279> <http://www.wikidata.org/entity/Q35120> .
```

### TSV Format (Sitelinks)
```
<http://www.wikidata.org/entity/Q5>
<http://www.wikidata.org/entity/Q42>
```

### TSV Format (Subjects)
```
<http://www.wikidata.org/entity/Q937>
<http://www.wikidata.org/entity/Q1339>
```

## Development Notes

### Adding New Languages
1. Download SKOS labels for target language
2. Update `LOCALE` variable: `make all LOCALE=fr`
3. Ensure sitelinks file exists for that language

### Modifying Bucket Structure
1. Update SPARQL queries to discover different buckets
2. Regenerate bucket files
3. Clean and rebuild: `make clean && make all`

### Custom Materialization Rules
Edit SPARQL update queries in `queries/`:
- `materialize_ancestors.rq` - Transitive closure rules
- `materialize_child_counts.rq` - Counting logic
- `export.rq` - Concept selection criteria

## License

Wiki Core is licensed under GPLv3. See LICENSE for details.

## References

- [Wikidata](https://www.wikidata.org/)
- [SKOS Specification](https://www.w3.org/TR/skos-reference/)
- [Apache Jena](https://jena.apache.org/)
- [Library of Congress Subject Headings](https://www.loc.gov/aba/cataloging/subject/)
