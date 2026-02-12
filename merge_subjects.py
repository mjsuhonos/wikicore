#!/usr/bin/env python3
"""
merge_subjects.py
Merge per-chunk subject files into one final file per bucket.
Usage:
    python3 merge_subjects.py subjects subjects_final
"""

import sys
from pathlib import Path
from collections import defaultdict

input_dir = Path(sys.argv[1])       # e.g., 'subjects' or 'subjects_merged'
output_dir = Path(sys.argv[2])      # e.g., 'subjects_final'
output_dir.mkdir(exist_ok=True)

# dictionary: {bucket_name: set(items)}
bucket_items = defaultdict(set)

# iterate over all per-chunk files
for f in input_dir.glob("*.tsv"):
    bucket_name = f.stem  # filename without .tsv
    with f.open() as fh:
        for line in fh:
            item = line.strip()
            if item:
                bucket_items[bucket_name].add(item)

# write merged & deduplicated files
for bucket, items in bucket_items.items():
    out_file = output_dir / f"{bucket}.tsv"
    with out_file.open("w") as fh:
        for item in sorted(items):
            fh.write(item + "\n")
