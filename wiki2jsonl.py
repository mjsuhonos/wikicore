#!/usr/bin/env python3

import gc
import heapq
import json
import multiprocessing
import os
import re
import sys
import tempfile
from urllib.parse import quote

from lxml import etree as ET
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

try:
    multiprocessing.set_start_method('fork')
except RuntimeError:
    pass

# Configuration constants
DEFAULT_BATCH_SIZE = 1000
DEFAULT_MAX_BATCHES = None  # Process all batches by default
FILTERED_OUTPUT_FILE = 'filtered.jsonl'

# MediaWiki XML namespace
MW_NS = "http://www.mediawiki.org/xml/export-0.10/"


def wikipedia_url(title):
    """Turn a MediaWiki article title into a Wikipedia URL."""
    title = str(title).strip()
    title = title.split("#", 1)[0].strip()
    title = re.sub(r"\s+", "_", title)
    return WIKIPEDIA_BASE + quote(title, safe=";:@$!*(),/~")


def is_article_link(link):
    """Return True for links to normal Wikipedia articles."""
    title = str(link.title).strip()
    return bool(title) and ":" not in title


def extract_intro(code):
    """Return everything before the first section heading, excluding templates."""
    nodes = []
    for node in code.nodes:
        if isinstance(node, Heading):
            break
        # Skip template nodes to prevent them from appearing in the output
        if not isinstance(node, Template):
            nodes.append(node)
    return mwparserfromhell.parse("".join(str(node) for node in nodes))


def extract_paragraphs(code):
    """Split intro wikitext into blank-line-separated paragraphs."""
    text = str(code)
    text = text.replace("\r\n", "\n").replace("\r", "\n")
    paragraphs = re.split(r"\n\s*\n", text)
    return [
        mwparserfromhell.parse(p.strip())
        for p in paragraphs
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
    # Remove magic words like __NOTOC__, __TOC__, etc.
    text = re.sub(r'__[A-Z_]+__', '', text)
    text = text.replace("'''", "").replace("'", "")
    text = re.sub(r"[ \t]+", " ", text)
    text = re.sub(r"[ \t]+\n", "\n", text)
    text = re.sub(r"\n[ \t]+", "\n", text)
    return text.strip()


def render_paragraph(code):
    """Return (plain_text, wikipedia_links) for one paragraph."""
    text, links = render_wikicode(code)
    return clean_text(text), links


def latest_revision(page_element):
    """Return the last revision element in the page element.
    
    Uses direct child iteration to avoid creating a large list of all revisions.
    """
    target_tag = f'{{{MW_NS}}}revision'
    latest = None
    for child in page_element:
        if child.tag == target_tag:
            latest = child
    return latest


def load_sitelinks(sitelinks_path):
    """Load sitelinks file and return a compact mapping from Wikipedia title to Wikidata Q-ID.
    
    This is memory-efficient: stores only the essential parts of URIs rather than full URIs.
    
    Input format: <wikidata_uri>\t<wikipedia_uri>
    Example: <http://www.wikidata.org/entity/Q42>\t<https://en.wikipedia.org/wiki/Douglas_Adams>
    
    Stored as: {"Douglas_Adams": "Q42"}
    
    This reduces memory usage by ~75-80% compared to storing full URIs.
    For a sitelinks file with 100M entries, this saves ~15-20GB of memory.
    """
    title_to_qid = {}
    wikidata_prefix = "http://www.wikidata.org/entity/"
    wikipedia_prefix = "https://en.wikipedia.org/wiki/"
    wikidata_prefix_len = len(wikidata_prefix)
    wikipedia_prefix_len = len(wikipedia_prefix)
    
    with open(sitelinks_path, 'r') as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            parts = line.split('\t')
            if len(parts) >= 2:
                # Extract Q-ID from Wikidata URI
                wikidata_uri = parts[0].strip().lstrip('<').rstrip('>')
                if wikidata_uri.startswith(wikidata_prefix):
                    qid = wikidata_uri[wikidata_prefix_len:]
                else:
                    continue
                
                # Extract title from Wikipedia URI
                wikipedia_uri = parts[1].strip().lstrip('<').rstrip('>')
                if wikipedia_uri.startswith(wikipedia_prefix):
                    title = wikipedia_uri[wikipedia_prefix_len:]
                else:
                    continue
                
                if title and qid:
                    title_to_qid[title] = qid
    return title_to_qid


def extract_page_data(page_element):
    """Extract picklable data from an lxml page element for parallel processing.
    
    Uses direct child iteration to minimize memory and maximize speed.
    """
    target_tag = f'{{{MW_NS}}}'
    
    title = None
    page_id = None
    redirect = False
    namespace = 0
    
    for child in page_element:
        tag = child.tag
        if tag == target_tag + 'title':
            title = child.text
        elif tag == target_tag + 'id':
            if child.text:
                try:
                    page_id = int(child.text)
                except (ValueError, TypeError):
                    page_id = None
        elif tag == target_tag + 'redirect':
            redirect = True
        elif tag == target_tag + 'ns':
            if child.text:
                try:
                    namespace = int(child.text)
                except (ValueError, TypeError):
                    namespace = 0
    
    revision = latest_revision(page_element)
    text = None
    if revision is not None:
        text_tag = target_tag + 'text'
        for child in revision:
            if child.tag == text_tag:
                text = child.text
                break
    
    return {
        'title': title,
        'id': page_id,
        'redirect': redirect,
        'namespace': namespace,
        'text': text,
    }


def page_data_to_jsonl(page_data, title_to_qid):
    """Convert page data dict to JSON Lines object.
    
    Args:
        page_data: dict with page data
        title_to_qid: dict mapping Wikipedia page titles to Wikidata Q-IDs
    
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

    # Pre-compute the Wikipedia URL for the page
    wiki_uri = wikipedia_url(page_data['title'])
    
    for paragraph in paragraphs:
        text, links = render_paragraph(paragraph)
        if not text:
            continue

        number = len(rendered_paragraphs) + 1
        rendered_paragraphs.append(text)

        qids = []
        for link in links:
            # Extract title from Wikipedia URL to look up in compact mapping
            # link is a full URL like "https://en.wikipedia.org/wiki/Article_Name"
            title = link[len("https://en.wikipedia.org/wiki/"):] if link.startswith("https://en.wikipedia.org/wiki/") else None
            if title:
                qid = title_to_qid.get(title, "")
                if qid:
                    qids.append(qid)

        if qids:
            metadata_links[str(number)] = ",".join(qids)

    text = "\n\n".join(rendered_paragraphs)

    # Look up Wikidata Q-ID for the page itself
    qid = title_to_qid.get(page_data['title'], "")
    
    # Filter out pages without Wikidata entries
    if not qid:
        return ('filtered', 'no_wikidata', {
            'id': page_data['id'],
            'title': page_data['title'],
            'namespace': page_data['namespace'],
            'reason': 'no_wikidata'
        })

    # Reconstruct full Wikidata URI from Q-ID
    wikidata_uri = f"http://www.wikidata.org/entity/{qid}"
    label = page_data['title'].replace("_", " ")
    subjects = [{"uri": wikidata_uri, "label": label}]
    document_id = qid

    return {
        "document_id": document_id,
        "subjects": subjects,
        "metadata": {
            "uri": wiki_uri,
            **metadata_links,
        },
        "text": text,
    }


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
    
    # Sort and write valid results
    results.sort(key=lambda x: x[0])
    with open(temp_file_path, 'a', encoding='utf-8') as f:
        for doc_id, json_line in results:
            f.write(json_line + '\n')
    
    # Sort and write filtered results
    filtered_results.sort(key=lambda x: x[0])
    with open(filtered_temp_file_path, 'a', encoding='utf-8') as f:
        for item_id, json_line in filtered_results:
            f.write(json_line + '\n')
    
    return len(results), len(filtered_results)


def kway_merge_sorted_files(file_paths, output_stream):
    """Perform a k-way merge of sorted JSONL files, outputting sorted by document_id."""
    files = [open(fp, 'r', encoding='utf-8') for fp in file_paths]

    def gen(file):
        for line in file:
            line = line.strip()
            if line:
                doc = json.loads(line)
                yield (doc['document_id'], line)

    generators = [gen(f) for f in files]
    merged = heapq.merge(*generators, key=lambda x: x[0])

    for doc_id, line in merged:
        print(line, file=output_stream)

    for f in files:
        f.close()


def kway_merge_sorted_filtered_files(file_paths, output_stream):
    """Perform a k-way merge of sorted filtered JSONL files, outputting sorted by id."""
    files = [open(fp, 'r', encoding='utf-8') for fp in file_paths]

    def gen(file):
        for line in file:
            line = line.strip()
            if line:
                doc = json.loads(line)
                yield (doc['id'], line)

    generators = [gen(f) for f in files]
    merged = heapq.merge(*generators, key=lambda x: x[0])

    for item_id, line in merged:
        print(line, file=output_stream)

    for f in files:
        f.close()


def batch_generator(stream, batch_size=DEFAULT_BATCH_SIZE, max_batches=DEFAULT_MAX_BATCHES):
    """Generator that yields batches of page data from the dump using lxml streaming.
    
    Uses iterparse with tag filtering to only process <page> elements,
    and aggressively clears parsed elements to keep memory low and maximize speed.
    """
    context = ET.iterparse(
        stream,
        events=('end',),
        tag=f'{{{MW_NS}}}page',
        remove_blank_text=True,
        no_network=True,
        resolve_entities=False,
        huge_tree=True
    )
    
    current_batch = []
    batch_index = 0
    
    for event, page_element in context:
        page_data = extract_page_data(page_element)
        current_batch.append(page_data)
        
        # Aggressively clear memory
        page_element.clear()
        parent = page_element.getparent()
        if parent is not None:
            while page_element.getprevious() is not None:
                del parent[0]
        
        if len(current_batch) % 100 == 0:
            gc.collect()
        
        if len(current_batch) >= batch_size:
            yield batch_index, current_batch
            batch_index += 1
            if max_batches is not None and batch_index >= max_batches:
                break
            current_batch = []
            gc.collect()
    
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
            kway_merge_sorted_filtered_files(filtered_temp_files, filtered_out)


def main():
    num_workers = os.cpu_count()
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
