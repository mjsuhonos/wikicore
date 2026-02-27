#!/usr/bin/env python3
"""
route_labels.py
Single-pass SKOS label router for the wikicore pipeline.

Reads the full SKOS labels NT file exactly once and routes matching lines
to per-stem output files based on pre-built subject TSV files.

Replaces the per-target awk approach that read all label chunks once per class/
occupation target (~220× I/O reduction).

Usage:
  python3 route_labels.py \\
    --labels   /path/to/wikidata-skos-labels-en.nt \\
    --subjects /path/to/subjects/ \\
    --out-dir  /path/to/skos/ \\
    --locale   en \\
    --sort-workers 10
"""

import argparse
import os
import re
import resource
import subprocess
import sys
from collections import defaultdict
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path

# Matches both Q532_subjects.tsv -> "Q532"
# and P31_other_subjects.tsv -> "P31_other"
# and Q5_sports_subjects.tsv -> "Q5_sports"
STEM_RE = re.compile(r'^(.+?)(?:_subjects|\.subjects)\.tsv$')


def load_reverse_map(subjects_dir: str) -> dict[str, list[str]]:
    """Build {uri: [stem1, stem2, ...]} from all *_subjects.tsv files."""
    reverse: dict[str, list[str]] = defaultdict(list)
    for tsv in sorted(Path(subjects_dir).glob("*.tsv")):
        m = STEM_RE.match(tsv.name)
        if not m:
            continue
        stem = m.group(1)
        with open(tsv) as f:
            for line in f:
                uri = line.strip()
                if uri:
                    reverse[uri].append(stem)
    return reverse


def label_path(out_dir: Path, stem: str, locale: str) -> Path:
    return out_dir / f"skos_{stem}_labels_{locale}.nt"


def sort_inplace(path: Path) -> None:
    tmp = path.with_suffix('.nt.tmp')
    env = {**os.environ, 'LC_ALL': 'C'}
    subprocess.run(['sort', '-u', '-o', str(tmp), str(path)],
                   env=env, check=True)
    tmp.rename(path)


def main() -> None:
    parser = argparse.ArgumentParser(
        description=__doc__,
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument('--labels',       required=True, help='SKOS labels NT file')
    parser.add_argument('--subjects',     required=True, help='Subjects directory with *_subjects.tsv files')
    parser.add_argument('--out-dir',      required=True, help='Output directory for routed label files')
    parser.add_argument('--locale',       required=True, help='Locale string (eg. en)')
    parser.add_argument('--sort-workers', type=int, default=os.cpu_count(),
                        help='Parallel workers for post-sort (default: cpu_count)')
    args = parser.parse_args()

    # 1. Raise file descriptor limit
    soft, hard = resource.getrlimit(resource.RLIMIT_NOFILE)
    resource.setrlimit(resource.RLIMIT_NOFILE, (min(hard, 8192), hard))

    # 2. Build reverse map: URI -> [stem names]
    print("Loading subject files...", flush=True)
    reverse_map = load_reverse_map(args.subjects)
    all_stems = {s for targets in reverse_map.values() for s in targets}
    print(f"  {len(reverse_map):,} unique URIs, {len(all_stems)} output files", flush=True)

    # 3. Single-pass stream; open output handles lazily on first hit
    handles: dict[str, object] = {}
    out_dir = Path(args.out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    print(f"Streaming {args.labels} ...", flush=True)
    total = matched = 0

    with open(args.labels, 'r', buffering=8 * 1024 * 1024) as f:
        for line in f:
            total += 1
            if total % 5_000_000 == 0:
                print(f"  {total:,} lines read, {matched:,} matched so far...", flush=True)
            end = line.index(' ')   # fast URI extraction without split() allocation
            uri = line[:end]
            targets = reverse_map.get(uri)
            if not targets:
                continue
            for stem in targets:
                if stem not in handles:
                    handles[stem] = open(
                        label_path(out_dir, stem, args.locale), 'w',
                        buffering=64 * 1024)
                handles[stem].write(line)
            matched += 1

    for h in handles.values():
        h.close()
    print(f"  {total:,} lines read, {matched:,} matched", flush=True)

    # 4. Touch any output files that were never written (classes with zero hits)
    empty = 0
    for stem in all_stems:
        p = label_path(out_dir, stem, args.locale)
        if not p.exists():
            p.touch()
            empty += 1
    if empty:
        print(f"  touched {empty} empty output files", flush=True)

    # 5. Sort each non-empty output file in-place with LC_ALL=C sort -u (parallel)
    output_paths = [label_path(out_dir, stem, args.locale) for stem in all_stems]
    to_sort = [p for p in output_paths if p.stat().st_size > 0]
    print(f"Sorting {len(to_sort)} files with {args.sort_workers} workers...", flush=True)

    with ThreadPoolExecutor(max_workers=args.sort_workers) as ex:
        futures = {ex.submit(sort_inplace, p): p for p in to_sort}
        done = 0
        for fut in as_completed(futures):
            fut.result()
            done += 1
            if done % 100 == 0:
                print(f"  sorted {done}/{len(futures)}", flush=True)

    print("Done.", flush=True)


if __name__ == '__main__':
    main()
