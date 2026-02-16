#!/usr/bin/env python3
"""
Group Q5 (human) subjects by occupation groups defined in occupations/*.tsv,
using P106 triples from working.nosync/wikidata-P106-sitelinks.nt.

Output: working.nosync/subjects/Q5_{group}_subjects.tsv for each occupation group,
        plus Q5_other_subjects.tsv for subjects with no matching occupation.
"""

import os
import re
from collections import defaultdict

OCCUPATIONS_DIR = "occupations"
NT_FILE = "working.nosync/wikidata-P106-sitelinks.nt"
SUBJECTS_FILE = "working.nosync/subjects/Q5_subjects.tsv"
OUTPUT_DIR = "working.nosync/subjects"

# 1. Load occupation QID -> group mapping
occ_to_group = {}
groups = []
for fname in sorted(os.listdir(OCCUPATIONS_DIR)):
    if not fname.endswith(".tsv"):
        continue
    group = fname[:-4]  # strip .tsv
    groups.append(group)
    with open(os.path.join(OCCUPATIONS_DIR, fname)) as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            qid = line.split("\t")[0]
            # First group wins (no override)
            if qid not in occ_to_group:
                occ_to_group[qid] = group

print(f"Loaded {len(occ_to_group)} occupation QIDs across {len(groups)} groups")

# 2. Load all subjects into a set for fast lookup
# Subjects are URIs like <http://www.wikidata.org/entity/Q1000005>
subjects = set()
with open(SUBJECTS_FILE) as f:
    for line in f:
        line = line.strip()
        if line:
            subjects.add(line)

print(f"Loaded {len(subjects)} subjects")

# Extract QID from URI like <http://www.wikidata.org/entity/Q123>
uri_re = re.compile(r'<http://www\.wikidata\.org/entity/(Q\d+)>')

def uri_to_qid(uri):
    m = uri_re.match(uri)
    return m.group(1) if m else None

def qid_to_uri(qid):
    return f"<http://www.wikidata.org/entity/{qid}>"

# 3. Parse NT file and assign subjects to groups
# Each line: <subject> <P106> <occupation> .
# A subject can have multiple occupations -> assign to all matching groups
subject_groups = defaultdict(set)

p106_uri = "<http://www.wikidata.org/prop/direct/P106>"

print(f"Parsing NT file...")
with open(NT_FILE) as f:
    for i, line in enumerate(f):
        if i % 500000 == 0:
            print(f"  {i:,} lines...")
        line = line.strip()
        if not line or not p106_uri in line:
            continue
        parts = line.split(" ")
        if len(parts) < 3:
            continue
        subj_uri = parts[0]
        occ_uri = parts[2]
        if subj_uri not in subjects:
            continue
        occ_qid = uri_to_qid(occ_uri)
        if occ_qid and occ_qid in occ_to_group:
            subject_groups[subj_uri].add(occ_to_group[occ_qid])

print(f"Found occupation matches for {len(subject_groups)} subjects")

# 4. Write output files
# For subjects with multiple group matches, write to each group file
group_counts = defaultdict(int)
other_count = 0

# Open all output files
out_files = {}
for group in groups:
    path = os.path.join(OUTPUT_DIR, f"Q5_{group}_subjects.tsv")
    out_files[group] = open(path, "w")

other_path = os.path.join(OUTPUT_DIR, "Q5_unmatched_subjects.tsv")
other_file = open(other_path, "w")

for subj_uri in subjects:
    grps = subject_groups.get(subj_uri)
    if grps:
        for g in grps:
            out_files[g].write(subj_uri + "\n")
            group_counts[g] += 1
    else:
        other_file.write(subj_uri + "\n")
        other_count += 1

for f in out_files.values():
    f.close()
other_file.close()

print("\nResults:")
for group in groups:
    print(f"  {group}: {group_counts[group]:,}")
print(f"  unmatched: {other_count:,}")
print("Done.")
