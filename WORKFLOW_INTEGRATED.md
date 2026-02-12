# Wiki Core Complete Workflow

## Overview

This pipeline builds the Wiki Core vocabulary from Wikidata with **automatic bucket discovery**. The key improvement is that buckets are generated from the data itself rather than requiring manual pre-creation.

## Complete Pipeline (10 Steps)

### Phase 1: Data Preparation
**Step 1: Extract Core Properties**
```bash
make working.nosync/wikidata-core-props-P31-P279-P361.nt
```
- Extracts P31 (instance-of), P279 (subclass-of), P361 (part-of)
- Removes blank nodes
- Output: ~150GB, ~100M triples

**Step 2: Split Into Chunks**
```bash
make working.nosync/splits/.split_done
```
- Splits into JOBS chunks (default: CPU cores)
- Enables parallel processing
- Output: splits/chunk_*

### Phase 2: Backbone & Discovery
**Step 3: Extract Backbone Only**
```bash
make working.nosync/concept_backbone.nt
```
- Extracts ONLY P279 and P361 (subclass, part-of)
- Does NOT process P31 instances yet
- Output: concept_backbone.nt (~30M triples)

**Step 4: Load Into Jena**
```bash
make working.nosync/jena/tdb2_loaded
```
- Loads complete backbone into TDB2
- Creates queryable RDF database
- Output: jena/ directory

**Step 5: Materialize & Export**
```bash
make working.nosync/core_concepts_qids.tsv
```
- Materializes transitive closure (ancestors)
- Computes child counts
- Exports all core concepts
- Output: core_concepts_qids.tsv

### Phase 3: Bucket Generation
**Step 6: Generate Buckets** 🆕
```bash
make buckets_qid/.buckets_done
```
- **Discovers** top-level buckets from root entity (default: Q35120)
- **Queries** for descendant classes of each bucket
- **Generates** bucket files automatically
- Output: buckets_qid/*.tsv (e.g., Q115095765.tsv, Q13196193.tsv, etc.)

**How it works:**
1. SPARQL query: "Find entities 1-2 hops from Q35120" → ~23 buckets
2. For each bucket: "Find all descendant classes" → class lists
3. Write to buckets_qid/<QID>.tsv

**Customization:**
```bash
make buckets_qid/.buckets_done ROOT_QID=Q16521  # Use different root
```

### Phase 4: Instance Partitioning
**Step 7: Partition Instances**
```bash
make working.nosync/subjects/.partition_done
```
- Goes back to chunks
- Extracts P31 (instance-of) triples
- Filters by sitelinks (Wikipedia articles only)
- Assigns instances to buckets
- Output: subjects/Q*_subjects.tsv, subjects/P31_other_subjects.tsv

**Optimization:** Sitelinks filtering reduces data by ~50% (116M → 60M)

**Step 8: Sort & Merge**
```bash
make working.nosync/core_nosubject_qids.tsv
```
- Sorts each bucket file
- Merges all buckets
- Removes subjects from concepts list
- Output: core_nosubject_qids.tsv

### Phase 5: SKOS Generation
**Step 9: Generate SKOS Components**
```bash
make working.nosync/skos/
```
- Extracts labels
- Generates concept statements
- Generates broader relations
- Generates concept scheme
- Output: skos/*.nt files

**Step 10: Final Merge**
```bash
make wikicore-YYYYMMDD-en.nt
```
- Merges all SKOS components
- Creates final vocabulary
- Output: wikicore-YYYYMMDD-en.nt (~5GB)

## Key Improvements

### 1. Automatic Bucket Discovery
**Before:** Manually create bucket files
**After:** Buckets discovered automatically from data

### 2. Two-Phase Processing
**Phase A (Steps 1-6):** Build backbone → Generate buckets
**Phase B (Steps 7-10):** Partition instances → Generate SKOS

### 3. Customizable Root
```bash
# Default: Q35120 (entity)
make all

# Custom root: Q16521 (taxon)
make all ROOT_QID=Q16521

# Custom root: Q2695156 (chemical compound)
make all ROOT_QID=Q2695156
```

### 4. Separation of Concerns
- **extract_backbone.py** - Extracts P279/P361 only
- **generate_buckets.py** - Discovers buckets via SPARQL
- **partition_instances.py** - Partitions P31 into buckets

## Complete Workflow Diagram

```
Input Data
  ↓
[1] Extract P31/P279/P361
  ↓
[2] Split into chunks
  ↓
[3] Extract backbone (P279/P361)
  ↓
[4] Load into Jena
  ↓
[5] Materialize ancestors
  ↓
[6] Generate buckets ←── Discovery happens here!
  ↓
[7] Partition instances (P31) using buckets
  ↓
[8] Sort & filter
  ↓
[9] Generate SKOS
  ↓
[10] Final vocabulary
```

## Files and Scripts

### Scripts
1. **extract_backbone.py** - Extracts P279/P361 from chunks
2. **generate_buckets.py** - Discovers and generates bucket files
3. **partition_instances.py** - Partitions P31 instances into buckets

### SPARQL Queries
1. **discover_buckets.rq** - Find top-level buckets from root
2. **bucket_descendants_template.rq** - Get descendants of a bucket
3. **materialize_ancestors.rq** - Compute transitive closure
4. **materialize_child_counts.rq** - Count descendants
5. **export.rq** - Export core concepts

### Generated Files
- **buckets_qid/*.tsv** - Bucket definitions (auto-generated)
- **concept_backbone.nt** - Complete class hierarchy
- **subjects/*_subjects.tsv** - Instances per bucket
- **wikicore-YYYYMMDD-en.nt** - Final vocabulary

## Running the Pipeline

### Full Build (Recommended)
```bash
make all
```
This runs all 10 steps automatically.

### Step-by-Step (for Debugging)
```bash
make working.nosync/wikidata-core-props-P31-P279-P361.nt  # Step 1
make working.nosync/splits/.split_done                     # Step 2
make working.nosync/concept_backbone.nt                    # Step 3
make working.nosync/jena/tdb2_loaded                       # Step 4
make working.nosync/core_concepts_qids.tsv                 # Step 5
make buckets_qid/.buckets_done                             # Step 6
make working.nosync/subjects/.partition_done               # Step 7
make working.nosync/core_nosubject_qids.tsv                # Step 8
make working.nosync/skos/                                  # Step 9
make wikicore-YYYYMMDD-en.nt                               # Step 10
```

### With Custom Root
```bash
# Discover buckets from Q16521 (taxon) instead of Q35120 (entity)
make all ROOT_QID=Q16521
```

### With Custom Settings
```bash
make all LOCALE=fr JOBS=32 ROOT_QID=Q35120
```

## Verification

```bash
# Check pipeline status
make verify

# Check bucket files
ls -lh buckets_qid/*.tsv
for f in buckets_qid/*.tsv; do
  echo "$f: $(wc -l < $f) classes"
done

# Check instance distribution
for f in working.nosync/subjects/*_subjects.tsv; do
  bucket=$(basename $f _subjects.tsv)
  count=$(wc -l < $f)
  printf "%-20s %10d instances\n" "$bucket" "$count"
done | sort -k2 -rn
```

### Workflow
```
1. Extract properties
2. Split chunks
3. Extract backbone
4. Load into Jena
5. Materialize
6. ✅ Auto-discover buckets
7. ✅ Auto-generate bucket files
8. Partition instances
9. Generate SKOS
10. Final output
```

## Benefits

1. **Fully Automated** - No manual SPARQL queries needed
2. **Reproducible** - Same root → same buckets
3. **Customizable** - Easy to try different root entities
4. **Self-Documenting** - Buckets tracked in version control
5. **Faster Iteration** - Regenerate buckets anytime

## Next Steps

After running the pipeline:

1. **Verify buckets:**
   ```bash
   ls buckets_qid/*.tsv
   cat buckets_qid/*.tsv | wc -l  # Total class assignments
   ```

2. **Inspect large buckets:**
   ```bash
   for f in buckets_qid/*.tsv; do
     echo "$(wc -l < $f) $f"
   done | sort -rn | head -10
   ```

3. **Sub-divide if needed:**
   - Large buckets (>1M instances) may need subdivision
   - Re-run with those buckets as new roots
   - Create hierarchical bucket structure

4. **Generate subject vocabularies:**
   ```bash
   make skos_subjects SUBJECTS="Q5 Q215627 Q488383"
   ```

## Troubleshooting

### No buckets found
**Cause:** Wrong root QID or backbone not materialized
**Solution:**
```bash
# Check materialization
make working.nosync/core_concepts_qids.tsv

# Try different root
make buckets_qid/.buckets_done ROOT_QID=Q16521
```

### Bucket generation fails
**Cause:** Jena not running or wrong path
**Solution:**
```bash
# Verify Jena
which tdb2.tdbquery
echo $JENA_JAVA_OPTS

# Check database
ls working.nosync/jena/
```

### Empty bucket files
**Cause:** No descendants found or query error
**Solution:** Check SPARQL query syntax in queries/bucket_descendants_template.rq

## Summary

The integrated bucket generation makes Wiki Core a **fully automated pipeline** that:
- Discovers semantic structure from data
- Generates buckets automatically
- Allows experimentation with different roots
- Produces reproducible results

**Key command:**
```bash
make all ROOT_QID=Q35120  # Build entire vocabulary with auto-discovered buckets
```
