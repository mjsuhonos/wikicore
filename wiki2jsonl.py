#!/usr/bin/env python3

import json
import multiprocessing
import os
import re
import sys
import tempfile
from urllib.parse import quote, unquote

import mwxml
import wikitextparser as wtp

# wikitextparser doesn't have node classes like mwparserfromhell
# We'll use its high-level API instead

WIKIPEDIA_BASE = "https://en.wikipedia.org/wiki/"
WIKIDATA_BASE = "http://www.wikidata.org/entity/"

# Pre-compute lengths for faster prefix stripping
WIKIPEDIA_BASE_LEN = len(WIKIPEDIA_BASE)
WIKIDATA_BASE_LEN = len(WIKIDATA_BASE)

# Global variable for Wikidata title-to-QID mapping
# With multiprocessing 'fork' method, this is inherited by worker processes
# via copy-on-write, avoiding expensive serialization
GLOBAL_TITLE_TO_QID = None

try:
    multiprocessing.set_start_method('fork')
except RuntimeError:
    pass

# Configuration constants
DEFAULT_NUM_WORKERS = 4 #round(os.cpu_count() * 3 / 4)
DEFAULT_BATCH_SIZE = 10000
DEFAULT_MAX_BATCHES = None  # Process all batches by default
FILTERED_OUTPUT_FILE = 'unmapped.jsonl'

# Maximum text size to keep (in characters) - truncate intro to this length
MAX_TEXT_SIZE = 10000

def wikipedia_url(title):
    """Turn a MediaWiki article title into a Wikipedia URL."""
    title = str(title).strip()
    title = title.split("#", 1)[0].strip()
    title = title.replace(" ", "_")
    return WIKIPEDIA_BASE + quote(title, safe=";:@$!*(),/~")


def extract_intro_text(text):
    """Return the intro text (before first section heading), excluding templates.
    
    Removes from lead section:
    - All templates (including nested ones) like infoboxes, citations
    - Filters out nested templates to avoid offset issues when removing
    - Removes all top-level structural elements from the lead section
    - Parser functions ({{#ifeq:...}}, {{#expr:...}}, etc.)
    - Tables ({|...|})
    - Comments (<!-- ... -->)
    - Lists with their markers (*, #, :, etc.)
    """
    parsed = wtp.parse(text)
    
    # Get the lead section (before first == heading)
    # sections[0] is the text before the first heading
    if parsed.sections:
        lead_section = parsed.sections[0]
        lead_text = str(lead_section)
    else:
        # No sections found, use the whole text
        lead_text = str(parsed)
    
    # Parse the lead text to remove unwanted elements
    lead_parsed = wtp.parse(lead_text)
    
    # Collect all spans to remove (structural elements with no content value)
    spans_to_remove = []
    
    # 1. Templates (infoboxes, citations, etc.) - remove top-level only
    all_templates = list(lead_parsed.templates)
    
    if all_templates:
        # Filter out nested templates to avoid offset issues
        templates_sorted = sorted(all_templates, key=lambda t: t.span[0])
        top_level_templates = []
        for i, t in enumerate(templates_sorted):
            is_nested = False
            # Optimization: only check against previous templates
            for j in range(i):
                other = templates_sorted[j]
                # If t is inside other, t is nested
                if other.span[0] <= t.span[0] and other.span[1] >= t.span[1]:
                    is_nested = True
                    break
            if not is_nested:
                top_level_templates.append(t)
        
        for t in top_level_templates:
            spans_to_remove.append(t.span)
    
    # 2. Parser functions ({{#ifeq:...}}, {{#expr:...}}, etc.)
    for pf in lead_parsed.parser_functions:
        spans_to_remove.append(pf.span)
    
    # 3. Tables ({|...|})
    for table in lead_parsed.tables:
        spans_to_remove.append(table.span)
    
    # 4. Comments (<!-- ... -->)
    for comment in lead_parsed.comments:
        spans_to_remove.append(comment.span)
    
    # 5. Lists (with markers like *, #, :, etc.)
    for lst in lead_parsed.get_lists():
        spans_to_remove.append(lst.span)
    
    # Sort by start position and remove in reverse order to avoid offset issues
    spans_to_remove.sort(key=lambda x: x[0])
    result_text = lead_text
    for start, end in reversed(spans_to_remove):
        result_text = result_text[:start] + result_text[end:]
    
    return result_text


def extract_paragraphs_text(intro_text):
    """Split intro text into blank-line-separated paragraphs.
    Returns a list of paragraph text strings.
    """
    # Split by blank lines (same as original logic)
    return [
        p.strip()
        for p in re.split(r"\n\s*\n", intro_text)
        if p.strip()
    ]


def render_paragraph_text_wtp(paragraph_text, title_to_qid):
    """Render a paragraph of wikitext to plain text and extract Wikipedia links.

    Handles:
    - External links [http://...] -> preserves link text via clean_text
    - HTML tags <ref>, <br>, etc. -> removed before plain_text() to avoid
      extracting their content (e.g., <ref>citation</ref> -> "citation")
    - Non-article wikilinks (File:, Category:, etc.) -> removed before plain_text()
      to avoid their titles appearing in output
    - Article wikilinks -> extracts displayed text, preserves in output
    
    Returns tuple of (cleaned_text, list_of_wikipedia_urls).
    """
    parsed = wtp.parse(paragraph_text)
    
    # Remove unwanted elements BEFORE getting plain text.
    # We need to do this on the raw text, then re-parse.
    text_clean = paragraph_text
    
    # 1. Remove HTML tags (prevents <ref>citation</ref> -> "citation")
    for tag in sorted(parsed.get_tags(), key=lambda t: t.span[0], reverse=True):
        start, end = tag.span
        text_clean = text_clean[:start] + text_clean[end:]
    
    # 2. Remove non-article wikilinks (File:, Category:, etc.)
    # These would appear as their title in plain_text() if not removed
    for wl in sorted(parsed.wikilinks, key=lambda w: w.span[0], reverse=True):
        title = str(wl.title).strip() if wl.title else ""
        if title and ":" in title:  # Non-article link (File:, Category:, etc.)
            start, end = wl.span
            text_clean = text_clean[:start] + text_clean[end:]
    
    # Now parse cleaned text and get plain text
    parsed_clean = wtp.parse(text_clean)
    plain = parsed_clean.plain_text()
    
    # Get wikilinks from original parse (before cleaning)
    # We use the original because we need all wikilink objects
    links = []
    for wl in parsed.wikilinks:
        # Check if this is an article link (not File:, Category:, etc.)
        if is_article_link_wtp(wl):
            url = wikipedia_url_wtp(wl)
            links.append(url)
    
    return clean_text(plain), links


def is_article_link_wtp(wikilink):
    """Check if a wikitextparser WikiLink is an article link (not File:, Category:, etc.)"""
    # wikitextparser WikiLink has .title attribute
    title = str(wikilink.title).strip() if wikilink.title else ""
    return bool(title) and ":" not in title


def wikipedia_url_wtp(wikilink):
    """Turn a wikitextparser WikiLink into a Wikipedia URL."""
    title = str(wikilink.title).strip() if wikilink.title else ""
    title = title.split("#", 1)[0].strip()
    title = title.replace(" ", "_")
    return WIKIPEDIA_BASE + quote(title, safe=";:@$!*(),/~")


def clean_text(text):
    """Normalize whitespace and remove formatting markers.
    
    Removes:
    - Magic words (like __NOTOC__, __TOC__, etc.)
    - Bold (''') and italic ('') markers
    - External link brackets [text] -> text (preserves the text)
    - HTML tags <...> (fallback for any that weren't removed earlier)
    - Comments <!-- ... --> (fallback)
    - Table syntax {|...|} (fallback)
    """
    # Remove magic words like __NOTOC__, __TOC__, etc.
    text = re.sub(r'__[A-Z_]+__', '', text)
    
    # Remove bold (''') and italic ('') markers
    text = text.replace("'''", "").replace("''", "")
    
    # Remove external link brackets but preserve the text inside
    # e.g., [http://example.com link text] -> link text
    text = re.sub(r'\[([^\]]+)\]', r'\1', text)
    
    # Remove HTML tags (fallback for any that weren't removed earlier)
    text = re.sub(r'<[^>]+>', '', text)
    
    # Remove comments (fallback)
    text = re.sub(r'<!--[^>]*-->', '', text)
    
    # Remove table syntax (fallback)
    text = re.sub(r'\{\|[^}]*\}\}', '', text)
    
    # Normalize all whitespace sequences to single spaces
    text = re.sub(r'[ \t]+', ' ', text)
    # Remove leading/trailing whitespace from lines and normalize newlines
    text = re.sub(r'[ \t]+\n', '\n', text)
    text = re.sub(r'\n[ \t]+', '\n', text)
    return text.strip()


def render_paragraph_text(paragraph_text):
    """Return (plain_text, wikipedia_links) for one paragraph.
    
    With wikitextparser: this is a wrapper that calls render_paragraph_text_wtp.
    """
    # We'll call render_paragraph_text_wtp, but we don't have title_to_qid here
    # Actually, we need title_to_qid to check if links have QIDs
    # But render_paragraph_text_wtp just extracts URLs, doesn't need title_to_qid
    return render_paragraph_text_wtp(paragraph_text, {})


def latest_revision(page):
    """Return the last revision in the page.
    """
    last = None
    for revision in page:
        last = revision
    return last


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
                # Decode URL-encoded characters (e.g., %C3%A9 -> é)
                title = unquote(title)
                # Convert URL-encoded underscores back to spaces to match Wikipedia dump titles
                title = title.replace("_", " ")
            else:
                continue
            title_to_qid[title] = qid
    return title_to_qid


def extract_page_data(page):
    """Extract picklable data from a mwxml Page for parallel processing.

    - Filters out pages based on namespace and redirect status early
    - Truncates text to MAX_TEXT_SIZE characters
    - Skips text extraction for filtered pages
    """
    # Early filtering: namespace and redirect checks
    if page.namespace != 0:
        return None
    
    if page.redirect:
        return None
    
    revision = latest_revision(page)
    if revision is None or revision.text is None:
        return None
    
    text = revision.text
    
    # Simple truncation: keep only first MAX_TEXT_SIZE characters
    # This significantly reduces data size before sending to workers
    if len(text) > MAX_TEXT_SIZE:
        text = text[:MAX_TEXT_SIZE]
    
    return {
        'title': page.title,
        'id': page.id,
        'redirect': page.redirect,
        'namespace': page.namespace,
        'text': text,
    }


def page_data_to_jsonl(page_data, title_to_qid):
    """Convert page data dict to JSON Lines object.
    
    Note: namespace and redirect filtering is already done in extract_page_data(),
    so we only check for text existence and Wikidata presence here.
    
    Args:
        page_data: dict with page metadata and text
        title_to_qid: mapping from Wikipedia article titles to Wikidata QIDs
    
    Returns:
        dict: JSON Lines object for valid pages
        tuple: ('filtered', reason, filtered_info) for filtered pages
    """
    page_title = page_data['title']
    # Defensive check for text (should already be filtered by extract_page_data)
    if page_data['text'] is None:
        return ('filtered', 'no_text', {
            'id': page_data['id'],
            'title': page_data['title'],
            'namespace': page_data['namespace'],
            'reason': 'no_text'
        })

    # Parse the full text with wikitextparser
    intro_text = extract_intro_text(page_data['text'])
    paragraph_texts = extract_paragraphs_text(intro_text)

    rendered_paragraphs = []
    metadata_links = {}

    for para_num, para_text in enumerate(paragraph_texts, 1):
        text, links = render_paragraph_text(para_text)
        if not text:
            continue

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
            metadata_links[str(para_num)] = ",".join(qids)

    text = "\n\n".join(rendered_paragraphs)
    
    if not text:  # Exclude pages with no valid text after extraction
        return ('filtered', 'empty_text', {
            'id': page_data['id'],
            'title': page_title,
            'namespace': page_data['namespace'],
            'reason': 'empty_text'
        })

    # Look up QID for this page's title
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
    """Write items to file without sorting (sorting done by Makefile)."""
    with open(file_path, 'a', encoding='utf-8') as f:
        for _, json_line in items:
            f.write(json_line + '\n')


def process_batch(args):
    """Process a batch, write results to temp file, return count.
    
    Uses GLOBAL_TITLE_TO_QID for Wikidata lookups (inherited via fork).
    Sorting is done by Makefile after all batches are processed.
    
    Args:
        args: tuple of (batch, temp_file_path, filtered_temp_file_path, num_workers)
    Returns:
        tuple: (valid_count, filtered_count)
    """
    batch, temp_file_path, filtered_temp_file_path = args
    results = []
    filtered_results = []
    
    for page_data in batch:
        # Check if this was pre-filtered (e.g., no_wikidata from batch_generator)
        if page_data.get('_filtered'):
            filtered_info = page_data['_filter_info']
            filtered_results.append((filtered_info['id'], json.dumps(filtered_info, ensure_ascii=False)))
            continue
        
        row = page_data_to_jsonl(page_data, GLOBAL_TITLE_TO_QID)
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


def kway_merge_sorted_files(file_paths, output_stream):
    """Concatenate files and add URI prefix. Sorting done by Makefile."""
    for fp in file_paths:
        with open(fp, 'r', encoding='utf-8') as f:
            for line in f:
                line = line.strip()
                if line:
                    doc = json.loads(line)
                    uri = doc.get('subjects', [{}])[0].get('uri', '')
                    if uri:
                        print(f"<{uri}>\t{line}", file=output_stream)


def batch_generator(stream, batch_size=DEFAULT_BATCH_SIZE, max_batches=DEFAULT_MAX_BATCHES):
    """Generator that yields batches of page data from the dump.
    
    Uses GLOBAL_TITLE_TO_QID for Wikidata lookups (inherited via fork).
    """
    dump = mwxml.Dump.from_file(stream)
    current_batch = []
    batch_index = 0

    for page in dump.pages:
        page_data = extract_page_data(page)
        
        # Skip None entries (filtered by namespace/redirect/no_text in extract_page_data)
        if page_data is None:
            continue
        
        # Early Wikidata filtering using global mapping
        # With fork, GLOBAL_TITLE_TO_QID is inherited from parent process
        if GLOBAL_TITLE_TO_QID is not None:
            page_title = page_data['title']
            page_qid = GLOBAL_TITLE_TO_QID.get(page_title, "")
            if not page_qid:
                # Store filtered info for later output
                page_data['_filtered'] = True
                page_data['_filter_reason'] = 'no_wikidata'
                page_data['_filter_info'] = {
                    'id': page_data['id'],
                    'title': page_title,
                    'namespace': page_data['namespace'],
                    'reason': 'no_wikidata'
                }
        
        current_batch.append(page_data)
        if len(current_batch) >= batch_size:
            yield batch_index, current_batch
            batch_index += 1
            if max_batches is not None and batch_index >= max_batches:
                break
            current_batch = []
    if current_batch and (max_batches is None or batch_index < max_batches):
        yield batch_index, current_batch


def process_batch_wrapper(args):
    """Wrapper to assign batch to correct worker temp file.
    
    Uses GLOBAL_TITLE_TO_QID (inherited via fork) - no need to pass it per batch.
    """
    batch_index, batch, temp_files, filtered_temp_files, num_workers = args
    worker_idx = batch_index % num_workers
    valid_count, filtered_count = process_batch((batch, temp_files[worker_idx], filtered_temp_files[worker_idx]))
    return (batch_index, valid_count, filtered_count)


def process_dump_parallel(stream, title_to_qid, num_workers, batch_size=DEFAULT_BATCH_SIZE, max_batches=DEFAULT_MAX_BATCHES):
    """Process dump in parallel with multiple workers.
    
    Uses GLOBAL_TITLE_TO_QID with fork's copy-on-write to avoid pickling
    the large mapping to each worker for every batch.
    """
    global GLOBAL_TITLE_TO_QID
    GLOBAL_TITLE_TO_QID = title_to_qid
    
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
            gen = batch_generator(stream, batch_size=batch_size, max_batches=max_batches)
            args_gen = (
                (batch_idx, batch, temp_files, filtered_temp_files, num_workers)
                for batch_idx, batch in gen
            )

            running_total = 0
            running_filtered_total = 0
            # Use imap_unordered for better load balancing - workers return as soon as ready
            # Results are concatenated by kway_merge_sorted_files, sorted by Makefile
            for batch_idx, valid_count, filtered_count in pool.imap_unordered(process_batch_wrapper, args_gen):
                running_total += valid_count
                running_filtered_total += filtered_count
                print(f"Completed batch {batch_idx}: {running_total} valid, {running_filtered_total} filtered", file=sys.stderr)

        # Merge and output valid results
        kway_merge_sorted_files(temp_files, sys.stdout)
        
        # Write filtered results to hardcoded file
        with open(FILTERED_OUTPUT_FILE, 'w', encoding='utf-8') as filtered_out:
            kway_merge_sorted_files(filtered_temp_files, filtered_out)


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
