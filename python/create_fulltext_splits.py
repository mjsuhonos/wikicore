#!/usr/bin/env python3
"""Create train/test/eval splits for all fulltext TSV files."""

import argparse
import os
import re
import random
from pathlib import Path
from typing import List

def find_tsv_files(fulltext_dir: Path) -> List[Path]:
    """Find all fulltext TSV files, excluding individual QID files."""
    tsv_files = []
    
    # Find all TSV files in fulltext directory (excluding splits subdirectory)
    for file in fulltext_dir.rglob("*.tsv"):
        if "/splits/" in str(file):
            continue
            
        base_name = file.name
        
        # Include files that start with "wikicore-" but DON'T contain "-Q" followed by numbers
        # This excludes individual QID group files like "wikicore-20260321-Q12345-en.tsv"
        if base_name.startswith("wikicore-"):
            if re.search(r'-Q\d+', base_name):
                print(f"  Excluding individual QID group file: {base_name}")
            elif base_name.startswith("Q"):
                print(f"  Excluding QID file: {base_name}")
            else:
                print(f"  Including: {base_name}")
                tsv_files.append(file)
        else:
            print(f"  Excluding non-wikicore file: {base_name}")
    
    return tsv_files

def create_splits(tsv_file: Path, splits_dir: Path):
    """Create train/test/eval splits for a single TSV file."""
    base_name = tsv_file.stem
    
    # Read all lines
    with open(tsv_file, 'r', encoding='utf-8') as f:
        lines = f.readlines()
    
    if not lines:
        print(f"  Warning: Empty file {tsv_file}")
        return
    
    # Shuffle lines
    random.shuffle(lines)
    
    # Calculate split points
    total_lines = len(lines)
    train_lines = int(total_lines * 0.8)
    test_lines = int(total_lines * 0.9)
    
    # Write splits
    train_file = splits_dir / f"{base_name}.train.tsv"
    test_file = splits_dir / f"{base_name}.test.tsv"
    eval_file = splits_dir / f"{base_name}.eval.tsv"
    
    with open(train_file, 'w', encoding='utf-8') as f:
        f.writelines(lines[:train_lines])
    
    with open(test_file, 'w', encoding='utf-8') as f:
        f.writelines(lines[train_lines:test_lines])
    
    with open(eval_file, 'w', encoding='utf-8') as f:
        f.writelines(lines[test_lines:])
    
    print(f"  Created splits: {train_file.name}, {test_file.name}, {eval_file.name}")

def main():
    parser = argparse.ArgumentParser(description="Create train/test/eval splits for all fulltext TSV files")
    parser.add_argument("--locale", required=True, help="Language locale (e.g., en, de)")
    parser.add_argument("--fulltext-dir", required=True, help="Full path to the fulltext directory")
    args = parser.parse_args()
    
    # Use the explicitly provided fulltext directory
    actual_fulltext_dir = Path(args.fulltext_dir)
    
    if not actual_fulltext_dir.exists():
        print(f"Error: Fulltext directory not found: {actual_fulltext_dir}")
        print("Available fulltext directories:")
        for dir in root_dir.rglob("fulltext"):
            if dir.is_dir():
                print(f"  {dir}")
        exit(1)
    
    print(f"Using fulltext directory: {actual_fulltext_dir}")
    
    splits_dir = actual_fulltext_dir / "splits"
    splits_dir.mkdir(parents=True, exist_ok=True)
    
    # Find all fulltext TSV files
    print(f"Finding wikicore group TSV files in {actual_fulltext_dir}...")
    tsv_files = find_tsv_files(actual_fulltext_dir)
    
    if not tsv_files:
        print("No fulltext TSV files found")
        exit(1)
    
    print(f"\nFound {len(tsv_files)} group files to process:")
    for file in tsv_files:
        print(f"  - {file.name}")
    print()
    
    print(f"Creating train/test/eval splits for {len(tsv_files)} files...")
    
    # Process each file
    for tsv_file in tsv_files:
        print(f"Processing {tsv_file.name}...")
        
        # Get relative path to maintain directory structure
        rel_path = tsv_file.parent.relative_to(actual_fulltext_dir)
        split_dir = splits_dir / rel_path if rel_path != Path(".") else splits_dir
        split_dir.mkdir(parents=True, exist_ok=True)
        
        create_splits(tsv_file, split_dir)
    
    print(f"\nCompleted splitting {len(tsv_files)} files into {splits_dir}")

if __name__ == "__main__":
    main()