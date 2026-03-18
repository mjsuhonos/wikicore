#!/usr/bin/env python3
"""
Group Q5 (human) subjects by occupation groups defined in occupations/*.tsv,
using P106 triples from working.nosync/wikidata-P106-sitelinks.nt.

Output: working.nosync/subjects/Q5_{group}_subjects.tsv for each occupation group,
        plus Q5_unmatched_subjects.tsv for subjects with no matching occupation,
        and optionally {QID}_subjects.tsv for each individual occupation QID.
"""

import os
import re
import argparse
from collections import defaultdict

# Parse command line arguments
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--core-only', action='store_true',
                    help='Only create files needed for core processing (skip per-QID subject files)')
parser.add_argument('nt_file', nargs='?', default="working.nosync/wikidata-P106-sitelinks.nt",
                    help='NT file to process (default: working.nosync/wikidata-P106-sitelinks.nt)')
args = parser.parse_args()

OCCUPATIONS_DIR = "occupations"
NT_FILE = args.nt_file
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

# 3. Parse NT file and assign subjects to groups and individual QIDs
# Each line: <subject> <P106> <occupation> .
# A subject can have multiple occupations -> assign to all matching groups/QIDs
subject_groups = defaultdict(set)
qid_subjects = defaultdict(set)  # occupation QID -> set of subject URIs

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
            qid_subjects[occ_qid].add(subj_uri)

print(f"Found occupation matches for {len(subject_groups)} subjects")

# 4. Write output files
# For subjects with multiple group matches, write to each group file
group_counts = defaultdict(int)
other_count = 0

# Write group files (sorted for downstream join compatibility)
for group in groups:
    path = os.path.join(OUTPUT_DIR, f"Q5_{group}_subjects.tsv")
    group_subjs = sorted(
        subj_uri for subj_uri in subjects
        if group in subject_groups.get(subj_uri, set())
    )
    with open(path, "w") as f:
        for subj_uri in group_subjs:
            f.write(subj_uri + "\n")
    group_counts[group] = len(group_subjs)

# Write unmatched subjects file (sorted)
other_path = os.path.join(OUTPUT_DIR, "Q5_unmatched_subjects.tsv")
with open(other_path, "w") as f:
    for subj_uri in sorted(subj_uri for subj_uri in subjects if not subject_groups.get(subj_uri)):
        f.write(subj_uri + "\n")
        other_count += 1

# Write per-QID subject files (sorted, replaces per-QID grep in Makefile)
# Only create these if not in core-only mode
if not args.core_only:
    qid_count = 0
    for occ_qid, occ_subjs in qid_subjects.items():
        path = os.path.join(OUTPUT_DIR, f"{occ_qid}_subjects.tsv")
        with open(path, "w") as f:
            for subj_uri in sorted(occ_subjs):
                f.write(subj_uri + "\n")
        qid_count += 1

    print(f"Wrote {qid_count} per-QID subject files")
    
    # Write manifest of active occupation QIDs (only those with ≥1 subject),
    # so the Makefile can filter build targets rather than attempting to process
    # QIDs that have no Q5 humans in the data.
    active_qids_path = os.path.join(os.path.dirname(OUTPUT_DIR), "active_occ_qids.txt")
    with open(active_qids_path, "w") as f:
        for occ_qid in sorted(qid_subjects.keys()):
            f.write(occ_qid + "\n")
    print(f"Wrote active QID manifest: {active_qids_path}")
else:
    print("Skipped per-QID subject files (core-only mode)")

print("\nResults:")
for group in groups:
    print(f"  {group}: {group_counts[group]:,}")
print(f"  unmatched: {other_count:,}")
print("Done.")
