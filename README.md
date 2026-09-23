<img src="https://github.com/mjsuhonos/wikicore/blob/main/wikicore_logo_trans.png?raw=true" alt="wikicore" width="200"/>

# Wiki Core

Wiki Core is an open controlled vocabulary built from Wikidata identifiers and English Wikipedia text. It is intended for subject organization, semantic discovery, and automated subject indexing.

Wiki Core separates concept identity from surface syntax by using stable Wikidata QIDs. SKOS provides machine-readable vocabulary data; matching Wikipedia articles provide a linked full-text corpus for indexing and model training. The design is intended to support automation while keeping concept selection, scope, and grouping under human control.

## Why Wiki Core?

The project grew out of work with the Annif subject indexing toolkit. The practical problem was aligning a large English full-text corpus with an open vocabulary without introducing a separate ontology-mapping layer. Wikidata already connects many entities to English Wikipedia articles, so using Wikidata as the vocabulary keeps the vocabulary and training corpus directly linked.

This gives each included entry:

- a stable Wikidata identifier
- an English Wikipedia article for end users and full-text training
- labels and terminology from Wikidata
- links back to other Wikidata entities where article links can be resolved

Wiki Core is deliberately a **controlled vocabulary**, not an ontology. It projects selected parts of the Wikidata graph into manageable subject vocabularies rather than defining a new knowledge model.

## Structure

### Core

Core contains non-instance concepts derived from Wikidata `P279` (subclass of) and `P361` (part of) relationships, excluding entities that are themselves present as `P31` (instance of) subjects.

### Classes

Class vocabularies are convenience groupings defined in `class/*.tsv`. Each group is expanded through `P31` to select its instances.

### Occupations

Occupation vocabularies are convenience groupings defined in `occupation/*.tsv`. Each group is expanded through `P106` to select people (`Q5`) with matching occupations.

Class and occupation groups are not intended to be mutually exclusive. The same QID can appear in multiple vocabularies, which is why the global unique-QID count is lower than the sum of category-specific counts.

## Current release

The most recent English build is `wikicore-20260914-en`.

| Corpus | Documents | Unique QIDs |
|---|---:|---:|
| Core | 104,367 | 104,367 |
| Class | 3,521,671 | 3,420,990 |
| Occupation | 2,502,809 | 1,924,850 |
| **Overall** | **6,128,847** | **5,444,953** |

Additional build statistics:

- **9,739,109** paragraphs
- **3,030,892** documents contain at least one resolved article link
- **5,772,352** resolved article links
- Average text length: **444 characters**; median: **288**

The release contains **61 compressed SKOS vocabularies** (1 core, 41 class, 19 occupation), **183 compressed JSONL corpus files** (61 corpora × train/eval/test), and **3 Annif configuration files**. The committed release files total about **1.54 GB**.

The category corpora overlap by design, so the overall unique-QID count is deduplicated and is not the sum of the category counts.

## Build pipeline

The build is driven by the GNU Makefile.

| Target | Purpose |
|---|---|
| `make data` | Build vocabularies and full-text corpora |
| `make vocab` | Generate SKOS N-Triples vocabularies |
| `make fulltext` | Generate JSONL train/eval/test splits |
| `make annif` | Generate Annif configs, load vocabularies, and train/evaluate projects |
| `make compress` | Gzip generated vocabularies and corpus files with `pigz` |
| `make decompress` | Decompress release files |

The current Makefile uses the following source dumps from `source.nosync/`:

- `wikidata-20260824-all-BETA.nt.gz`
- `enwiki-20260801-pages-articles.xml.bz2`

A typical data build is:

```sh
make data -j 8
```

The main options are `RUN_DATE` (release directory date), `LOCALE` (default `en`), and `BACKEND` (default `mllm` for Annif).

### Vocabulary generation

The Makefile extracts Wikidata sitelinks and the properties needed for vocabulary construction: `P31`, `P106`, `P279`, and `P361`. Labels are taken from the localized SKOS label data.

Core, class, and occupation vocabularies are written as SKOS N-Triples and then compressed for distribution. The generated release layout is:

```text
wikicore-YYYYMMDD-LOCALE/
  vocab/
    core.nt.gz
    class/*.nt.gz
    occupation/*.nt.gz
```

### Full-text generation

`wiki2jsonl.py` converts the English Wikipedia XML dump into JSONL documents keyed by Wikidata QID. It:

- keeps main-namespace, non-redirect articles
- uses the lead section before the first heading
- removes templates, HTML tags, and non-article wikilinks
- resolves article links to Wikidata QIDs when possible
- excludes pages without a Wikidata mapping
- truncates the source page text to 10,000 characters before parsing

The resulting documents contain a document ID, Wikidata subject information, Wikipedia metadata, and cleaned text. The Makefile then creates randomized **80/10/10 train/eval/test splits** for each vocabulary.

The release layout is:

```text
wikicore-YYYYMMDD-LOCALE/
  fulltext/
    core-{train,eval,test}.jsonl.gz
    class/*-{train,eval,test}.jsonl.gz
    occupation/*-{train,eval,test}.jsonl.gz
```

### Annif integration

The `annif` target creates project configurations for the core, class, and occupation vocabularies. Class and occupation projects are also combined into ensembles. The backend is configurable through `BACKEND`.

## Design principles

Wiki Core is intended to augment human expertise rather than replace it. Automation is useful for extraction, normalization, linking, splitting, loading, and evaluation; human work remains central to choosing concepts, defining scope, maintaining groupings, and deciding how the vocabulary should evolve.

The class and occupation groupings are convenience views over Wikidata rather than a prescriptive taxonomy. Their purpose is to provide vocabularies that are practical for downstream indexing systems while retaining Wikidata's identifier space and allowing overlap between groups.

## Community governance

Wiki Core is currently maintained by a single developer and is intended to remain community-shaped. The vocabulary, grouping strategy, identifier policy, and architecture are open to discussion through GitHub Issues, and the current design should be treated as experimental rather than final.

## Related projects and standards

The project was initially motivated by Annif and by the availability of Wikidata/Wikipedia training data such as Wikidata5M. The vocabulary is serialized using SKOS. Related approaches in knowledge organization include FAST, YSO, and GND.

## Repository references

The main implementation files are:

- `Makefile` — data extraction, vocabulary generation, full-text generation, splitting, compression, and Annif workflow
- `wiki2jsonl.py` — Wikipedia-to-JSONL conversion and link/QID extraction
- `class/` — class grouping definitions
- `occupation/` — occupation grouping definitions
- `wikicore-20260914-en/` — latest generated English release
