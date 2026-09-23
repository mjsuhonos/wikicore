#!/usr/bin/env python3
"""
Generate Sankey diagram data from WikiCore stats TSV.

Usage: python3 sankey.py OUT_DIR SOURCE_DIR

Reads stats.tsv from OUT_DIR and outputs Sankey diagram flow data to stdout.
"""

import csv
import os
import sys


def main():
    if len(sys.argv) < 3:
        print("Usage: python3 sankey.py OUT_DIR SOURCE_DIR", file=sys.stderr)
        sys.exit(1)
    
    out_dir = sys.argv[1]
    source_dir = sys.argv[2]
    
    # Get RUN_DATE from OUT_DIR for label
    # OUT_DIR format: wikicore-YYYYMMDD-LOCALE
    basename = os.path.basename(out_dir)
    run_date = basename.replace('wikicore-', '').split('-')[0]
    
    # Read stats TSV
    stats_file = os.path.join(out_dir, 'stats.tsv')
    
    if not os.path.exists(stats_file):
        print(f"Error: {stats_file} not found", file=sys.stderr)
        print("Please run 'make stats' first.", file=sys.stderr)
        sys.exit(1)
    
    # Parse TSV: subject, total_documents, ...
    by_subject = {}
    by_category = {}
    
    with open(stats_file, 'r') as f:
        reader = csv.DictReader(f, delimiter='\t')
        for row in reader:
            subject = row['subject']
            total_docs = int(row['total_documents'])
            by_subject[subject] = {'total_documents': total_docs}
            
            # Build category -> subject mapping
            category = subject.split('/')[0] if '/' in subject else subject
            if category not in by_category:
                by_category[category] = {}
            by_category[category][subject] = total_docs
    
    # Build category -> subcategories mapping and compute totals
    categories = {}
    category_totals = {}
    
    for subject, subject_stats in by_subject.items():
        category = subject.split('/')[0] if '/' in subject else subject
        total = subject_stats.get('total_documents', 0)
        
        # Accumulate category totals
        category_totals[category] = category_totals.get(category, 0) + total
        
        if category not in categories:
            categories[category] = {}
        
        if '/' in subject:
            subcategory = subject.split('/', 1)[1]
            categories[category][subcategory] = categories[category].get(subcategory, 0) + total
    
    # Get top-level categories sorted by total_documents (descending)
    top_categories = sorted(category_totals.items(), key=lambda x: x[1], reverse=True)
    
    # Generate Sankey output
    output_lines = []
    
    # First section: wikicore-RUN_DATE -> each top-level category
    wikicore_label = f"wikicore-{run_date}"
    for category, total in top_categories:
        output_lines.append(f"{wikicore_label}  [{total}] {category}")
    
    output_lines.append("")
    
    # Second section: each category -> its subcategories (sorted alphabetically by subcategory name)
    for category in sorted(categories.keys()):
        subcats = categories[category]
        sorted_subcats = sorted(subcats.items(), key=lambda x: x[0])
        for subcat, count in sorted_subcats:
            output_lines.append(f"{category:<15} [{count}] {category}/{subcat}")
    
    output_lines.append("")
    
    # Third section: each subcategory -> wikicore-category (sorted alphabetically)
    for category in sorted(categories.keys()):
        subcats = categories[category]
        sorted_subcats = sorted(subcats.items(), key=lambda x: x[0])
        for subcat, count in sorted_subcats:
            output_lines.append(f"{category}/{subcat:<15} [{count}]    wikicore-{category}")
    
    output_lines.append("")
    
    # Fourth section: category roots -> wikicore-full (sorted by count descending)
    for category, _ in top_categories:
        if category in ['class', 'occupation']:
            output_lines.append(f"wikicore-{category:<15} [*]     wikicore-full")
        else:
            output_lines.append(f"{category:<15} [*]     wikicore-full")
    
    # Print output
    print('\n'.join(output_lines))


if __name__ == '__main__':
    main()
