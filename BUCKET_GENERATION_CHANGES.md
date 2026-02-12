# Bucket Generation Integration - Summary of Changes

## Pipeline

1. Extract core properties
2. Split into chunks
3. **Extract backbone** (NEW: only P279/P361, no partition yet)
4. Load into Jena
5. Materialize & export
6. **Generate buckets** (NEW: auto-discover from root entity)
7. **Partition instances** (NEW: separate step, was combined with #3)
8. Sort & filter
9. Generate SKOS
10. Final merge

## Files

### Scripts
- **extract_backbone.py** - Extract P279/P361 only
- **generate_buckets.py** - Auto-generate bucket files
- **partition_instances.py** - Partition P31 instances

### SPARQL (goes in queries/ directory)
- **discover_buckets.rq** - Find top-level buckets
- **bucket_descendants_template.rq** - Get bucket descendants

## Usage

### Default
```bash
make all  # Uses Q35120 as root
```

### Custom root
```bash
make all ROOT_QID=Q16521  # Use taxon as root
```

### Regenerate buckets
```bash
rm buckets_qid/.buckets_done
make buckets_qid/.buckets_done ROOT_QID=Q2695156
```

## Benefits

1. Fully automated - no manual SPARQL queries
2. Reproducible - same root → same buckets
3. Customizable - easy to try different roots
4. Faster - no manual steps

See WORKFLOW_INTEGRATED.md for complete documentation.
