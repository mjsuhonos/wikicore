#!/usr/bin/env python3
"""
Split fulltext for a specific group without creating individual QID files.

This script creates a single fulltext TSV file for a specific group by filtering
the fulltext GZ file for QIDs that belong to that group.
"""

import argparse
import gzip
import os
from collections import defaultdict


def parse_arguments():
    parser = argparse.ArgumentParser(description='Split fulltext for a specific group')
    parser.add_argument('--gz', required=True, help='Path to fulltext GZ file')
    parser.add_argument('--map', required=True, help='Path to instance QID map file')
    parser.add_argument('--group-qids', required=True, help='Path to file containing QIDs for this group')
    parser.add_argument('--out', required=True, help='Output TSV file path')
    parser.add_argument('--date', required=True, help='Run date (YYYYMMDD)')
    parser.add_argument('--locale', required=True, help='Locale (e.g., en)')
    return parser.parse_args()


def load_qid_map(map_file):
    """Load QID to group mapping."""
    qid_map = {}
    with open(map_file, 'r', encoding='utf-8') as f:
        for line in f:
            parts = line.strip().split('\t')
            if len(parts) >= 2:
                qid = parts[0]
                group_qid = parts[1]
                qid_map[qid] = group_qid
    return qid_map


def load_group_qids(group_qids_file):
    """Load QIDs that belong to this group."""
    group_qids = set()
    with open(group_qids_file, 'r', encoding='utf-8') as f:
        for line in f:
            parts = line.strip().split()
            if parts:
                group_qids.add(parts[0])
    return group_qids


def process_fulltext(gz_file, qid_map, group_qids, out_file):
    """Process fulltext GZ and create group file."""
    group_entries = defaultdict(list)
    
    with gzip.open(gz_file, 'rt', encoding='utf-8', errors='replace') as f:
        for line in f:
            # Format: QID\ttext
            parts = line.strip().split('\t', 1)
            if len(parts) >= 2:
                qid = parts[0]
                text = parts[1]
                
                # Check if this QID maps to one of our group QIDs
                if qid in qid_map:
                    mapped_qid = qid_map[qid]
                    if mapped_qid in group_qids:
                        group_entries[mapped_qid].append(f"{qid}\t{text}")
    
    # Write all entries to the output file
    os.makedirs(os.path.dirname(out_file), exist_ok=True)
    with open(out_file, 'w', encoding='utf-8') as f:
        for entries in group_entries.values():
            f.write('\n'.join(entries) + '\n')


def main():
    args = parse_arguments()
    
    print(f"Loading QID map from {args.map}")
    qid_map = load_qid_map(args.map)
    
    print(f"Loading group QIDs from {args.group_qids}")
    group_qids = load_group_qids(args.group_qids)
    
    print(f"Processing fulltext from {args.gz}")
    print(f"Creating group file {args.out}")
    process_fulltext(args.gz, qid_map, group_qids, args.out)
    
    print(f"Generated {args.out}")


if __name__ == '__main__':
    main()
