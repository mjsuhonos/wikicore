#!/usr/bin/env python3
"""
partition_chunks.py
Split input N-Triples chunks into backbone and per-class subjects.
Usage:
    partition_chunks.py <chunk_file> <class_names_file> <tmp_dir> <subjects_dir>
"""

import sys
from pathlib import Path

chunk_file = Path(sys.argv[1])
class_file = Path(sys.argv[2])
TMP_DIR = Path(sys.argv[3])
SUBJECTS_DIR = Path(sys.argv[4])

# Load class names
class_names = {}
with open(class_file) as f:
    for line in f:
        parts = line.strip().split("\t")
        if len(parts) >= 2:
            qid, name = parts[:2]
            class_names[qid] = name

subjects = {}  # {qid: set(subjects)}
backbone_buffer = []
BUFFER_SIZE = 10000

TMP_DIR.mkdir(parents=True, exist_ok=True)
SUBJECTS_DIR.mkdir(parents=True, exist_ok=True)

def flush_backbone(buf):
    if buf:
        with open(TMP_DIR / "concept_backbone.nt", "a") as f:
            f.writelines(buf)
        buf.clear()

with open(chunk_file) as f:
    for line in f:
        line = line.strip()
        if not line:
            continue
        try:
            subj, pred, obj, dot = line.split(" ", 3)
        except ValueError:
            print(f"ERROR: Malformed line (cannot split into 4 parts): {line}", file=sys.stderr)
            sys.exit(1)

        if pred.endswith("P31>"):
            qid = obj.strip("<>")
            qid = qid.split("/")[-1]

            if qid in class_names:
                subjects.setdefault(qid, set()).add(subj)
            else:
                subjects.setdefault("P31_other", set()).add(subj)
            
        else:
            if subj.startswith("<") and pred.startswith("<") and (obj.startswith("<") or obj.startswith('"')):
                backbone_buffer.append(line + "\n")
                if len(backbone_buffer) >= BUFFER_SIZE:
                    flush_backbone(backbone_buffer)
            else:
                print(f"ERROR: Malformed backbone triple: {line}", file=sys.stderr)
                sys.exit(1)
            
flush_backbone(backbone_buffer)

# Write subjects
for qid, subs in subjects.items():
    if qid == "P31_other":
        out_file = SUBJECTS_DIR / "P31_other.subjects.tsv"
    else:
        out_file = SUBJECTS_DIR / f"{qid}_subjects.tsv"
    with open(out_file, "a") as f:
        for s in sorted(subs):
            f.write(s + "\n")
