#!/usr/bin/env python3
"""Generate a shell script with direct annif commands."""

import argparse
import os
import re
from pathlib import Path
from typing import List, Dict

def get_fulltext_file_path(vocab: str, suffix: str, fulltext_dir: Path) -> Path:
    """Construct fulltext file path based on vocab name and suffix."""
    splits_dir = fulltext_dir / "splits"
    
    # Construct the expected filename based on vocab name
    # Remove prefixes and use the base name
    vocab_base = vocab
    if vocab_base.startswith("class-"):
        vocab_base = vocab_base[6:]  # Remove "class-" prefix
    elif vocab_base.startswith("occ-"):
        vocab_base = vocab_base[4:]  # Remove "occ-" prefix
    
    # Construct the expected filename pattern
    if suffix:
        filename = f"wikicore-*-{vocab_base}-*.{suffix}.tsv"
    else:
        filename = f"wikicore-*-{vocab_base}-*.tsv"
    
    # Look for the file in the splits directory
    matches = list(splits_dir.glob(filename))
    
    if matches:
        return matches[0]
    
    # If not found, return a path that likely exists based on the pattern
    # This handles the case where we need to construct the path explicitly
    return splits_dir / f"wikicore-*-{vocab_base}-*.{suffix}.tsv" if suffix else splits_dir / f"wikicore-*-{vocab_base}-*.tsv"

def get_vocab_dir(vocab: str) -> str:
    """Get vocabulary directory based on vocab name."""
    if "class-" in vocab:
        return "classes"
    elif "occ-" in vocab:
        return "occupations"
    return ""

def get_vocab_filename(vocab: str) -> str:
    """Get vocabulary filename based on vocab name."""
    if vocab.startswith("class-"):
        return vocab.replace("class-", "")
    elif vocab.startswith("occ-"):
        return vocab.replace("occ-", "")
    return vocab

def process_project(project: str, backend: str, vocab: str, fulltext_dir: Path, output_lines: List[str]):
    """Process a project and generate train/eval commands."""
    # Get file paths
    train_file = get_fulltext_file_path(vocab, "train", fulltext_dir)
    eval_file = get_fulltext_file_path(vocab, "eval", fulltext_dir)
    if not eval_file.exists():
        eval_file = get_fulltext_file_path(vocab, "test", fulltext_dir)
    if not eval_file.exists():
        eval_file = get_fulltext_file_path(vocab, "", fulltext_dir)
    
    output_lines.append(f"echo 'Processing {project} ({backend})...'")
    
    # MLLM projects: train then evaluate
    if train_file:
        output_lines.append(f"echo '  Training MLLM project...'")
        output_lines.append(f"annif train '{project}' '{train_file}'")
    else:
        output_lines.append(f"echo '  Warning: No training data for {project}'")
    
    if eval_file:
        output_lines.append(f"echo '  Evaluating MLLM project...'")
        project_slug = project.replace(" ", "_")
        output_lines.append(f"annif eval '{project}' '{eval_file}' -M 'data/eval/{project_slug}.json'")
    else:
        output_lines.append(f"echo '  Warning: No evaluation data for {project}'")
    
    output_lines.append("")

def parse_project_file(project_file: Path, fulltext_dir: Path) -> List[str]:
    """Parse project file and generate commands."""
    output_lines = []
    
    # First pass: load vocabularies
    with open(project_file, 'r') as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            
            if line.startswith("vocab"):
                match = re.match(r'vocab\s*=\s*(.+)', line)
                if match:
                    vocab = match.group(1).strip()
                    vocab_dir = get_vocab_dir(vocab)
                    vocab_file = get_vocab_filename(vocab)
                    
                    # Build vocabulary path
                    vocabs_base_dir = fulltext_dir.parent
                    vocab_path = vocabs_base_dir
                    if vocab_dir:
                        vocab_path = vocab_path / vocab_dir
                    vocab_path = vocab_path / f"{vocab_file}.nt"
                    
                    output_lines.append(f"echo '  Loading vocabulary: {vocab}'")
                    output_lines.append(f"annif load-vocab '{vocab}' '{vocab_path}'")
    
    output_lines.append("")
    
    # Second pass: process projects
    project = ""
    backend = ""
    vocab = ""
    
    with open(project_file, 'r') as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            
            # Section header
            section_match = re.match(r'\[(.+)\]', line)
            if section_match:
                # Process previous project if complete
                if project and backend and vocab:
                    process_project(project, backend, vocab, fulltext_dir, output_lines)
                
                project = section_match.group(1)
                backend = ""
                vocab = ""
            elif line.startswith("backend"):
                match = re.match(r'backend\s*=\s*(.+)', line)
                if match:
                    backend = match.group(1).strip()
            elif line.startswith("vocab"):
                match = re.match(r'vocab\s*=\s*(.+)', line)
                if match:
                    vocab = match.group(1).strip()
    
    # Process last project
    if project and backend and vocab:
        process_project(project, backend, vocab, fulltext_dir, output_lines)
    
    return output_lines

def main():
    parser = argparse.ArgumentParser(description="Generate a shell script with direct annif commands")
    parser.add_argument("--date", required=True, help="Build date (YYYYMMDD)")
    parser.add_argument("--lang", required=True, help="Language code (e.g. en, de)")
    parser.add_argument("--annif-dir", required=True, help="Path to annif directory")
    parser.add_argument("--fulltext-dir", required=True, help="Path to fulltext directory")
    parser.add_argument("--output-script", required=True, help="Output script path")
    args = parser.parse_args()
    
    # Create output directory
    output_script = Path(args.output_script)
    output_script.parent.mkdir(parents=True, exist_ok=True)
    
    # Start generating the command script
    output_lines = [
        "#!/bin/bash",
        "set -e",
        "echo 'Starting Annif training and evaluation...'",
        ""
    ]
    
    annif_dir = Path(args.annif_dir)
    fulltext_dir = Path(args.fulltext_dir)
    
    # Process all project files
    project_files = list(annif_dir.glob("projects_*.cfg"))
    
    if not project_files:
        print(f"No project files found in {annif_dir}")
        return
    
    for project_file in project_files:
        print(f"Processing {project_file.name}...")
        project_lines = parse_project_file(project_file, fulltext_dir)
        output_lines.extend(project_lines)
    
    # Finish the script
    output_lines.append("echo 'Annif processing completed!'")
    
    # Write output script
    with open(output_script, 'w') as f:
        f.write('\n'.join(output_lines))
    
    # Make the generated script executable
    os.chmod(output_script, 0o755)
    
    print(f"Generated Annif command script: {output_script}")
    print(f"You can run it with: ./{output_script.name}")

if __name__ == "__main__":
    main()