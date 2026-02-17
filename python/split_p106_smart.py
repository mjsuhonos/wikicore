#!/usr/bin/env python3
"""
Group P106 (occupation) counts by label prefix, similar to split_classes_smart.py.

Reads P106-counts.tsv (format: count<TAB><QID URI>), joins labels from
wikidata-skos-labels-en.nt, builds label_count slugs, then applies
prefix-based grouping with auto-discovered prefixes.

Usage:
    python3 split_p106_smart.py [options]

Options:
    --counts FILE       P106 counts TSV (default: working.nosync/P106-counts.tsv)
    --labels FILE       SKOS labels NT (default: working.nosync/wikidata-skos-labels-en.nt)
    --output-dir DIR    Output directory (default: working.nosync/p106_groups)
    --min-prefix-count  Min first-token frequency to auto-include as prefix (default: 3)
    --no-counts         Omit count suffix from output labels

90% reached at line 372 (cumulative = 90.02%)
95% reached at line 709 (cumulative = 95.01%)
99% reached at line 2269 (cumulative = 99.00%)
"""

import re
import argparse
from pathlib import Path
from collections import Counter, defaultdict


WD_PREFIX = "http://www.wikidata.org/entity/"
PREFLABEL_URI = "http://www.w3.org/2004/02/skos/core#prefLabel"


def parse_qid(uri_field: str) -> str | None:
    """Extract QID from '<http://www.wikidata.org/entity/Qxxx>'."""
    m = re.match(r"<" + re.escape(WD_PREFIX) + r"(Q\d+)>", uri_field.strip())
    return m.group(1) if m else None


def load_counts(path: str) -> dict[str, int]:
    """Load P106-counts.tsv → {QID: count}. Format: count<TAB><QID URI>"""
    counts = {}
    with open(path, encoding="utf-8") as f:
        for line in f:
            parts = line.strip().split()
            if len(parts) != 2:
                continue
            count_str, uri_field = parts
            qid = parse_qid(uri_field)
            if qid:
                try:
                    counts[qid] = int(count_str)
                except ValueError:
                    pass
    return counts


def load_labels(path: str, wanted: set[str]) -> dict[str, str]:
    """
    Stream wikidata-skos-labels-en.nt and collect prefLabels for QIDs in `wanted`.
    Keeps the first (lowercase) label seen per QID; skips duplicates/capitalised variants.
    NT line format:
        <WD_URI> <PREFLABEL_URI> "label"@en .
    """
    labels: dict[str, str] = {}
    needed = len(wanted)
    found = 0

    print(f"Streaming labels file for {needed} QIDs …")
    with open(path, encoding="utf-8") as f:
        for line in f:
            if PREFLABEL_URI not in line:
                continue
            parts = line.split(None, 3)
            if len(parts) < 3:
                continue
            qid = parse_qid(parts[0])
            if qid not in wanted or qid in labels:
                continue
            # Extract literal: "label text"@en
            m = re.search(r'"([^"]+)"@en', parts[2] if len(parts) == 3 else parts[2] + parts[3])
            if not m:
                continue
            label = m.group(1)
            # Prefer lowercase variant; skip if we already have one
            if label[0].isupper() and qid in labels:
                continue
            labels[qid] = label
            found += 1
            if found >= needed:
                break

    print(f"Found labels for {len(labels)}/{needed} QIDs")
    return labels


def slugify(label: str) -> str:
    """Convert a label to a lowercase underscore slug."""
    slug = label.lower()
    slug = re.sub(r"[^a-z0-9]+", "_", slug)
    slug = slug.strip("_")
    return slug


def discover_prefixes(rows: list[tuple[str, str, int]], min_count: int) -> list[str]:
    """Return first-token prefixes appearing >= min_count times, sorted by frequency desc."""
    token_counts: Counter = Counter()
    for _qid, slug, _n in rows:
        tok = slug.split("_")[0]
        if len(tok) > 2:
            token_counts[tok] += 1
    return [f"{tok}_" for tok, c in token_counts.most_common() if c >= min_count]


def main():
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--counts",    default="working.nosync/P106-counts.tsv")
    parser.add_argument("--labels",    default="working.nosync/wikidata-skos-labels-en.nt")
    parser.add_argument("--output-dir", default="working.nosync/p106_groups")
    parser.add_argument("--min-prefix-count", type=int, default=3,
                        help="Min first-token frequency to auto-include as a prefix")
    parser.add_argument("--no-counts", action="store_true",
                        help="Omit count suffix from output label column")
    args = parser.parse_args()

    # 1. Load counts
    counts = load_counts(args.counts)
    print(f"Loaded {len(counts)} P106 values from {args.counts}")

    # 2. Load labels for just the QIDs we care about
    labels = load_labels(args.labels, set(counts.keys()))

    # 3. Build rows: (QID, slug, count) — sorted by count desc
    rows: list[tuple[str, str, int]] = []
    missing = []
    for qid, n in sorted(counts.items(), key=lambda x: -x[1]):
        if qid not in labels:
            missing.append((qid, n))
            continue
        slug = slugify(labels[qid])
        if not slug:
            missing.append((qid, n))
            continue
        rows.append((qid, slug, n))

    print(f"Rows with labels: {len(rows)}, missing labels: {len(missing)}")

    # 4. Discover prefixes
    prefixes = discover_prefixes(rows, args.min_prefix_count)
    print(f"Auto-discovered {len(prefixes)} prefixes (>={args.min_prefix_count} occurrences)")
    print(f"Prefixes: {prefixes}\n")

    # Sort longer/more-specific prefixes first
    prefixes_sorted = sorted(prefixes, key=len, reverse=True)

    # 5. Group
    groups: dict[str, list[tuple[str, str, int]]] = defaultdict(list)
    remainder: list[tuple[str, str, int]] = []

    for qid, slug, n in rows:
        matched = False
        for prefix in prefixes_sorted:
            if slug.startswith(prefix) or f"_{prefix.rstrip('_')}_" in slug:
                groups[prefix].append((qid, slug, n))
                matched = True
                break
        if not matched:
            remainder.append((qid, slug, n))

    print(f"Matched: {sum(len(v) for v in groups.values())}")
    print(f"Unmatched (→ other.tsv): {len(remainder)}\n")

    # 6. Write output
    out_dir = Path(args.output_dir)
    out_dir.mkdir(parents=True, exist_ok=True)

    def label_col(slug: str, n: int) -> str:
        return slug if args.no_counts else f"{slug}_{n}"

    total = 0
    for prefix in prefixes:
        items = groups.get(prefix, [])
        if not items:
            continue
        fname = prefix.rstrip("_") + ".tsv"
        out_path = out_dir / fname
        with open(out_path, "w", encoding="utf-8") as f:
            for qid, slug, n in items:
                f.write(f"Q{qid}\t{label_col(slug, n)}\n")
        print(f"  {fname}  ({len(items)} items)")
        total += len(items)

    # other.tsv = remainder + QIDs with no label
    other_rows = [(qid, slug, n) for qid, slug, n in remainder]
    other_nolabel = [(qid, f"Q{qid}", n) for qid, n in missing]

    if other_rows or other_nolabel:
        out_path = out_dir / "other.tsv"
        with open(out_path, "w", encoding="utf-8") as f:
            for qid, slug, n in other_rows:
                f.write(f"Q{qid}\t{label_col(slug, n)}\n")
            for qid, slug, n in other_nolabel:
                f.write(f"Q{qid}\t{label_col(slug, n)}\n")
        print(f"  other.tsv  ({len(other_rows) + len(other_nolabel)} items)")
        total += len(other_rows) + len(other_nolabel)

    print(f"\nWrote {total} items to {out_dir}/")


if __name__ == "__main__":
    main()
