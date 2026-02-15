#!/usr/bin/env python3
"""
Prefix-based class splitting (like split_classes.sh) with:
  - auto-expanded prefix list derived from class_names.tsv (first-token frequency)
  - optional embedding-based outlier removal per prefix group

Usage:
    python3 local/split_classes_smart.py [options]

Options:
    --input FILE        Input TSV (default: class_names.tsv)
    --output-dir DIR    Output directory (default: classes_smart)
    --min-prefix-count  Min occurrences of first token to auto-include as prefix (default: 50)
    --filter-embeddings Use sentence-transformers to remove outliers from each prefix group
    --filter-threshold  Max cosine distance from centroid to keep (default: 0.45)
    --model MODEL       sentence-transformers model (default: all-MiniLM-L6-v2)

From class_names/P31 sitelinks filtered (59166 lines)

90% reached at line 776 (cumulative = 90.00%)
95% reached at line 2718 (cumulative = 95.00%)
99% reached at line 16549 (cumulative = 99.00%)
"""

import re
import argparse
from pathlib import Path
from collections import Counter, defaultdict

import numpy as np


# -----------------------------------------------------------------------
# Manually curated prefixes (from original split_classes.sh, de-duped).
# More specific / longer prefixes should come first so they win ties.
# -----------------------------------------------------------------------
MANUAL_PREFIXES = [
    # original script
    "administrative_",
    "anthropomorphic_",
    "book_",
    "bus_",
    "battle_",
    "character"
    "church_",
    "city_",
    "community_",
    "competition_",
    "county_",
    "district_",
    "election_",
    "family_",
    "educational_",
    "european_",
    "event_",
    "fictional_",
    "film_",
    "first_",
    "former_",
    "government_",
    "group_",
    "human_",
    "international_",
    "isotope_",
#    "list_",
    "local_",
    "military_",
    "ministry_",
    "model_",
    "municipality_",
    "music_",
    "musical_",
    "national_",
    "organization_",
    "other_",
    "political_",
    "protein"
    "public_",
    "regional_",
    "road_",
    "social_",
    "sport_",
    "state_",
    "team_",
    "television_",
    "temple"
    "township_",
    "team"
    "type_",
    "unit_",
#    "united_",
    "video_",
    "village_",
    "world_",
    "wiki_",
    "wikimedia_",
]

MANUAL_PREFIXES = []

def load_tsv(path: str) -> list[tuple[str, str]]:
    rows = []
    with open(path, encoding="utf-8") as f:
        for line in f:
            parts = line.strip().split("\t")
            if len(parts) == 2:
                rows.append((parts[0], parts[1]))
    return rows


def clean_label(label: str) -> str:
    """Strip trailing _COUNT and replace underscores with spaces."""
    return re.sub(r"_\d+$", "", label).replace("_", " ")


def discover_prefixes(rows: list[tuple[str, str]], min_count: int) -> list[str]:
    """Return first-token prefixes that appear >= min_count times, sorted by frequency desc."""
    counts: Counter = Counter()
    for _, lbl in rows:
        tok = re.sub(r"_\d+$", "", lbl).split("_")[0]
        if len(tok) > 2:
            counts[tok] += 1
    return [f"{tok}_" for tok, c in counts.most_common() if c >= min_count]


def embed_labels(labels: list[str], model_name: str) -> np.ndarray:
    from sentence_transformers import SentenceTransformer
    model = SentenceTransformer(model_name)
    return model.encode(labels, batch_size=256, show_progress_bar=True,
                        convert_to_numpy=True, normalize_embeddings=True)


def filter_outliers(
    items: list[tuple[str, str]],
    threshold: float,
    model_name: str,
) -> tuple[list[tuple[str, str]], list[tuple[str, str]]]:
    """
    Embed cleaned labels, compute centroid, keep items within cosine distance threshold.
    Returns (kept, rejected).
    Since embeddings are L2-normalized, cosine_distance = 1 - dot(v, centroid).
    """
    labels = [clean_label(lbl) for _, lbl in items]
    embeddings = embed_labels(labels, model_name)

    centroid = embeddings.mean(axis=0)
    centroid /= np.linalg.norm(centroid)

    distances = 1.0 - embeddings @ centroid  # cosine distance

    kept, rejected = [], []
    for item, dist in zip(items, distances):
        if dist <= threshold:
            kept.append(item)
        else:
            rejected.append(item)
    return kept, rejected


def main():
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--input", default="class_names.tsv")
    parser.add_argument("--output-dir", default="classes_smart")
    parser.add_argument("--min-prefix-count", type=int, default=50,
                        help="Min first-token frequency to auto-include as a prefix")
    parser.add_argument("--filter-embeddings", action="store_true",
                        help="Use sentence-transformers to remove outliers from each prefix group")
    parser.add_argument("--filter-threshold", type=float, default=0.45,
                        help="Max cosine distance from centroid to keep (0=tight, 1=keep all)")
    parser.add_argument("--model", default="all-MiniLM-L6-v2",
                        help="sentence-transformers model name")
    args = parser.parse_args()

    rows = load_tsv(args.input)
    print(f"Loaded {len(rows)} rows from {args.input}")

    # --- Build prefix list ---
    auto_prefixes = discover_prefixes(rows, args.min_prefix_count)
    print(f"Auto-discovered {len(auto_prefixes)} prefixes (>={args.min_prefix_count} occurrences)")

    # Merge: manual first, then auto-discovered extras, preserving order and deduplicating.
    seen = set(MANUAL_PREFIXES)
    extra = [p for p in auto_prefixes if p not in seen]
    prefixes = MANUAL_PREFIXES + extra
    print(f"Total prefix list ({len(prefixes)}): {prefixes}\n")

    # --- Match prefixes greedily (first match wins, like split_classes.sh) ---
    # Sort by length descending so longer/more-specific prefixes match first.
    prefixes_sorted = sorted(prefixes, key=len, reverse=True)

    groups: dict[str, list[tuple[str, str]]] = defaultdict(list)
    remainder: list[tuple[str, str]] = []

    for qid, lbl in rows:
        matched = False
        for prefix in prefixes_sorted:
            if prefix in lbl:
                groups[prefix].append((qid, lbl))
                matched = True
                break
        if not matched:
            remainder.append((qid, lbl))

    print(f"Matched items: {sum(len(v) for v in groups.values())}")
    print(f"Unmatched (→ other.tsv): {len(remainder)}\n")

    # --- Optionally filter outliers with embeddings ---
    all_rejected: list[tuple[str, str]] = []
    if args.filter_embeddings:
        print(f"Filtering outliers (threshold={args.filter_threshold}, model={args.model})...\n")
        filtered_groups: dict[str, list[tuple[str, str]]] = {}
        for prefix, items in groups.items():
            if len(items) < 5:
                # Too small to meaningfully filter
                filtered_groups[prefix] = items
                continue
            kept, rejected = filter_outliers(items, args.filter_threshold, args.model)
            n_rej = len(rejected)
            if n_rej:
                print(f"  {prefix}: kept {len(kept)}/{len(items)}, removed {n_rej} outliers")
                all_rejected.extend(rejected)
            filtered_groups[prefix] = kept
        groups = filtered_groups

    # --- Write output ---
    out_dir = Path(args.output_dir)
    out_dir.mkdir(exist_ok=True)

    total = 0
    for prefix in prefixes:
        items = groups.get(prefix, [])
        if not items:
            continue
        # Filename: strip trailing underscore, e.g. "human_" → human.tsv
        fname = prefix.rstrip("_") + ".tsv"
        out_path = out_dir / fname
        with open(out_path, "w", encoding="utf-8") as f:
            for qid, lbl in items:
                f.write(f"{qid}\t{lbl}\n")
        print(f"  {fname}  ({len(items)} items)")
        total += len(items)

    # Write remainder + rejected outliers into other.tsv
    other = remainder + all_rejected
    if other:
        out_path = out_dir / "other.tsv"
        with open(out_path, "w", encoding="utf-8") as f:
            for qid, lbl in other:
                f.write(f"{qid}\t{lbl}\n")
        print(f"  other.tsv  ({len(other)} items)")
        total += len(other)

    print(f"\nWrote to {out_dir}/  ({total} total items)")


if __name__ == "__main__":
    main()
