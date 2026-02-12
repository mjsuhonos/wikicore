#!/usr/bin/env python3
"""
extract_backbone.py
Extract ONLY P279 (subclass) and P361 (part-of) relationships from chunks.
This creates the backbone BEFORE we partition instances.

Usage:
    python3 extract_backbone.py <chunks_dir> <backbone_out>
"""

import sys
from pathlib import Path

if len(sys.argv) != 3:
    print(__doc__)
    sys.exit(1)

chunks_dir = Path(sys.argv[1])
backbone_out = Path(sys.argv[2])

backbone_out.parent.mkdir(exist_ok=True, parents=True)

P279_PRED = "<http://www.wikidata.org/prop/direct/P279>"
P361_PRED = "<http://www.wikidata.org/prop/direct/P361>"

backbone_count = 0

print("Extracting backbone from chunks...")

with backbone_out.open("w") as backbone_f:
    for chunk_file in sorted(chunks_dir.glob("chunk_*")):
        print(f"  Processing {chunk_file.name}")
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

                # Only P279 (subclass) and P361 (part-of)
                if pred == P279_PRED or pred == P361_PRED:
                    backbone_f.write(line + "\n")
                    chunk_backbone += 1
                    backbone_count += 1

        print(f"    Backbone triples: {chunk_backbone}")

print(f"\nTotal backbone triples: {backbone_count}")
print(f"Written to: {backbone_out}")
