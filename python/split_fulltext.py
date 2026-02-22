#!/usr/bin/env python3
"""
split_fulltext.py
Single-pass fulltext routing for the wikicore pipeline.

Replaces the shell split/parallel/merge dance in the Makefile, decompressing
the fulltext GZ exactly once and routing each line to the appropriate output
file(s) via in-memory dict lookups.

Modes:
  classes   Route each instance QID to its class QID output file(s).
  occs      Route each person QID to their occupation group output file(s).
            A person in multiple groups is written to each group file.

Output format per line: text<TAB><http://www.wikidata.org/entity/QID>

Usage:
  python3 split_fulltext.py classes \\
      --map    INSTANCE_MAP_TSV \\
      --qids   CLASS_QIDS_FILE \\
      --gz     FULLTEXT_GZ \\
      --out-dir OUTPUT_DIR \\
      --date   YYYYMMDD \\
      --locale LOCALE

  python3 split_fulltext.py occs \\
      --map    OCC_GROUP_MAP_TSV \\
      --gz     FULLTEXT_GZ \\
      --out-dir OUTPUT_DIR \\
      --date   YYYYMMDD \\
      --locale LOCALE \\
      --groups GROUP [GROUP ...]
"""

import argparse
import gzip
import sys
from collections import defaultdict
from pathlib import Path


def outfile_path(out_dir: Path, date: str, key: str, locale: str) -> Path:
    return out_dir / f"wikicore-{date}-{key}-{locale}.tsv"


def load_map(path: str) -> dict[str, list[str]]:
    """Load a two-column TSV into {key: [value, ...]}. One key may map to multiple values."""
    m: dict[str, list[str]] = defaultdict(list)
    with open(path) as f:
        for line in f:
            parts = line.rstrip("\n").split("\t", 1)
            if len(parts) == 2:
                m[parts[0]].append(parts[1])
    return m


def stream_fulltext(gz_path: str):
    """Yield (qid, text) pairs from a tab-separated fulltext GZ file."""
    with gzip.open(gz_path, "rt", encoding="utf-8", errors="replace") as f:
        for i, line in enumerate(f):
            if i % 500_000 == 0 and i > 0:
                print(f"  {i:,} lines processed...", flush=True)
            parts = line.rstrip("\n").split("\t", 1)
            if len(parts) == 2:
                yield parts[0], parts[1]


def write_lines(routing_map: dict[str, list[str]], gz_path: str,
                out_dir: Path, date: str, locale: str,
                touch_keys: set[str]) -> None:
    """
    Stream the fulltext GZ once, routing each matching line to its output file(s).
    After streaming, touch empty files for any expected keys with no matches.
    """
    handles: dict[str, object] = {}
    matched = 0

    for qid, text in stream_fulltext(gz_path):
        targets = routing_map.get(qid)
        if not targets:
            continue
        out_line = f"{text}\t<http://www.wikidata.org/entity/{qid}>\n"
        for key in targets:
            if key not in handles:
                handles[key] = open(outfile_path(out_dir, date, key, locale), "w",
                                    encoding="utf-8")
            handles[key].write(out_line)
            matched += 1

    for h in handles.values():
        h.close()

    empty = 0
    for key in touch_keys:
        p = outfile_path(out_dir, date, key, locale)
        if not p.exists():
            p.touch()
            empty += 1

    print(f"Wrote {matched:,} lines across {len(handles):,} files; "
          f"touched {empty:,} empty files")


def run_classes(args: argparse.Namespace) -> None:
    out_dir = Path(args.out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)

    print(f"Loading instance→class map from {args.map}...")
    routing_map = load_map(args.map)
    print(f"Loaded {len(routing_map):,} instance QIDs")

    touch_keys: set[str] = set()
    with open(args.qids) as f:
        for line in f:
            q = line.strip()
            if q:
                touch_keys.add(q)
    print(f"Loaded {len(touch_keys):,} class QIDs to ensure")

    print(f"Streaming {args.gz}...")
    write_lines(routing_map, args.gz, out_dir, args.date, args.locale, touch_keys)


def run_occs(args: argparse.Namespace) -> None:
    out_dir = Path(args.out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)

    print(f"Loading person→group map from {args.map}...")
    routing_map = load_map(args.map)
    print(f"Loaded {len(routing_map):,} person QIDs")

    touch_keys: set[str] = set(args.groups) if args.groups else set()
    for groups in routing_map.values():
        touch_keys.update(groups)

    print(f"Streaming {args.gz}...")
    write_lines(routing_map, args.gz, out_dir, args.date, args.locale, touch_keys)


def main() -> None:
    parser = argparse.ArgumentParser(
        description=__doc__,
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    sub = parser.add_subparsers(dest="mode", required=True)

    p_classes = sub.add_parser("classes", help="Route fulltext to per-class-QID files")
    p_classes.add_argument("--map",     required=True, help="instance_qid→class_qid TSV")
    p_classes.add_argument("--qids",    required=True, help="All class QIDs file (for empty-file touch)")
    p_classes.add_argument("--gz",      required=True, help="Fulltext GZ source")
    p_classes.add_argument("--out-dir", required=True, help="Output directory")
    p_classes.add_argument("--date",    required=True, help="Release date string (YYYYMMDD)")
    p_classes.add_argument("--locale",  required=True, help="Locale string (eg. en)")

    p_occs = sub.add_parser("occs", help="Route fulltext to per-occupation-group files")
    p_occs.add_argument("--map",     required=True, help="person_qid→group TSV")
    p_occs.add_argument("--gz",      required=True, help="Fulltext GZ source")
    p_occs.add_argument("--out-dir", required=True, help="Output directory")
    p_occs.add_argument("--date",    required=True, help="Release date string (YYYYMMDD)")
    p_occs.add_argument("--locale",  required=True, help="Locale string (eg. en)")
    p_occs.add_argument("--groups",  nargs="+", help="All expected group names (for empty-file touch)")

    args = parser.parse_args()

    if args.mode == "classes":
        run_classes(args)
    elif args.mode == "occs":
        run_occs(args)
    else:
        parser.print_help()
        sys.exit(1)


if __name__ == "__main__":
    main()
