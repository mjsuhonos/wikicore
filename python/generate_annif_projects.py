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
[wikicore_{lang}_yake_{slug}]
name = WikiCore YAKE {label} ({lang})
backend = yake
language = {lang}
analyzer=snowball({lang_name})
vocab=wikicore-{date}-{vocab_slug}-{lang}
limit=100
"""


def make_entry(lang, lang_name, date, slug, label, vocab_slug):
    return PROJECT_TEMPLATE.format(
        lang=lang,
        lang_name=lang_name,
        slug=slug,
        label=label,
        date=date,
        vocab_slug=vocab_slug,
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



def main():
    parser = argparse.ArgumentParser(description="Generate Annif project .cfg files")
    parser.add_argument("--date", required=True, help="Build date (YYYYMMDD)")
    parser.add_argument("--lang", required=True, help="Language code (e.g. en, de)")
    parser.add_argument("--classes-dir", required=True, help="Path to classes/ directory")
    parser.add_argument("--occs-dir", required=True, help="Path to occupations/ directory")
    parser.add_argument("--outdir", required=True, help="Output directory for .cfg files")
    args = parser.parse_args()

    lang = args.lang
    lang_name = SNOWBALL_MAP.get(lang, lang)
    date = args.date
    outdir = Path(args.outdir)

    # --- core ---
    entries = [make_entry(lang, lang_name, date, "core", "Core", "core")]
    write_cfg(outdir / "projects_core.cfg", entries)

    # --- unmatched ---
    entries = [make_entry(lang, lang_name, date, "unmatched", "Unmatched", "unmatched")]
    write_cfg(outdir / "projects_unmatched.cfg", entries)

    # --- P31 other ---
    entries = [make_entry(lang, lang_name, date, "other", "Other", "other")]
    write_cfg(outdir / "projects_other.cfg", entries)

    # --- class groups ---
    entries = []
    for name in stem_names_from_dir(args.classes_dir):
        slug = f"class_{name}"
        vocab_slug = f"class-{name}"
        label = f"Class {name.capitalize()}"
        entries.append(make_entry(lang, lang_name, date, slug, label, vocab_slug))
    write_cfg(outdir / "projects_class_groups.cfg", entries)

    # --- occ groups ---
    entries = []
    for name in stem_names_from_dir(args.occs_dir):
        slug = f"occ_{name}"
        vocab_slug = f"occ-{name}"
        label = f"Occ {name.capitalize()}"
        entries.append(make_entry(lang, lang_name, date, slug, label, vocab_slug))
    write_cfg(outdir / "projects_occ_groups.cfg", entries)


if __name__ == "__main__":
    main()
