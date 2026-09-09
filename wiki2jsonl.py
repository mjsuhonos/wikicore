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

try:
    multiprocessing.set_start_method('fork')
except RuntimeError:
    pass


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
    if page_data['redirect'] or page_data['text'] is None:
        return None

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
            wd = wikipedia_to_wikidata.get(link, "")
            if wd:
                qids.append(wd.split('/')[-1])

        if qids:
            metadata_links[str(number)] = ",".join(qids)

    text = "\n\n".join(rendered_paragraphs)

    wiki_uri = wikipedia_url(page_data['title'])
    wikidata_uri = wikipedia_to_wikidata.get(wiki_uri, "")

    if wikidata_uri:
        label = page_data['title'].replace("_", " ")
        subjects = [{"uri": wikidata_uri, "label": label}]
        document_id = wikidata_uri.split('/')[-1]
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
    """Process dump in parallel with multiple workers."""
    with tempfile.TemporaryDirectory() as temp_dir:
        temp_files = [
            os.path.join(temp_dir, f'worker_{i}.jsonl')
            for i in range(num_workers)
        ]

        for fp in temp_files:
            open(fp, 'w').close()

        with multiprocessing.Pool(processes=num_workers) as pool:
            gen = batch_generator(stream, batch_size)
            args_gen = (
                (batch_idx, batch, wikipedia_to_wikidata, temp_files, num_workers)
                for batch_idx, batch in gen
            )

            running_total = 0
            for batch_idx, result_count in pool.imap(process_batch_wrapper, args_gen):
                running_total += result_count
                print(f"Completed batch {batch_idx}: {running_total} documents processed", file=sys.stderr)

        kway_merge_sorted_files(temp_files, sys.stdout)


def main():
    num_workers = os.cpu_count()
    batch_size = 5000

    args = sys.argv[1:]
    positional_args = []

    sitelinks_path = positional_args[0] if positional_args else None

    wikipedia_to_wikidata = load_sitelinks(sitelinks_path) if sitelinks_path else {}

    stream = sys.stdin.buffer
    try:
        process_dump_parallel(
            stream,
            wikipedia_to_wikidata,
            num_workers=num_workers,
            batch_size=batch_size
        )
    finally:
        pass


if __name__ == "__main__":
    main()
