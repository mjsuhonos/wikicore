#!/usr/bin/env python3
"""
generate_buckets.py
Generate bucket files from the Jena TDB2 database.

This script:
1. Queries Jena to discover top-level buckets (from root entity)
2. For each bucket, queries to get all descendant classes
3. Writes bucket files to buckets_qid/*.tsv

Usage:
    python3 generate_buckets.py <jena_dir> <queries_dir> <buckets_dir> [root_qid]

Arguments:
    jena_dir     Path to Jena TDB2 database directory
    queries_dir  Path to directory containing SPARQL queries
    buckets_dir  Output directory for bucket files
    root_qid     Root entity QID (default: Q35120)
"""

import sys
import subprocess
from pathlib import Path
import re

if len(sys.argv) < 4:
    print(__doc__)
    sys.exit(1)

jena_dir = Path(sys.argv[1])
queries_dir = Path(sys.argv[2])
buckets_dir = Path(sys.argv[3])
root_qid = sys.argv[4] if len(sys.argv) > 4 else "Q35120"

if not jena_dir.exists():
    print(f"Error: Jena directory not found: {jena_dir}")
    sys.exit(1)

if not queries_dir.exists():
    print(f"Error: Queries directory not found: {queries_dir}")
    sys.exit(1)

buckets_dir.mkdir(exist_ok=True, parents=True)

print("=" * 60)
print("Generating Bucket Files from Jena Database")
print("=" * 60)
print(f"Jena database: {jena_dir}")
print(f"Root entity:   {root_qid}")
print(f"Output dir:    {buckets_dir}")
print()

# Step 1: Discover buckets
print("Step 1: Discovering top-level buckets...")
print("-" * 60)

discover_query = queries_dir / "discover_buckets.rq"

# Read and customize query with root QID
with discover_query.open() as f:
    query_text = f.read()
    query_text = query_text.replace("wd:Q35120", f"wd:{root_qid}")

# Write temporary query file
temp_query = queries_dir / "temp_discover_buckets.rq"
with temp_query.open("w") as f:
    f.write(query_text)

# Run query
try:
    result = subprocess.run(
        [
            "tdb2.tdbquery",
            "--loc", str(jena_dir),
            "--query", str(temp_query),
            "--results=TSV"
        ],
        capture_output=True,
        text=True,
        check=True
    )
    
    # Parse bucket QIDs from output
    buckets = []
    for line in result.stdout.strip().split('\n'):
        line = line.strip()
        if not line or line.startswith('?'):  # Skip header
            continue
        
        # Extract QID from URI
        match = re.search(r'entity/(Q\d+)', line)
        if match:
            buckets.append(match.group(1))
    
    print(f"Found {len(buckets)} top-level buckets:")
    for bucket in buckets:
        print(f"  - {bucket}")
    print()

finally:
    temp_query.unlink(missing_ok=True)

if not buckets:
    print("Warning: No buckets found!")
    print("Check your root QID and ensure the backbone has been materialized.")
    sys.exit(1)

# Step 2: For each bucket, get descendant classes
print("Step 2: Generating descendant classes for each bucket...")
print("-" * 60)

template_query = queries_dir / "bucket_descendants_template.rq"

with template_query.open() as f:
    template_text = f.read()

for i, bucket_qid in enumerate(buckets, 1):
    print(f"[{i}/{len(buckets)}] Processing {bucket_qid}...")
    
    # Customize query for this bucket
    query_text = template_text.replace("BUCKET_QID", bucket_qid)
    
    # Write temporary query
    temp_query = queries_dir / f"temp_bucket_{bucket_qid}.rq"
    with temp_query.open("w") as f:
        f.write(query_text)
    
    # Run query
    try:
        result = subprocess.run(
            [
                "tdb2.tdbquery",
                "--loc", str(jena_dir),
                "--query", str(temp_query),
                "--results=TSV"
            ],
            capture_output=True,
            text=True,
            check=True
        )
        
        # Parse class URIs from output
        classes = []
        for line in result.stdout.strip().split('\n'):
            line = line.strip()
            if not line or line.startswith('?'):  # Skip header
                continue
            
            # Extract full URI
            match = re.search(r'<(http://www\.wikidata\.org/entity/Q\d+)>', line)
            if match:
                classes.append(match.group(1))
        
        # Write bucket file
        bucket_file = buckets_dir / f"{bucket_qid}.tsv"
        with bucket_file.open("w") as f:
            for class_uri in sorted(set(classes)):
                f.write(f"<{class_uri}>\n")
        
        print(f"  → {len(classes)} classes written to {bucket_file.name}")
    
    finally:
        temp_query.unlink(missing_ok=True)

print()
print("=" * 60)
print("Bucket Generation Complete!")
print("=" * 60)
print(f"Generated {len(buckets)} bucket files in {buckets_dir}")
print()

# Summary statistics
total_classes = 0
for bucket_file in sorted(buckets_dir.glob("*.tsv")):
    count = sum(1 for _ in bucket_file.open())
    total_classes += count
    print(f"  {bucket_file.stem}: {count:,} classes")

print()
print(f"Total unique class assignments: {total_classes:,}")
print("(Note: Classes may appear in multiple buckets)")
print()
print("Next step: Run partitioning to assign instances to buckets")
