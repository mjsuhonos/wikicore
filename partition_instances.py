#!/usr/bin/env python3
"""
partition_instances.py
Partition P31 (instance-of) relationships into buckets with early sitelinks filtering.

This script only processes P31 triples. The backbone (P279/P361) was already extracted
in a separate step.

Usage:
    python3 partition_instances.py <chunks_dir> <buckets_dir> <sitelinks_file> <subjects_dir>

Arguments:
    chunks_dir      Directory containing chunk_*.nt files
    buckets_dir     Directory containing bucket QID files (buckets_qid/*.tsv)
    sitelinks_file  TSV file with Wikipedia sitelinks (QIDs with articles)
    subjects_dir    Output directory for per-bucket subjects TSV
"""

import sys
from pathlib import Path
from collections import defaultdict

if len(sys.argv) != 5:
    print(__doc__)
    sys.exit(1)

chunks_dir = Path(sys.argv[1])
buckets_dir = Path(sys.argv[2])
sitelinks_file = Path(sys.argv[3])
subjects_dir = Path(sys.argv[4])

subjects_dir.mkdir(exist_ok=True, parents=True)

# --------------------------------------------------
# 1. Load sitelinks (early filter)
# --------------------------------------------------
print("Loading sitelinks...")
sitelinks = set()

with sitelinks_file.open() as f:
    for line in f:
        qid = line.strip().split()[0]  # Assumes format: <http://...entity/Q123>
        sitelinks.add(qid)

print(f"  Loaded {len(sitelinks):,} items with sitelinks")
print()

# --------------------------------------------------
# 2. Load buckets
# --------------------------------------------------
print("Loading buckets and building class->bucket map...")

buckets = {}
for bucket_file in sorted(buckets_dir.glob("*.tsv")):
    bucket_name = bucket_file.stem
    with bucket_file.open() as f:
        buckets[bucket_name] = set(line.strip() for line in f if line.strip())
    print(f"  Loaded bucket {bucket_name}: {len(buckets[bucket_name]):,} classes")

class_to_buckets = defaultdict(list)
for bucket_name, class_set in buckets.items():
    for class_uri in class_set:
        class_to_buckets[class_uri].append(bucket_name)

print(f"Total buckets: {len(buckets)}")
print(f"Total unique classes: {len(class_to_buckets):,}")
print()

# --------------------------------------------------
# 3. Prepare subject storage
# --------------------------------------------------
subjects = {bucket: set() for bucket in buckets}
subjects["P31_other"] = set()

# --------------------------------------------------
# 4. Process all chunks - P31 ONLY
# --------------------------------------------------
P31_PRED = "<http://www.wikidata.org/prop/direct/P31>"

p31_total = 0
p31_filtered = 0
p31_kept = 0
p31_other = 0

print("Processing chunks (P31 instances only)...")

for chunk_file in sorted(chunks_dir.glob("chunk_*")):
    print(f"  Processing {chunk_file.name}")
    chunk_p31 = 0
    chunk_kept = 0

    with chunk_file.open() as f:
        for line in f:
            line = line.strip()
            if not line:
                continue

            parts = line.split(" ", 3)
            if len(parts) < 3:
                continue

            subj, pred, obj = parts[:3]

            # ONLY process P31 (instance-of)
            if pred != P31_PRED:
                continue
            
            chunk_p31 += 1
            p31_total += 1
            
            # EARLY FILTER: only process items with sitelinks
            if subj not in sitelinks:
                p31_filtered += 1
                continue
            
            chunk_kept += 1
            p31_kept += 1
            
            # Check which bucket(s) this class belongs to
            bucket_list = class_to_buckets.get(obj)
            
            if bucket_list:
                # Add subject to all matching buckets
                for bucket in bucket_list:
                    subjects[bucket].add(subj)
            else:
                # Uncategorized
                subjects["P31_other"].add(subj)
                p31_other += 1

    print(f"    P31: {chunk_p31:,} total, {chunk_kept:,} kept ({chunk_p31-chunk_kept:,} filtered)")

print()
print("Summary:")
print(f"  Total P31 triples:           {p31_total:,}")
print(f"  Filtered (no sitelink):      {p31_filtered:,}")
print(f"  Kept (with sitelink):        {p31_kept:,}")
print(f"  Uncategorized (P31_other):   {p31_other:,}")
print()

# --------------------------------------------------
# 5. Write subject files
# --------------------------------------------------
print("Writing subject files...")

files_written = 0
total_items = 0

for bucket_name, items in sorted(subjects.items()):
    if not items:
        continue
    
    out_file = subjects_dir / f"{bucket_name}_subjects.tsv"
    with out_file.open("w") as out:
        for item in sorted(items):
            out.write(item + "\n")
    
    files_written += 1
    total_items += len(items)
    print(f"  {bucket_name}: {len(items):,} items")

print()
print("=" * 60)
print(f"Done! Generated {files_written} non-empty subject files.")
print(f"Total items across all buckets: {total_items:,}")
print("(Note: Items may appear in multiple buckets)")
print("=" * 60)
