#!/usr/bin/env python3

import heapq
import json
import multiprocessing
import os
import re
import sys
import tempfile
from urllib.parse import quote

import mwxml
import mwparserfromhell

from mwparserfromhell.nodes import (
    Comment,
    Heading,
    HTMLEntity,
    Tag,
    Template,
    Text,
    Wikilink,
)

WIKIPEDIA_BASE = "https://en.wikipedia.org/wiki/"
WIKIDATA_BASE = "http://www.wikidata.org/entity/"

# Pre-compute lengths for faster prefix stripping
WIKIPEDIA_BASE_LEN = len(WIKIPEDIA_BASE)
WIKIDATA_BASE_LEN = len(WIKIDATA_BASE)

try:
    multiprocessing.set_start_method('fork')
except RuntimeError:
    pass

# Configuration constants
DEFAULT_NUM_WORKERS = os.cpu_count() #// 2
DEFAULT_BATCH_SIZE = 5000
DEFAULT_MAX_BATCHES = None  # Process all batches by default
FILTERED_OUTPUT_FILE = 'unmapped.jsonl'


def wikipedia_url(title):
    """Turn a MediaWiki article title into a Wikipedia URL."""
    title = str(title).strip()
    title = title.split("#", 1)[0].strip()
    title = title.replace(" ", "_")
    return WIKIPEDIA_BASE + quote(title, safe=";:@$!*(),/~")


def is_article_link(link):
    """Return True for links to normal Wikipedia articles."""
    return bool(link.title) and ":" not in str(link.title).strip()


def extract_intro(code):
    """Return everything before the first section heading, excluding templates."""
    nodes = []
    for node in code.nodes:
        if isinstance(node, Heading):
            break
        # Skip template nodes to prevent them from appearing in the output
        if not isinstance(node, Template):
            nodes.append(str(node))
    return mwparserfromhell.parse("".join(nodes))


def extract_paragraphs(code):
    """Split intro wikitext into blank-line-separated paragraphs."""
    text = str(code).replace("\r\n", "\n").replace("\r", "\n")
    return [
        mwparserfromhell.parse(p.strip())
        for p in re.split(r"\n\s*\n", text)
        if p.strip()
    ]


def render_node(node):
    """Render one wikitext node to plain text while collecting Wikipedia link occurrences."""
    if isinstance(node, Text):
        return str(node), []

    if isinstance(node, Comment):
        return "", []

    if isinstance(node, Template):
        return "", []

    if isinstance(node, Wikilink):
        if is_article_link(node):
            url = wikipedia_url(node.title)
            visible = render_wikicode(node.text if node.text is not None else node.title)
            return visible[0], [url] + visible[1]
        return "", []

    if isinstance(node, Tag):
        tag = str(node.tag).lower().strip()
        if tag in {"ref", "references", "gallery", "timeline", "math", "source", "syntaxhighlight", "img", "figure", "div", "span", "table"}:
            return "", []
        if node.contents is not None:
            return render_wikicode(node.contents)
        return "", []

    if isinstance(node, HTMLEntity):
        return str(node), []

    return str(node), []


def render_wikicode(code):
    """Render Wikicode recursively and preserve link occurrences."""
    text_parts = []
    links = []
    for node in code.nodes:
        text, node_links = render_node(node)
        text_parts.append(text)
        links.extend(node_links)
    return "".join(text_parts), links


def clean_text(text):
    """Normalize whitespace without destroying paragraph structure."""
    # Remove magic words like __NOTOC__, __TOC__, etc. and bold/italic markers
    text = re.sub(r'__[A-Z_]+__', '', text)
    text = text.replace("'''", "").replace("'", "")
    # Normalize all whitespace sequences to single spaces
    text = re.sub(r'[ \t]+', ' ', text)
    # Remove leading/trailing whitespace from lines and normalize newlines
    text = re.sub(r'[ \t]+\n', '\n', text)
    text = re.sub(r'\n[ \t]+', '\n', text)
    return text.strip()


def render_paragraph(code):
    """Return (plain_text, wikipedia_links) for one paragraph."""
    text, links = render_wikicode(code)
    return clean_text(text), links


def latest_revision(page):
    """Return the last revision in the page."""
    return next(reversed(list(page)), None)


def load_sitelinks(sitelinks_path):
    """Load sitelinks file and return a mapping from Wikipedia article title to Wikidata QID."""
    title_to_qid = {}
    wp_len = WIKIPEDIA_BASE_LEN
    wd_len = WIKIDATA_BASE_LEN
    wp_base = WIKIPEDIA_BASE
    wd_base = WIKIDATA_BASE
    with open(sitelinks_path, 'r') as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            parts = line.split('\t')
            if len(parts) < 2:
                continue
            wikidata_uri = parts[0].strip()
            if wikidata_uri.startswith('<') and wikidata_uri.endswith('>'):
                wikidata_uri = wikidata_uri[1:-1]
            wikipedia_uri = parts[1].strip()
            if wikipedia_uri.startswith('<') and wikipedia_uri.endswith('>'):
                wikipedia_uri = wikipedia_uri[1:-1]
            # Extract QID from Wikidata URI
            if wikidata_uri.startswith(wd_base):
                qid = wikidata_uri[wd_len:]
            else:
                continue
            # Extract title from Wikipedia URI
            if wikipedia_uri.startswith(wp_base):
                title = wikipedia_uri[wp_len:]
            else:
                continue
            title_to_qid[title] = qid
    return title_to_qid


def extract_page_data(page):
    """Extract picklable data from a mwxml Page for parallel processing."""
    revision = latest_revision(page)
    return {
        'title': page.title,
        'id': page.id,
        'redirect': page.redirect,
        'namespace': page.namespace,
        'text': revision.text if revision and revision.text else None,
    }


def page_data_to_jsonl(page_data, title_to_qid):
    """Convert page data dict to JSON Lines object.
    
    Args:
        page_data: dict with page metadata and text
        title_to_qid: mapping from Wikipedia article titles to Wikidata QIDs
    
    Returns:
        dict: JSON Lines object for valid pages
        tuple: ('filtered', reason, filtered_info) for filtered pages
    """
    # Check filtering conditions
    if page_data['namespace'] != 0:
        return ('filtered', 'namespace', {
            'id': page_data['id'],
            'title': page_data['title'],
            'namespace': page_data['namespace'],
            'reason': 'namespace'
        })
    
    if page_data['redirect'] or page_data['text'] is None:
        reason = 'redirect' if page_data['redirect'] else 'no_text'
        return ('filtered', reason, {
            'id': page_data['id'],
            'title': page_data['title'],
            'namespace': page_data['namespace'],
            'reason': reason
        })

    code = mwparserfromhell.parse(page_data['text'])
    intro = extract_intro(code)
    paragraphs = extract_paragraphs(intro)

    rendered_paragraphs = []
    metadata_links = {}

    for paragraph in paragraphs:
        text, links = render_paragraph(paragraph)
        if not text:
            continue

        number = len(rendered_paragraphs) + 1
        rendered_paragraphs.append(text)

        qids = []
        for link in links:
            # Extract title from Wikipedia URL to look up in title_to_qid mapping
            if link.startswith(WIKIPEDIA_BASE):
                link_title = link[WIKIPEDIA_BASE_LEN:]
            else:
                link_title = link
            qid = title_to_qid.get(link_title, "")
            if qid:
                qids.append(qid)

        if qids:
            metadata_links[str(number)] = ",".join(qids)

    text = "\n\n".join(rendered_paragraphs)

    # Look up QID for this page's title
    page_title = page_data['title']
    page_qid = title_to_qid.get(page_title, "")

    # Filter out pages without Wikidata entries
    if not page_qid:
        return ('filtered', 'no_wikidata', {
            'id': page_data['id'],
            'title': page_title,
            'namespace': page_data['namespace'],
            'reason': 'no_wikidata'
        })

    wiki_uri = wikipedia_url(page_title)
    wikidata_uri = WIKIDATA_BASE + page_qid
    label = page_title.replace("_", " ")
    document_id = page_qid
    subjects = [{"uri": wikidata_uri, "label": label}]

    return {
        "document_id": document_id,
        "subjects": subjects,
        "metadata": {
            "uri": wiki_uri,
            **metadata_links,
        },
        "text": text,
    }


def _write_sorted(file_path, items):
    """Write sorted items to file. Items are (key, json_line) tuples."""
    items.sort(key=lambda x: x[0])
    with open(file_path, 'a', encoding='utf-8') as f:
        for _, json_line in items:
            f.write(json_line + '\n')


def process_batch(args):
    """Process a batch, write sorted results to temp file, return count.
    
    Args:
        args: tuple of (batch, title_to_qid, temp_file_path, filtered_temp_file_path)
    Returns:
        tuple: (valid_count, filtered_count)
    """
    batch, title_to_qid, temp_file_path, filtered_temp_file_path = args
    results = []
    filtered_results = []
    
    for page_data in batch:
        row = page_data_to_jsonl(page_data, title_to_qid)
        if isinstance(row, tuple) and len(row) == 3 and row[0] == 'filtered':
            # This is a filtered item
            _, _, filtered_info = row
            filtered_results.append((filtered_info['id'], json.dumps(filtered_info, ensure_ascii=False)))
        elif row is not None:
            # This is a valid result
            results.append((row['document_id'], json.dumps(row, ensure_ascii=False)))
    
    _write_sorted(temp_file_path, results)
    _write_sorted(filtered_temp_file_path, filtered_results)
    
    return len(results), len(filtered_results)


def kway_merge_sorted_files(file_paths, output_stream, key_field='document_id'):
    """Perform a k-way merge of sorted JSONL files.
    
    Args:
        file_paths: list of file paths to merge
        output_stream: file-like object to write merged output to
        key_field: the JSON field to use as the sort key (default: 'document_id')
    """
    files = [open(fp, 'r', encoding='utf-8') for fp in file_paths]

    def gen(file):
        for line in file:
            line = line.strip()
            if line:
                doc = json.loads(line)
                yield (doc[key_field], line)

    generators = [gen(f) for f in files]
    merged = heapq.merge(*generators, key=lambda x: x[0])

    for _, line in merged:
        print(line, file=output_stream)

    for f in files:
        f.close()


def batch_generator(stream, batch_size=DEFAULT_BATCH_SIZE, max_batches=DEFAULT_MAX_BATCHES):
    """Generator that yields batches of page data from the dump."""
    dump = mwxml.Dump.from_file(stream)
    current_batch = []
    batch_index = 0

    for page in dump:
        current_batch.append(extract_page_data(page))
        if len(current_batch) >= batch_size:
            yield batch_index, current_batch
            batch_index += 1
            if max_batches is not None and batch_index >= max_batches:
                break
            current_batch = []
    if current_batch and (max_batches is None or batch_index < max_batches):
        yield batch_index, current_batch


def process_batch_wrapper(args):
    """Wrapper to assign batch to correct worker temp file."""
    batch_index, batch, title_to_qid, temp_files, filtered_temp_files, num_workers = args
    worker_idx = batch_index % num_workers
    valid_count, filtered_count = process_batch((batch, title_to_qid, temp_files[worker_idx], filtered_temp_files[worker_idx]))
    return (batch_index, valid_count, filtered_count)


def process_dump_parallel(stream, title_to_qid, num_workers, batch_size=DEFAULT_BATCH_SIZE, max_batches=DEFAULT_MAX_BATCHES):
    """Process dump in parallel with multiple workers."""
    with tempfile.TemporaryDirectory() as temp_dir:
        temp_files = [
            os.path.join(temp_dir, f'worker_{i}.jsonl')
            for i in range(num_workers)
        ]
        
        filtered_temp_files = [
            os.path.join(temp_dir, f'worker_{i}.filtered.jsonl')
            for i in range(num_workers)
        ]
        for fp in filtered_temp_files:
            open(fp, 'w').close()

        for fp in temp_files:
            open(fp, 'w').close()

        with multiprocessing.Pool(processes=num_workers) as pool:
            gen = batch_generator(stream, batch_size, max_batches=max_batches)
            args_gen = (
                (batch_idx, batch, title_to_qid, temp_files, filtered_temp_files, num_workers)
                for batch_idx, batch in gen
            )

            running_total = 0
            running_filtered_total = 0
            for batch_idx, valid_count, filtered_count in pool.imap(process_batch_wrapper, args_gen):
                running_total += valid_count
                running_filtered_total += filtered_count
                print(f"Completed batch {batch_idx}: {running_total} valid, {running_filtered_total} filtered", file=sys.stderr)

        # Merge and output valid results
        kway_merge_sorted_files(temp_files, sys.stdout)
        
        # Write filtered results to hardcoded file
        with open(FILTERED_OUTPUT_FILE, 'w', encoding='utf-8') as filtered_out:
            kway_merge_sorted_files(filtered_temp_files, filtered_out, key_field='id')


def main():
    num_workers = DEFAULT_NUM_WORKERS
    batch_size = DEFAULT_BATCH_SIZE
    max_batches = DEFAULT_MAX_BATCHES

    args = sys.argv[1:]
    sitelinks_path = args[0] if args else None

    title_to_qid = load_sitelinks(sitelinks_path) if sitelinks_path else {}

    stream = sys.stdin.buffer
    try:
        process_dump_parallel(
            stream,
            title_to_qid,
            num_workers=num_workers,
            batch_size=batch_size,
            max_batches=max_batches
        )
    finally:
        pass


if __name__ == "__main__":
    main()
