#!/usr/bin/env python3
"""Generate Annif project .cfg files for WikiCore sub-vocabularies."""

import argparse
from pathlib import Path

SNOWBALL_MAP = {
    "en": "english",
    "de": "german",
    "fr": "french",
    "it": "italian",
    "fi": "finnish",
    "es": "spanish",
}

PROJECT_TEMPLATE = """\
# Vocab size: {vocab_size}
[wikicore_{lang}_mllm_{slug}]
name = WikiCore MLLM {label} ({lang})
backend = mllm
language = {lang}
analyzer=snowball({lang_name})
vocab=wikicore-{date}-{vocab_slug}-{lang}
limit=100
"""

def make_entry(lang, lang_name, date, slug, label, vocab_slug, vocab_size):
    return PROJECT_TEMPLATE.format(
        lang=lang,
        lang_name=lang_name,
        slug=slug,
        label=label,
        date=date,
        vocab_slug=vocab_slug,
        vocab_size=vocab_size,
    )

def write_cfg(path, entries):
    path.parent.mkdir(parents=True, exist_ok=True)
    with open(path, "w") as f:
        f.write("\n".join(entries))
        if entries:
            f.write("\n")
    print(f"Written {path} ({len(entries)} entries)")

def stem_names_from_dir(tsv_dir):
    """Return sorted list of stem names from *.tsv files in tsv_dir."""
    return sorted(p.stem for p in Path(tsv_dir).glob("*.tsv"))

def count_vocab_size(tsv_path):
    """Count the number of lines in a TSV file to determine vocabulary size."""
    with open(tsv_path, 'r') as f:
        return sum(1 for _ in f)

def count_class_group_size(classes_dir, subjects_dir, class_name):
    """Count total QIDs in a class group by summing up individual QID subjects files."""
    class_file = Path(classes_dir) / f"{class_name}.tsv"
    total = 0
    
    if class_file.exists():
        with open(class_file, 'r') as f:
            for line in f:
                qid = line.strip().split('\t')[0]
                subjects_file = Path(subjects_dir) / f"{qid}_subjects.tsv"
                if subjects_file.exists():
                    total += count_vocab_size(subjects_file)
    
    return total

def count_occ_group_size(occs_dir, subjects_dir, occ_name):
    """Count QIDs in an occupation group."""
    subjects_file = Path(subjects_dir) / f"Q5_{occ_name}_subjects.tsv"
    return count_vocab_size(subjects_file) if subjects_file.exists() else 0

def main():
    parser = argparse.ArgumentParser(description="Generate Annif project .cfg files")
    parser.add_argument("--date", required=True, help="Build date (YYYYMMDD)")
    parser.add_argument("--lang", required=True, help="Language code (e.g. en, de)")
    parser.add_argument("--subjects-dir", required=True, help="Path to subjects/ directory")
    parser.add_argument("--classes-dir", required=True, help="Path to classes/ directory")
    parser.add_argument("--occs-dir", required=True, help="Path to occupations/ directory")
    parser.add_argument("--outdir", required=True, help="Output directory for .cfg files")
    args = parser.parse_args()

    lang = args.lang
    lang_name = SNOWBALL_MAP.get(lang, lang)
    date = args.date
    outdir = Path(args.outdir)

    # --- core, unmatched, other ---
    core_size = count_vocab_size(Path(args.subjects_dir) / "core_subjects.tsv")
    
    # Count unmatched from occupations directory
    unmatched_size = 0
    for tsv_file in Path(args.occs_dir).glob("*.tsv"):
        unmatched_size += count_vocab_size(tsv_file)
    
    other_size = count_vocab_size(Path(args.subjects_dir) / "P31_other.subjects.tsv")
    
    entries = [
        make_entry(lang, lang_name, date, "core", "Core", "core", core_size),
        make_entry(lang, lang_name, date, "unmatched", "Unmatched", "unmatched", unmatched_size),
        make_entry(lang, lang_name, date, "other", "Other", "other", other_size)
    ]
    write_cfg(outdir / "projects_main.cfg", entries)

    # --- class groups ---
    entries = []
    for name in stem_names_from_dir(args.classes_dir):
        slug = f"class_{name}"
        vocab_slug = f"class-{name}"
        label = f"Class {name.capitalize()}"
        # Count total QIDs in this class group by summing individual QID subjects files
        vocab_size = count_class_group_size(args.classes_dir, args.subjects_dir, name)
        entries.append(make_entry(lang, lang_name, date, slug, label, vocab_slug, vocab_size))
    write_cfg(outdir / "projects_class.cfg", entries)

    # --- occ groups ---
    entries = []
    for name in stem_names_from_dir(args.occs_dir):
        slug = f"occ_{name}"
        vocab_slug = f"occ-{name}"
        label = f"Occ {name.capitalize()}"
        # Count QIDs in this occupation group
        vocab_size = count_occ_group_size(args.occs_dir, args.subjects_dir, name)
        entries.append(make_entry(lang, lang_name, date, slug, label, vocab_slug, vocab_size))
    write_cfg(outdir / "projects_occ.cfg", entries)


if __name__ == "__main__":
    main()