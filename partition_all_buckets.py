#!/usr/bin/env python3
"""
partition_all_buckets.py
Assign all instances from a chunk to 23 buckets in memory.
"""

import sys
from pathlib import Path
from collections import defaultdict

chunk_file = Path(sys.argv[1])
buckets_dir = Path(sys.argv[2])  # buckets_qid/
output_dir = Path(sys.argv[3])
output_dir.mkdir(exist_ok=True)

# Load all buckets into memory
buckets = {}
for f in buckets_dir.glob("*.tsv"):
    bucket_name = f.stem
    buckets[bucket_name] = set()
    with f.open() as fh:
        for line in fh:
            qid = line.strip()
            if qid:
                buckets[bucket_name].add(qid)

# prepare storage for assigned subjects
subjects = defaultdict(set)  # {bucket_name: set(subject QIDs)}

# process the chunk once
with chunk_file.open() as f:
    for line in f:
        parts = line.strip().split(" ")
        if len(parts) < 3:
            continue
        subj, pred, obj = parts[:3]

        if pred.endswith("P31>"):
            # keep full URI for subject
            for bucket_name, class_qids in buckets.items():
                obj_qid = obj.split("/")[-1].strip("><")
                if obj_qid in class_qids:
                    subjects[bucket_name].add(subj)
            # catch any P31 not in buckets
            subjects["P31_other"].add(subj)

# write results
for bucket_name, items in subjects.items():
    out_file = output_dir / f"{bucket_name}_subjects.tsv"
    with out_file.open("a") as fh:
        for s in sorted(items):
            fh.write(s + "\n")
