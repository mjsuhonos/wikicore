#!/usr/bin/env python3
"""
partition_all_chunks.py
Efficiently assign instances from all N-triple chunks to multiple buckets in one pass.

Usage:
    python3 partition_all_chunks.py <chunks_dir> <buckets_dir> <output_dir>

Arguments:
    chunks_dir   Directory containing chunk_*.nt files
    buckets_dir  Directory containing bucket QID files (buckets_qid/*.tsv)
    output_dir   Directory to write final per-bucket subjects TSV
"""

import sys
from pathlib import Path
from collections import defaultdict

chunks_dir = Path(sys.argv[1])
buckets_dir = Path(sys.argv[2])
output_dir = Path(sys.argv[3])
output_dir.mkdir(exist_ok=True)

print("Loading buckets and building class->bucket map...")
# --------------------------------------------------
# 1. Load buckets (full URIs only)
# --------------------------------------------------

buckets = {}  # {bucket_name: set(class_uri_strings)}

for bucket_file in buckets_dir.glob("*.tsv"):
    bucket_name = bucket_file.stem  # e.g. Q488383
    class_uris = set()

    with bucket_file.open() as f:
        for line in f:
            line = line.strip()
            if line:
                class_uris.add(line)

    buckets[bucket_name] = class_uris

# Create reverse lookup: class_uri -> bucket_name
class_to_bucket = {}

for bucket_name, class_set in buckets.items():
    for class_uri in class_set:
        class_to_bucket[class_uri] = bucket_name

# --------------------------------------------------
# 2. Prepare subject storage
# --------------------------------------------------

subjects = {bucket: set() for bucket in buckets}
subjects["P31_other"] = set()

# --------------------------------------------------
# 3. Process all chunks exactly once
# --------------------------------------------------

for chunk_file in chunks_dir.glob("chunk_*"):
    print(f"Processing {chunk_file.name}")

    with chunk_file.open() as f:
        for line in f:
            line = line.strip()
            if not line:
                continue

            # Fast parse: subject predicate object .
            parts = line.split(" ", 3)
            if len(parts) < 3:
                continue

            subj, pred, obj = parts[:3]

            if pred != "<http://www.wikidata.org/prop/direct/P31>":
                continue

            bucket = class_to_bucket.get(obj)

            if bucket:
                subjects[bucket].add(subj)
            else:
                subjects["P31_other"].add(subj)

# --------------------------------------------------
# 4. Write exactly one file per bucket
# --------------------------------------------------

for bucket_name, items in subjects.items():
    out_file = output_dir / f"{bucket_name}_subjects.tsv"

    with out_file.open("w") as out:
        for item in sorted(items):
            out.write(item + "\n")

print("Done! Generated", len(subjects), "per-bucket subject files.")