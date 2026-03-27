#!/usr/bin/env python3
"""
Create class group .nt files by combining existing SKOS files.
"""

import os
import sys
from pathlib import Path

def create_class_group_nt(class_name, skos_dir, output_dir, locale="en"):
    """Create a class group .nt file by combining SKOS files."""
    # Read class TSV file
    class_file = f"classes/{class_name}.tsv"
    with open(class_file, 'r') as f:
        qids = [line.strip().split()[0] for line in f if line.strip()]
    
    # Collect all existing SKOS files
    skos_files = []
    for qid in qids:
        for file_type in ['concepts', 'concept_scheme', f'labels_{locale}', 'broader']:
            skos_file = f"{skos_dir}/skos_{qid}_{file_type}.nt"
            if os.path.exists(skos_file):
                skos_files.append(skos_file)
    
    # Create output file
    output_file = f"{output_dir}/wikicore-{os.environ.get('RUN_DATE', 'unknown')}-{class_name}-{locale}.nt"
    os.makedirs(os.path.dirname(output_file), exist_ok=True)
    
    with open(output_file, 'w') as out_f:
        for skos_file in skos_files:
            with open(skos_file, 'r') as in_f:
                out_f.write(in_f.read())
    print(f"Generated {output_file}")

if __name__ == "__main__":
    if len(sys.argv) < 4:
        print("Usage: create_class_group_nt.py <class_name> <skos_dir> <output_dir> [locale]")
        sys.exit(1)
    
    class_name = sys.argv[1]
    skos_dir = sys.argv[2]
    output_dir = sys.argv[3]
    locale = sys.argv[4] if len(sys.argv) > 4 else "en"
    
    create_class_group_nt(class_name, skos_dir, output_dir, locale)