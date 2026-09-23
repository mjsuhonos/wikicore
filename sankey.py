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
            # Skip aggregation rows (__overall__, __category__*)
            if subject.startswith('__'):
                continue
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
    # Format: {label} + (9 - len(count)) spaces + [{count}] + space + {category}
    # This ensures the ] is at position len(label) + 10
    wikicore_label = f"wikicore-{run_date}"
    for category, total in top_categories:
        count_str = str(total)
        padding = 9 - len(count_str)
        output_lines.append(f"{wikicore_label}{' ' * padding}[{count_str}] {category}")
    
    output_lines.append("")
    
    # Second section: each category -> its subcategories (sorted alphabetically by category, then subcategory)
    # Format: {category} + (9 - len(count)) spaces + [{count}] + space + {category}/{subcategory}
    # This ensures the ] is at position len(category) + 10
    for category in sorted(categories.keys()):
        subcats = categories[category]
        sorted_subcats = sorted(subcats.items(), key=lambda x: x[0])
        for subcat, count in sorted_subcats:
            count_str = str(count)
            padding = 9 - len(count_str)
            output_lines.append(f"{category}{' ' * padding}[{count_str}] {category}/{subcat}")
    
    # Print output
    print('\n'.join(output_lines))


if __name__ == '__main__':
    main()
