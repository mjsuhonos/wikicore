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


# Use fork start method for better performance with queues on Unix
# (must be set before any Process is created)
try:
    multiprocessing.set_start_method('fork')
except RuntimeError:
    pass  # Already set or not supported


def wikipedia_url(title):
    """Turn a MediaWiki article title into a Wikipedia URL."""
    title = str(title).strip()

    # Remove anchors/fragments.
    title = title.split("#", 1)[0].strip()

    # Normalize whitespace.
    title = re.sub(r"\s+", "_", title)

    # Wikipedia's article URLs need URL encoding, but retain common
    # characters that are valid in MediaWiki titles.
    return WIKIPEDIA_BASE + quote(
        title,
        safe="_-().:/"
    )


def is_article_link(link):
    """Return True for links to normal Wikipedia articles."""
    title = str(link.title).strip()

    if not title:
        return False

    # Ignore namespace links, interwiki links, etc.
    # This excludes things such as:
    #   File:Foo.jpg
    #   Category:Foo
    #   Wikipedia:Foo
    #   de:Foo
    if ":" in title:
        return False

    return True


def extract_intro(code):
    """Return everything before the first section heading."""
    nodes = []

    for node in code.nodes:
        if isinstance(node, Heading):
            break
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
    """
    Render one wikitext node to plain text while collecting Wikipedia
    link occurrences.

    Returns:
        (text, links)
    """

    # Ordinary text.
    if isinstance(node, Text):
        return str(node), []

    # Comments should not appear in the text.
    if isinstance(node, Comment):
        return "", []

    # Templates such as {{cite journal ...}} are metadata/markup,
    # not article text. Don't render them, and don't extract links
    # from inside them.
    if isinstance(node, Template):
        return "", []

    # Wiki links.
    if isinstance(node, Wikilink):
        if is_article_link(node):
            url = wikipedia_url(node.title)

            # The visible text is the part after the pipe.
            if node.text is not None:
                visible = render_wikicode(node.text)
            else:
                visible = render_wikicode(node.title)

            return visible[0], [url] + visible[1]

        # Non-article wikilinks (File:, Category:, etc.) - don't render their text
        return "", []

    # HTML / MediaWiki tags.
    if isinstance(node, Tag):
        tag = str(node.tag).lower().strip()

        # References/citations should disappear completely.
        if tag in {
            "ref",
            "references",
            "gallery",
            "timeline",
            "math",
            "source",
            "syntaxhighlight",
        }:
            return "", []

        # For ordinary inline/container tags, retain their contents.
        if node.contents is not None:
            return render_wikicode(node.contents)

        return "", []

    # HTML entities such as &nbsp;.
    if isinstance(node, HTMLEntity):
        return str(node), []

    # Anything else: render its textual representation.
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

    # Remove MediaWiki bold/italic markers that may remain in text.
    text = text.replace("'''", "")
    text = text.replace("'", "")

    # Normalize horizontal whitespace.
    text = re.sub(r"[ \t]+", " ", text)

    # Remove whitespace immediately after/before newlines.
    text = re.sub(r"[ \t]+\n", "\n", text)
    text = re.sub(r"\n[ \t]+", "\n", text)

    return text.strip()


def render_paragraph(code):
    """Return (plain_text, wikipedia_links) for one paragraph."""
    text, links = render_wikicode(code)
    return clean_text(text), links


def latest_revision(page):
    """Return the last revision in the page."""
    revision = None

    for rev in page:
        revision = rev

    return revision


def load_sitelinks(sitelinks_path):
    """Load sitelinks file and return a mapping from Wikipedia URI to Wikidata URI."""
    wikipedia_to_wikidata = {}
    
    with open(sitelinks_path, 'r') as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            parts = line.split('\t')
            if len(parts) >= 2:
                wikidata_uri = parts[0].strip().lstrip('<').rstrip('>')
                wikipedia_uri = parts[1].strip().lstrip('<').rstrip('>')
                wikipedia_to_wikidata[wikipedia_uri] = wikidata_uri
    
    return wikipedia_to_wikidata


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


def page_data_to_jsonl(page_data, wikipedia_to_wikidata):
    """Convert page data dict to JSON Lines object."""
    # Redirects aren't article documents.
    if page_data['redirect']:
        return None

    if page_data['text'] is None:
        return None

    code = mwparserfromhell.parse(page_data['text'])

    intro = extract_intro(code)
    paragraphs = extract_paragraphs(intro)

    rendered_paragraphs = []
    metadata_links = {}

    # Number paragraphs AFTER rendering/filtering, so the first
    # emitted paragraph is always "1".
    for paragraph in paragraphs:
        text, links = render_paragraph(paragraph)

        if not text:
            continue

        number = len(rendered_paragraphs) + 1
        rendered_paragraphs.append(text)

        # Convert Wikipedia URIs to QIDs for this paragraph
        qids = []
        for link in links:
            wd = wikipedia_to_wikidata.get(link, "")
            if wd:
                # Extract just the QID part
                qid = wd.split('/')[-1]
                qids.append(qid)
        
        # Store as comma-separated QIDs with paragraph number as key
        # Only include if there are QIDs (non-empty paragraphs)
        if qids:
            metadata_links[str(number)] = ",".join(qids)

    text = "\n\n".join(rendered_paragraphs)
    
    # Look up Wikidata URI for this page
    wiki_uri = wikipedia_url(page_data['title'])
    wikidata_uri = wikipedia_to_wikidata.get(wiki_uri, "")
    
    # Extract label from page title (replace underscores with spaces)
    if wikidata_uri:
        label = page_data['title'].replace("_", " ")
        subjects = [{"uri": wikidata_uri, "label": label}]
        document_id = wikidata_uri.split('/')[-1]  # Extract QID for document_id
    else:
        subjects = []
        document_id = str(page_data['id'])

    return {
        "document_id": document_id,
        "text": text,
        "subjects": subjects,
        "metadata": {
            "uri": wiki_uri,
            **metadata_links,
        },
    }


def page_to_jsonl(page, wikipedia_to_wikidata):
    """Convert one mwxml Page into a JSON Lines object."""
    page_data = extract_page_data(page)
    return page_data_to_jsonl(page_data, wikipedia_to_wikidata)


# =============================================================================
# Parallel Processing Implementation
# =============================================================================


def process_batch(args):
    """Process a batch, write sorted results to temp file, return count."""
    batch, wikipedia_to_wikidata, temp_file_path = args
    results = []
    for page_data in batch:
        row = page_data_to_jsonl(page_data, wikipedia_to_wikidata)
        if row is not None:
            results.append((row['document_id'], json.dumps(row, ensure_ascii=False)))
    results.sort(key=lambda x: x[0])
    with open(temp_file_path, 'a', encoding='utf-8') as f:
        for doc_id, json_line in results:
            f.write(json_line + '\n')
    return len(results)


def kway_merge_sorted_files(file_paths, output_stream):
    """
    Perform a k-way merge of sorted JSONL files, outputting sorted by document_id.
    Each input file is sorted by document_id.
    """
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


def batch_generator(stream, batch_size):
    """Generator that yields batches of page data from the dump."""
    dump = mwxml.Dump.from_file(stream)
    current_batch = []
    batch_index = 0
    
    for page in dump:
        if page.namespace != 0:
            continue
        current_batch.append(extract_page_data(page))
        if len(current_batch) >= batch_size:
            yield batch_index, current_batch
            batch_index += 1
            current_batch = []
    if current_batch:
        yield batch_index, current_batch


def process_batch_wrapper(args):
    """Wrapper to assign batch to correct worker temp file."""
    batch_index, batch, wikipedia_to_wikidata, temp_files, num_workers = args
    worker_idx = batch_index % num_workers
    result_count = process_batch((batch, wikipedia_to_wikidata, temp_files[worker_idx]))
    return (batch_index, result_count)


def process_dump_parallel(stream, wikipedia_to_wikidata, num_workers, batch_size):
    """
    Process dump in parallel with multiple workers.
    Uses temp files for intermediate storage and k-way merge for sorted output.
    """
    with tempfile.TemporaryDirectory() as temp_dir:
        temp_files = [
            os.path.join(temp_dir, f'worker_{i}.jsonl')
            for i in range(num_workers)
        ]

        # Pre-create temp files
        for fp in temp_files:
            open(fp, 'w').close()

        # Use Pool.imap for ordered results (enables accurate running total)
        with multiprocessing.Pool(processes=num_workers) as pool:
            # Create generator for batches (doesn't load all into memory)
            gen = batch_generator(stream, batch_size)
            
            # Process batches in parallel as they are generated
            args_gen = (
                (batch_idx, batch, wikipedia_to_wikidata, temp_files, num_workers)
                for batch_idx, batch in gen
            )
            
            # Consume the generator to process all batches, track running total
            running_total = 0
            for batch_idx, result_count in pool.imap(process_batch_wrapper, args_gen):
                running_total += result_count
                print(f"Completed batch {batch_idx}: {running_total} documents processed", file=sys.stderr)

        # Merge sorted temp files and output
        kway_merge_sorted_files(temp_files, sys.stdout)


def process_dump(stream, wikipedia_to_wikidata):
    """Stream pages from a MediaWiki XML dump and output as JSON Lines."""
    dump = mwxml.Dump.from_file(stream)
    batch_size = 10000
    current_batch = []
    batch_index = 0
    running_total = 0

    for page in dump:
        # Namespace 0 = normal articles.
        if page.namespace != 0:
            continue

        current_batch.append(extract_page_data(page))

        if len(current_batch) >= batch_size:
            # Process the batch
            doc_count = 0
            for page_data in current_batch:
                row = page_data_to_jsonl(page_data, wikipedia_to_wikidata)
                if row is not None:
                    try:
                        print(json.dumps(row, ensure_ascii=False))
                    except BrokenPipeError:
                        sys.exit(0)
                    doc_count += 1
            running_total += doc_count
            print(f"Completed batch {batch_index}: {running_total} documents processed", file=sys.stderr)
            batch_index += 1
            current_batch = []

    # Process remaining pages in the last batch
    if current_batch:
        doc_count = 0
        for page_data in current_batch:
            row = page_data_to_jsonl(page_data, wikipedia_to_wikidata)
            if row is not None:
                try:
                    print(json.dumps(row, ensure_ascii=False))
                except BrokenPipeError:
                    sys.exit(0)
                doc_count += 1
        running_total += doc_count
        print(f"Completed batch {batch_index}: {running_total} documents processed", file=sys.stderr)


def parse_parallel_args():
    """Parse parallel processing specific arguments from sys.argv."""
    # Default values
    workers = 1
    batch_size = 10000
    
    # Track which arguments are consumed by flags
    consumed = [False] * len(sys.argv)
    consumed[0] = True  # script name
    
    # Parse known flags and their values from ALL arguments
    i = 1
    while i < len(sys.argv):
        if consumed[i]:
            i += 1
            continue
        arg = sys.argv[i]
        if arg == '-j' or arg == '--workers' or (arg.startswith('-j') and len(arg) > 2):
            consumed[i] = True
            # Handle -jN syntax (e.g., -j0, -j4) where value is concatenated
            if arg.startswith('-j') and len(arg) > 2:
                try:
                    workers = int(arg[2:])
                    i += 1
                except ValueError:
                    workers = os.cpu_count()
                    i += 1
            elif i + 1 < len(sys.argv) and not sys.argv[i + 1].startswith('-'):
                # Only consume next arg if it doesn't look like a flag
                try:
                    workers = int(sys.argv[i + 1])
                    consumed[i + 1] = True
                    i += 2
                except ValueError:
                    # Next arg is not a valid integer, treat -j as flag without value
                    workers = os.cpu_count()
                    i += 1
            else:
                # -j without value: use all CPUs
                workers = os.cpu_count()
                i += 1
        elif arg == '-b' or arg == '--batch-size':
            consumed[i] = True
            if i + 1 < len(sys.argv) and not sys.argv[i + 1].startswith('-'):
                try:
                    batch_size = int(sys.argv[i + 1])
                    consumed[i + 1] = True
                    i += 2
                except ValueError:
                    i += 1
            else:
                i += 1
        elif arg.startswith('-'):
            # Unknown flag, skip it
            consumed[i] = True
            i += 1
        else:
            # Positional argument, skip but continue parsing
            i += 1
    
    # -j 0 means all CPUs
    if workers == 0:
        workers = os.cpu_count()
    
    # Build list of non-consumed arguments (positional args only)
    positional_args = []
    for i in range(1, len(sys.argv)):
        if not consumed[i]:
            positional_args.append(sys.argv[i])
    
    return workers, batch_size, positional_args


def main():
    # Parse parallel processing arguments first
    workers, batch_size, remaining_args = parse_parallel_args()

    # Determine sitelinks file path and dump path from remaining args
    sitelinks_path = None
    wikipedia_dump_path = None

    # Check if we have positional arguments
    if len(remaining_args) > 0:
        if remaining_args[0] == '-':
            # '-' means read dump from stdin
            if len(remaining_args) > 1:
                sitelinks_path = remaining_args[1]
        else:
            # First arg could be either dump file or sitelinks file
            if sys.stdin.isatty():
                # stdin is a terminal, so first arg is dump file
                wikipedia_dump_path = remaining_args[0]
                if len(remaining_args) > 1:
                    sitelinks_path = remaining_args[1]
            else:
                # stdin has data from pipe, so first arg is sitelinks file
                sitelinks_path = remaining_args[0]
                if len(remaining_args) > 1:
                    wikipedia_dump_path = remaining_args[1]

    # Load sitelinks if path is provided
    if sitelinks_path:
        wikipedia_to_wikidata = load_sitelinks(sitelinks_path)
    else:
        # Try default path
        try:
            wikipedia_to_wikidata = load_sitelinks("working.nosync/enwiki_sitelinks.tsv")
        except FileNotFoundError:
            wikipedia_to_wikidata = {}

    # Determine dump source
    if wikipedia_dump_path:
        stream = open(wikipedia_dump_path, "rb")
    else:
        stream = sys.stdin.buffer

    try:
        # Choose processing mode: parallel if workers > 1
        if workers > 1:
            process_dump_parallel(
                stream,
                wikipedia_to_wikidata,
                num_workers=workers,
                batch_size=batch_size
            )
        else:
            process_dump(stream, wikipedia_to_wikidata)
    finally:
        if wikipedia_dump_path:
            stream.close()


if __name__ == "__main__":
    main()
