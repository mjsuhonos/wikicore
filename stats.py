#!/usr/bin/env python3
"""
Compute statistics for WikiCore JSONL files.

Usage: python3 stats.py OUT_DIR SOURCE_DIR

Outputs JSON statistics to stdout.
"""

import json
import glob
import os
import sys
from collections import defaultdict
import statistics


def percentile(data, p):
    """Calculate p-th percentile (0-100) using linear interpolation."""
    if not data:
        return 0
    sorted_data = sorted(data)
    n = len(sorted_data)
    if n == 1:
        return sorted_data[0]
    k = (p / 100) * (n - 1)
    f = int(k)
    c = f + 1
    if c >= n:
        return sorted_data[f]
    return sorted_data[f] * (c - k) + sorted_data[c] * (k - f)


def extract_subject_name(filepath, fulltext_dir):
    """Extract subject name from filepath.
    
    For: wikicore-20260914-en/fulltext/class/aircraft-train.jsonl
    Returns: class/aircraft
    
    For: wikicore-20260914-en/fulltext/core-train.jsonl
    Returns: core
    """
    rel_path = os.path.relpath(filepath, fulltext_dir)
    rel_path = os.path.splitext(rel_path)[0]
    
    for suffix in ['-train', '-eval', '-test']:
        if rel_path.endswith(suffix):
            rel_path = rel_path[:-len(suffix)]
            break
    
    if rel_path.endswith('.jsonl'):
        rel_path = os.path.splitext(rel_path)[0]
    
    return rel_path


def process_document(doc):
    """Process a single document and extract statistics."""
    result = {
        'document_id': doc.get('document_id', ''),
        'has_uri': 'uri' in doc.get('metadata', {}),
        'text': doc.get('text', ''),
        'metadata': doc.get('metadata', {}),
    }
    
    # Paragraph stats
    text = result['text']
    paras = text.split('\n\n') if text else []
    para_count = len([p for p in paras if p.strip()])
    result['paragraph_count'] = para_count
    
    # Link stats
    metadata = result['metadata']
    doc_links = []
    for key, value in metadata.items():
        if key != 'uri' and isinstance(value, str):
            linked_qids = [q.strip() for q in value.split(',') if q.strip()]
            doc_links.extend(linked_qids)
    
    result['link_count'] = len(doc_links)
    result['links'] = doc_links
    result['text_length'] = len(text)
    
    return result


def aggregate_subject_stats(subject_docs):
    """Aggregate statistics for a subject (across all its splits)."""
    if not subject_docs:
        return {}
    
    total_docs = len(subject_docs)
    all_qids = set()
    docs_with_enwp = 0
    
    para_counts = []
    docs_with_2_plus_para = 0
    total_paragraphs = 0
    
    link_counts = []
    all_linked_qids = set()
    total_links = 0
    docs_with_1_plus_link = 0
    
    text_lengths = []
    total_text_length = 0
    
    for doc in subject_docs:
        all_qids.add(doc['document_id'])
        
        if doc['has_uri']:
            docs_with_enwp += 1
        
        para_count = doc['paragraph_count']
        para_counts.append(para_count)
        total_paragraphs += para_count
        
        if para_count >= 2:
            docs_with_2_plus_para += 1
        
        link_count = doc['link_count']
        link_counts.append(link_count)
        total_links += link_count
        
        if link_count >= 1:
            docs_with_1_plus_link += 1
        
        all_linked_qids.update(doc['links'])
        
        text_length = doc['text_length']
        text_lengths.append(text_length)
        total_text_length += text_length
    
    avg_paragraphs = total_paragraphs / total_docs if total_docs > 0 else 0
    median_paragraphs = statistics.median(para_counts) if para_counts else 0
    
    avg_links = total_links / total_docs if total_docs > 0 else 0
    median_links = statistics.median(link_counts) if link_counts else 0
    
    avg_text_length = total_text_length / total_docs if total_docs > 0 else 0
    median_text_length = statistics.median(text_lengths) if text_lengths else 0
    
    avg_links_per_paragraph = total_links / total_paragraphs if total_paragraphs > 0 else 0
    avg_links_per_1000_chars = (total_links / total_text_length * 1000) if total_text_length > 0 else 0
    
    # Key percentiles
    p50 = percentile(link_counts, 50)
    p95 = percentile(link_counts, 95)
    p99 = percentile(link_counts, 99)
    
    # Link thresholds for N = 0, 1, 2, 3, 5, 10, 20
    link_thresholds = [0, 1, 2, 3, 5, 10, 20]
    docs_by_link_threshold = {}
    for n in link_thresholds:
        count = sum(1 for x in link_counts if x > n)
        docs_by_link_threshold[f">{n}"] = count
    
    # Simple histograms
    def simple_histogram(data, bins):
        """Create a simple histogram with label ranges."""
        counts = [0] * (len(bins) - 1)
        for value in data:
            for i in range(len(bins) - 1):
                if bins[i] <= value < bins[i + 1] or (i == len(bins) - 2 and value >= bins[i]):
                    counts[i] += 1
                    break
        
        labels = []
        for i in range(len(bins) - 1):
            if bins[i + 1] == float('inf'):
                labels.append(f"{bins[i]}+")
            else:
                labels.append(f"{bins[i]}-{bins[i + 1]}")
        
        return dict(zip(labels, counts))
    
    link_bins = [0, 1, 5, 10, 20, float('inf')]
    links_hist = simple_histogram(link_counts, link_bins)
    
    paragraph_bins = [1, 2, 3, 5, float('inf')]
    paragraphs_hist = simple_histogram(para_counts, paragraph_bins)
    
    text_length_bins = [0, 500, 1000, 5000, float('inf')]
    text_length_hist = simple_histogram(text_lengths, text_length_bins)
    
    return {
        'total_documents': total_docs,
        'unique_qids': len(all_qids),
        'qids_with_wikipedia': docs_with_enwp,
        
        # Paragraph statistics
        'documents_with_2_plus_paragraphs': docs_with_2_plus_para,
        'total_paragraphs': total_paragraphs,
        'avg_paragraphs_per_document': round(avg_paragraphs, 2),
        'median_paragraphs_per_document': round(median_paragraphs, 2),
        'paragraphs_histogram': paragraphs_hist,
        
        # Link statistics
        'documents_with_links': docs_with_1_plus_link,
        'total_links': total_links,
        'unique_linked_qids': len(all_linked_qids),
        'avg_links_per_document': round(avg_links, 2),
        'median_links_per_document': round(median_links, 2),
        'p50_links': round(p50, 2),
        'p95_links': round(p95, 2),
        'p99_links': round(p99, 2),
        'link_thresholds': docs_by_link_threshold,
        'links_histogram': links_hist,
        
        # Text length statistics
        'avg_text_length_chars': round(avg_text_length),
        'median_text_length_chars': round(median_text_length),
        'text_length_histogram': text_length_hist,
        
        # Link density
        'avg_links_per_paragraph': round(avg_links_per_paragraph, 2),
        'avg_links_per_1000_chars': round(avg_links_per_1000_chars, 2),
    }


def process_unmapped(filepath):
    """Process unmapped.jsonl file."""
    unmapped_docs = []
    
    if not os.path.exists(filepath):
        return unmapped_docs
    
    with open(filepath, 'r') as f:
        for line in f:
            line = line.strip()
            if line:
                try:
                    doc = json.loads(line)
                    unmapped_docs.append(doc)
                except json.JSONDecodeError:
                    continue
    
    return unmapped_docs


def main():
    if len(sys.argv) < 3:
        print("Usage: python3 stats.py OUT_DIR SOURCE_DIR", file=sys.stderr)
        sys.exit(1)
    
    out_dir = sys.argv[1]
    source_dir = sys.argv[2]
    
    fulltext_dir = os.path.join(out_dir, 'fulltext')
    
    # Find all JSONL files
    jsonl_files = []
    
    # Core files
    core_pattern = os.path.join(fulltext_dir, 'core-*.jsonl')
    jsonl_files.extend(glob.glob(core_pattern))
    
    # Class files
    for split in ['train', 'eval', 'test']:
        class_pattern = os.path.join(fulltext_dir, 'class', f'*-{split}.jsonl')
        jsonl_files.extend(glob.glob(class_pattern))
    
    # Occupation files
    for split in ['train', 'eval', 'test']:
        occ_pattern = os.path.join(fulltext_dir, 'occupation', f'*-{split}.jsonl')
        jsonl_files.extend(glob.glob(occ_pattern))
    
    # Also look for files directly in fulltext_dir
    direct_pattern = os.path.join(fulltext_dir, '*.jsonl')
    direct_files = glob.glob(direct_pattern)
    for f in direct_files:
        if f not in jsonl_files:
            jsonl_files.append(f)
    
    # Group by subject
    subject_docs = defaultdict(list)
    
    print(f"Found {len(jsonl_files)} JSONL files", file=sys.stderr)
    
    for filepath in jsonl_files:
        subject_name = extract_subject_name(filepath, fulltext_dir)
        
        with open(filepath, 'r') as f:
            for line in f:
                line = line.strip()
                if line:
                    try:
                        doc = json.loads(line)
                        processed = process_document(doc)
                        subject_docs[subject_name].append(processed)
                    except json.JSONDecodeError as e:
                        print(f"Error parsing JSON in {filepath}: {e}", file=sys.stderr)
                        continue
    
    # Process unmapped file
    unmapped_file = os.path.join(source_dir, 'unmapped.jsonl')
    unmapped_docs = process_unmapped(unmapped_file)
    
    # Aggregate statistics
    
    # By subject
    by_subject = {}
    for subject, docs in subject_docs.items():
        by_subject[subject] = aggregate_subject_stats(docs)
    
    # By category
    by_category = defaultdict(list)
    
    for subject, docs in subject_docs.items():
        category = subject.split('/')[0] if '/' in subject else subject
        by_category[category].extend(docs)
    
    if unmapped_docs:
        by_category['unmapped'] = []
    
    category_stats = {}
    for category, docs in by_category.items():
        if docs:
            category_stats[category] = aggregate_subject_stats(docs)
        elif category == 'unmapped':
            category_stats[category] = {
                'total_documents': len(unmapped_docs),
                'unique_qids': 0,
                'qids_with_wikipedia': 0,
                'documents_with_2_plus_paragraphs': 0,
                'total_paragraphs': 0,
                'avg_paragraphs_per_document': 0,
                'median_paragraphs_per_document': 0,
                'paragraphs_histogram': {},
                'documents_with_links': 0,
                'total_links': 0,
                'unique_linked_qids': 0,
                'avg_links_per_document': 0,
                'median_links_per_document': 0,
                'p50_links': 0,
                'p95_links': 0,
                'p99_links': 0,
                'link_thresholds': {},
                'links_histogram': {},
                'avg_text_length_chars': 0,
                'median_text_length_chars': 0,
                'text_length_histogram': {},
                'avg_links_per_paragraph': 0,
                'avg_links_per_1000_chars': 0,
            }
        else:
            category_stats[category] = {}
    
    # Overall statistics
    all_docs = []
    for docs in subject_docs.values():
        all_docs.extend(docs)
    
    overall_stats = aggregate_subject_stats(all_docs)
    
    # Build final output
    output = {
        'overall': overall_stats,
        'by_category': category_stats,
        'by_subject': by_subject,
        'metadata': {
            'total_subjects': len(by_subject),
            'total_files_processed': len(jsonl_files),
            'unmapped_count': len(unmapped_docs),
        },
    }
    
    # Print JSON to stdout
    print(json.dumps(output, indent=2))


if __name__ == '__main__':
    main()
