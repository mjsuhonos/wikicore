#!/usr/bin/env python3

import os
import gzip
import sys
import subprocess

def main():
    if len(sys.argv) != 5:
        print("Usage: fulltext_occ_qid.py <QID> <FULLTEXT_GZ> <SUBJECTS_DIR> <OUTPUT_FILE>")
        sys.exit(1)
    
    qid = sys.argv[1]
    fulltext_gz = sys.argv[2]
    subjects_dir = sys.argv[3]
    output_file = sys.argv[4]
    
    # Build mapping file
    subjects_file = os.path.join(subjects_dir, f"{qid}_subjects.tsv")
    map_file = f"/tmp/fulltext_occ_qid_{qid}_map.tsv"
    
    if os.path.exists(subjects_file):
        with open(subjects_file, 'r') as f:
            with open(map_file, 'w') as out:
                for line in f:
                    # Remove URI formatting
                    clean_qid = line.strip().replace('<http://www.wikidata.org/entity/', '').replace('>', '')
                    out.write(f"{clean_qid}\t{qid}\n")
    else:
        # Create empty map file
        open(map_file, 'w').close()
    
    # Check if map file has content
    if os.path.getsize(map_file) > 0:
        # Process fulltext
        with gzip.open(fulltext_gz, 'rt') as f:
            with open(map_file, 'r') as map_f:
                # Read QIDs to look for
                qids_to_find = set()
                for line in map_f:
                    parts = line.strip().split('\t')
                    if len(parts) >= 1:
                        qids_to_find.add(parts[0])
        
        # Process fulltext file
        with gzip.open(fulltext_gz, 'rt') as f:
            with open(output_file, 'w') as out:
                for line in f:
                    parts = line.strip().split('\t', 1)
                    if len(parts) >= 2:
                        qid_in_file = parts[0]
                        text = parts[1]
                        if qid_in_file in qids_to_find:
                            out.write(f"{text}\t<http://www.wikidata.org/entity/{qid_in_file}>\n")
    else:
        # Create empty output file
        open(output_file, 'w').close()
    
    # Clean up
    if os.path.exists(map_file):
        os.remove(map_file)

if __name__ == "__main__":
    main()