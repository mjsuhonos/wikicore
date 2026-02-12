#!/usr/bin/env python3
"""
partition_all_chunks.py
Single-pass: extract backbone (P279, P361) AND bucket subjects (P31)
WITH early sitelinks filtering

Usage:
    python3 partition_all_chunks.py <chunks_dir> <buckets_dir> <sitelinks_file> <backbone_out> <subjects_dir>
"""

import sys
from pathlib import Path
from collections import defaultdict

if len(sys.argv) != 6:
    print(__doc__)
    sys.exit(1)

chunks_dir = Path(sys.argv[1])
buckets_dir = Path(sys.argv[2])
sitelinks_file = Path(sys.argv[3])
backbone_out = Path(sys.argv[4])
subjects_dir = Path(sys.argv[5])

subjects_dir.mkdir(exist_ok=True, parents=True)
backbone_out.parent.mkdir(exist_ok=True, parents=True)

# --------------------------------------------------
# 1. Load sitelinks (early filter)
# --------------------------------------------------
print("Loading sitelinks...")
sitelinks = set()

with sitelinks_file.open() as f:
    for line in f:
        qid = line.strip().split()[0]  # Assumes format: <http://...entity/Q123>
        sitelinks.add(qid)

print(f"  Loaded {len(sitelinks)} items with sitelinks")

# --------------------------------------------------
# 2. Load buckets
# --------------------------------------------------
print("Loading buckets and building class->bucket map...")

buckets = {}
for bucket_file in sorted(buckets_dir.glob("*.tsv")):
    bucket_name = bucket_file.stem
    with bucket_file.open() as f:
        buckets[bucket_name] = set(line.strip() for line in f if line.strip())
    print(f"  Loaded bucket {bucket_name}: {len(buckets[bucket_name])} classes")

class_to_buckets = defaultdict(list)
for bucket_name, class_set in buckets.items():
    for class_uri in class_set:
        class_to_buckets[class_uri].append(bucket_name)

print(f"Total buckets: {len(buckets)}")
print(f"Total unique classes: {len(class_to_buckets)}")

# --------------------------------------------------
# 3. Prepare subject storage
# --------------------------------------------------
subjects = {bucket: set() for bucket in buckets}
subjects["P31_other"] = set()

# --------------------------------------------------
# 4. Process all chunks
# --------------------------------------------------
P31_PRED = "<http://www.wikidata.org/prop/direct/P31>"
P279_PRED = "<http://www.wikidata.org/prop/direct/P279>"
P361_PRED = "<http://www.wikidata.org/prop/direct/P361>"

backbone_count = 0
p31_count = 0
p31_filtered_count = 0
p31_other_count = 0

print("\nProcessing chunks...")

with backbone_out.open("w") as backbone_f:
    for chunk_file in sorted(chunks_dir.glob("chunk_*")):
        print(f"  Processing {chunk_file.name}")
        chunk_p31 = 0
        chunk_p31_kept = 0
        chunk_backbone = 0

        with chunk_file.open() as f:
            for line in f:
                line = line.strip()
                if not line:
                    continue

                parts = line.split(" ", 3)
                if len(parts) < 3:
                    continue

                subj, pred, obj = parts[:3]

                # P31: instance-of -> bucket subjects (WITH SITELINKS FILTER)
                if pred == P31_PRED:
                    chunk_p31 += 1
                    p31_count += 1
                    
                    # EARLY FILTER: only process items with sitelinks
                    if subj not in sitelinks:
                        p31_filtered_count += 1
                        continue
                    
                    chunk_p31_kept += 1
                    bucket_list = class_to_buckets.get(obj)
                    
                    if bucket_list:
                        for bucket in bucket_list:
                            subjects[bucket].add(subj)
                    else:
                        subjects["P31_other"].add(subj)
                        p31_other_count += 1

                # P279/P361: subclass/part-of -> backbone (NO FILTER)
                elif pred == P279_PRED or pred == P361_PRED:
                    backbone_f.write(line + "\n")
                    chunk_backbone += 1
                    backbone_count += 1

        print(f"    P31: {chunk_p31} total, {chunk_p31_kept} kept ({chunk_p31-chunk_p31_kept} filtered)")
        print(f"    Backbone: {chunk_backbone}")

print(f"\nSummary:")
print(f"  Total P31 triples: {p31_count}")
print(f"  P31 filtered (no sitelink): {p31_filtered_count}")
print(f"  P31 kept: {p31_count - p31_filtered_count}")
print(f"  P31_other (uncategorized): {p31_other_count}")
print(f"  Total backbone triples: {backbone_count}")

# --------------------------------------------------
# 5. Write subject files
# --------------------------------------------------
print("\nWriting subject files...")

for bucket_name, items in sorted(subjects.items()):
    if not items:
        continue
    
    out_file = subjects_dir / f"{bucket_name}_subjects.tsv"
    with out_file.open("w") as out:
        for item in sorted(items):
            out.write(item + "\n")
    
    print(f"  {bucket_name}: {len(items)} items")

print(f"\nDone! Generated {len([s for s in subjects.values() if s])} non-empty subject files.")
print(f"Backbone written to: {backbone_out}")