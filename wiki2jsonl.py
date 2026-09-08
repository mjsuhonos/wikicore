#!/usr/bin/env python3

import json
import re
import sys
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

        # Non-article wikilinks are still rendered using their visible
        # text, but aren't added to wikipedia_links.
        if node.text is not None:
            return render_wikicode(node.text)

        return render_wikicode(node.title)

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
    text = text.replace("''", "")

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


def page_to_jsonl(page, wikipedia_to_wikidata):
    """Convert one mwxml Page into a JSON Lines object."""

    # Redirects aren't article documents.
    if page.redirect:
        return None

    revision = latest_revision(page)

    if revision is None or revision.text is None:
        return None

    code = mwparserfromhell.parse(revision.text)

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
        metadata_links[str(number)] = ",".join(qids)

    text = "\n\n".join(rendered_paragraphs)
    
    # Look up Wikidata URI for this page
    wiki_uri = wikipedia_url(page.title)
    wikidata_uri = wikipedia_to_wikidata.get(wiki_uri, "")
    
    # Extract label from page title (replace underscores with spaces)
    if wikidata_uri:
        label = page.title.replace("_", " ")
        # Convert to https and use full URI for subjects
        #wikidata_uri = wikidata_uri.replace("http://", "https://")
        subjects = [{"uri": wikidata_uri, "label": label}]
        document_id = wikidata_uri.split('/')[-1]  # Extract QID for document_id
    else:
        subjects = []
        document_id = str(page.id)

    return {
        "document_id": document_id,
        "text": text,
        "subjects": subjects,
        "metadata": {
            "uri": wiki_uri,
            **metadata_links,
        },
    }


def process_dump(stream, wikipedia_to_wikidata):
    """Stream pages from a MediaWiki XML dump and output as JSON Lines."""
    dump = mwxml.Dump.from_file(stream)

    for page in dump:
        # Namespace 0 = normal articles.
        if page.namespace != 0:
            continue

        row = page_to_jsonl(page, wikipedia_to_wikidata)

        if row is not None:
            try:
                print(json.dumps(row, ensure_ascii=False))
            except BrokenPipeError:
                # Pipe was closed (e.g., by head), exit gracefully
                sys.exit(0)


def main():
    # Determine sitelinks file path
    sitelinks_path = None
    wikipedia_dump_path = None
    
    # Check if we have arguments
    if len(sys.argv) > 1:
        # If first arg is '-', it means read dump from stdin, second arg is sitelinks
        if sys.argv[1] == '-':
            if len(sys.argv) > 2:
                sitelinks_path = sys.argv[2]
            else:
                # '-' with no sitelinks arg - read dump from stdin, try default sitelinks
                pass
        else:
            # First arg could be either dump file or sitelinks file
            # Check if stdin has data (from pipe) - if so, first arg is sitelinks
            if sys.stdin.isatty():
                # stdin is a terminal, so first arg is dump file
                wikipedia_dump_path = sys.argv[1]
                if len(sys.argv) > 2:
                    sitelinks_path = sys.argv[2]
            else:
                # stdin has data from pipe, so first arg is sitelinks file
                sitelinks_path = sys.argv[1]
                if len(sys.argv) > 2:
                    wikipedia_dump_path = sys.argv[2]
    
    # Load sitelinks if path is provided
    if sitelinks_path:
        wikipedia_to_wikidata = load_sitelinks(sitelinks_path)
    else:
        # Try default path
        try:
            wikipedia_to_wikidata = load_sitelinks("working.nosync/enwiki_sitelinks.tsv")
        except FileNotFoundError:
            wikipedia_to_wikidata = {}
    
    # Process dump
    if wikipedia_dump_path:
        with open(wikipedia_dump_path, "rb") as f:
            process_dump(f, wikipedia_to_wikidata)
    else:
        process_dump(sys.stdin.buffer, wikipedia_to_wikidata)


if __name__ == "__main__":
    main()
