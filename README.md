<img src="https://github.com/mjsuhonos/wikicore/blob/main/wikicore_logo_trans.png?raw=true" alt="wikicore" width="200"/>

# Wiki Core

Wiki Core is a modern, open approach to subject organization. By anchoring topics in stable identifiers from Wikidata instead of pre-coordinated strings, it separates meaning from syntax, supports multilingual labels, and enables flexible, faceted discovery.

For developers, Wiki Core provides an ID-based, machine-readable vocabulary designed for modern applications. Its faceted, graph-oriented structure and multilingual labels support semantic search, API integration, and flexible data linking. Unlike legacy library vocabularies, it is web-native, interoperable, and ready for automated indexing workflows, while still preserving human oversight.

Wiki Core is designed to augment human expertise, not displace it. The goal is to shift effort from mechanical encoding toward higher-order judgment — curating concepts, defining scope, and shaping the relationships that make discovery meaningful. Systems handle the repetitive work; people shape what it means.

## Features

- **Openly licensed** (GPLv3), community-driven, and designed to evolve transparently
- **Machine-friendly**: intended for integration with automated indexing tools, catalogs, and semantic pipelines
- Anchors topics in **Wikidata identifiers** to ensure global interoperability and stable semantics
- Components can be **combined, extended, or adapted** to different domains and applications
- Supports metadata, indexing, and subject classification workflows
- Native multilingual labels and terminology

Wiki Core aligns philosophically with **modern, flexible subject systems**, including:

* **YSO** (Finnish General Upper Ontology for Knowledge Organization) — a multilingual ontology used for Finnish cultural and scientific metadata
* **GND** (Gemeinsame Normdatei) — a German authority file for persons, organizations, subjects, and works, widely used in Europe
* **FAST** — a simplified faceted version of LCSH for online catalogs and digital libraries

---

## Community Governance

Wiki Core is intentionally designed as a community project from the ground up — not a product of any single institution, and not beholden to any vendor or standards body. That independence is a feature, not a limitation. This project emerged from over a decade working on linked data infrastructure in academic libraries, and a growing conviction that the field needs a genuinely open alternative.

The project is currently in early community formation. The core vocabulary and architecture reflect a year of experimentation and research, but the goal is explicitly not to present a finished system for adoption — it's to find collaborators who will stress-test the ideas, identify gaps, and help shape what Wiki Core becomes.

### What we're looking for:

Developers building discovery systems, cataloguing tools, or semantic pipelines who want an alternative to LCSH that is web-native. Ontologists and information scientists who see problems with existing controlled vocabularies and want to work on something better. Critics who think the approach is wrong in interesting ways.

Wiki Core is currently maintained by a single developer, but the explicit intention is to distribute governance as the community grows. Significant changes to vocabulary structure, identifier policies, or core philosophy will be discussed openly in GitHub Issues before implementation. Nothing about the architecture is considered settled. If you're considering contributing, you have as much right to shape the direction as anyone. Contributions, critique, and questions are welcome via GitHub Issues or by reaching out directly.

---

## Coverage

Subject coverage is drawn from Wikidata items with English-language sitelinks, organized into two main tracks: **named classes** (things) and **humans** (people by occupation).

![Coverage Sankey Diagram](https://github.com/mjsuhonos/wikicore/blob/main/wikicore-sankey.png?raw=true)

### QID Coverage

Unique Wikidata QID counts from the `wikicore-20260226-en` build. Individual and group files share the same QID pool within each domain; the global unique total reflects deduplication across all files.

| Component | Files | Unique QIDs | Notes |
|-----------|------:|------------:|-------|
| Core | 1 | 144,978 | Pure concepts (no P31 instances) |
| Classes / per-QID files | 820 | 9,101,430 | P31 instances of each class QID |
| Classes / group files | 86 | 9,101,430 | Same QID pool, grouped by subject area |
| Occupations / per-QID files | 1,448 | 1,943,216 | Q5 humans matched to a known occupation |
| Occupations / group files | 38 | 1,943,216 | Same QID pool, grouped by occupation area |
| Occupations / unmatched file | 1 | 172,868 | Q5 humans with no matching occupation |
| **Global unique** | **2,393** | **9,231,924** | Deduplicated |

### Subject Distribution

Occupation SKOS files contain statements about Q5 (human) entities, not about occupation concepts themselves. For example, `wikicore-DATE-occ-engineering-en.nt` contains SKOS about individual engineers (Ada Lovelace, etc.), not about the occupation concept "engineer" (Q81096). Class SKOS files contain statements about class concepts and their instances. Items may appear in multiple groups.

895,485 subjects have P31 types that are not yet assigned to any named group. These represent uncategorized entities that could potentially be organized into new subject groups in future builds.

---

## Background and Rationale

The need for an open controlled vocabulary originally came from work with the [Annif](https://github.com/NatLibFi/Annif/) subject indexing toolkit.  While linked-data based ontologies with English labels exist, none offered an easy way to align a full-text corpus for ML training.  However, the [Wikidata5m](https://deepgraphlearning.github.io/project/wikidata5m) dataset  contains 1:1 Wikidata:Wikipedia mappings for a subset of 4.6M Wikipedia entries.  Any attempt to use Wikidata5m (or a larger Wikipedia variant) as a training corpus would require mapping to external onotologies through Wikidata properties, accepting both data and semantic loss.  Better to simply use Wikidata as the vocabulary itself -- and by only using the subset with Wikipedia sitelinks, Wiki Core can then make two guarantees:

1. All entries in Wiki Core can link directly to an English Wikipedia article (for end users)
2. All entries in Wiki Core therefore have an English training document (and potentially more through use of in-text Wikipedia links)

### Why another ontology?

Wiki Core is very intentionally and explicitly **not an ontology** -- it is a *controlled vocabulary*; ie. a one-dimensinoal projection onto the Wikidata knowledge graph.  This eliminates a number of biases (mostly structural), and only makes use of the graph structure to identify "pure concepts" (ie. entries without instances) for the core vocabulary.

The 'classes' and 'occupations' in Wiki Core are not prescriptive, they are just convenience groups for generating vocabularies that are a manageable size for downstream tools.  They are **not disjoint**; ie. entries can appear in multiple classes -- this is again, a reflection of the Wikidata knowledge graph and by design.  Classes and occupations have been generated by embedded clustering, but a more deterministic approach for future releases is desirable.

---

## Build Pipeline

Wiki Core is built using a GNU Make pipeline. The pipeline extracts SKOS concept vocabularies in N-Triples format and fulltext TSVs, organized by subject class or occupation group.

A complete build (`make all`) generates SKOS files and fulltext TSVs organized by class and occupation group; see [Output](#output) for file and coverage counts.

The build proceeds through the following stages:

1. **Extract core properties** — filters P31, P279, P361 triples from the Wikidata property-direct dump
2. **Split & partition** — chunks the core properties and partitions them by class into per-subject TSVs
3. **Prepare subject vocabularies** — sorts, deduplicates, and filters each per-subject TSV against the sitelinks list
4. **Extract P106 & group Q5 humans** — extracts P106 (occupation) triples, identifies Q5 (human) entities, and groups them by occupation
5. **Extract core concepts** — identifies entities with P279/P361 relationships and sitelinks using file operations
6. **Extract localized labels** — decompresses and splits the SKOS labels dump by locale
7. **Generate SKOS vocabs** — assembles concept declarations, concept scheme membership, labels, and `skos:broader` relations into `.nt` files
8. **Convert to Turtle** — re-serializes `.nt` files to compressed Turtle using `rapper`

### Prerequisites

- GNU Make, `parallel`, `pigz`, `ripgrep` (`rg`)
- `rapper` (Raptor RDF utilities, for `make turtle`)
- Python 3
- Wikidata property-direct and SKOS labels dumps in `source.nosync/`

### Usage

```
make <target> [OPTIONS]
```

**Aggregate targets:**

| Target | Description |
|--------|-------------|
| `all` | Build everything: `skos` + `fulltext` |
| `skos` | Build all SKOS `.nt` files (core + class/occ qids and groups) |
| `fulltext` | Build all fulltext TSVs (requires `source.nosync/wikidata5m_text.txt.gz`) |

**SKOS targets:**

| Target | Description |
|--------|-------------|
| `skos_core` | Build the core SKOS vocab (`wikicore-DATE-core-LOCALE.nt`) |
| `skos_class_qids` | Build one `.nt` per class QID |
| `skos_class_groups` | Build one combined `.nt` per class group |
| `skos_occ_qids` | Build one `.nt` per occupation QID |
| `skos_occ_groups` | Build one combined `.nt` per occupation group |
| `skos_occ_unmatched` | Build SKOS for Q5 humans with no matched occupation |
| `skos_class_qid QIDS='Q5 Q532'` | Build SKOS for specific class QIDs |
| `skos_class_group CLASS_FILE=classes/aircraft.tsv` | Build combined `.nt` for a single class group |
| `skos_occ_qid QID=Q7888586` | Build SKOS for Q5 humans with a specific occupation QID |
| `skos_occ_group OCC_FILE=occupations/engineering.tsv` | Build combined `.nt` for a single occupation group |
| `turtle` | Convert all `.nt` files to compressed Turtle (`.ttl.gz`) |

**Fulltext targets:**

| Target | Description |
|--------|-------------|
| `fulltext_core` | Build fulltext TSV for core vocabulary concepts |
| `fulltext_class_qids` | Build one fulltext TSV per class QID |
| `fulltext_class_groups` | Build one combined fulltext TSV per class group |
| `fulltext_occ_groups` | Build one combined fulltext TSV per occupation group (Q5 humans) |
| `fulltext_occ_unmatched` | Build fulltext TSV for Q5 humans with no matched occupation |
| `fulltext_class_qid QIDS='Q5 Q532'` | Build fulltext TSVs for specific class QIDs |
| `fulltext_class_group CLASS_FILE=classes/aircraft.tsv` | Build combined fulltext TSV for a single class group |
| `fulltext_occ_group OCC_FILE=occupations/engineering.tsv` | Build combined fulltext TSV for a single occupation group |

**Utility targets:**

| Target | Description |
|--------|-------------|
| `clean` | Remove working files |
| `distclean` | Remove working files and all generated `.nt`/`.ttl.gz`/fulltext TSVs |

**Options:**

| Option | Default | Description |
|--------|---------|-------------|
| `LOCALE` | `en` | Output language |
| `JOBS` | `nproc` | Parallel jobs |

---

## Output

`make skos` output is written to a dated, locale-specific release directory (`wikicore-YYYYMMDD-LOCALE/`), ~11 GB total:

| Target | Location | Description |
|--------|----------|-------------|
| `skos_core` | `wikicore-DATE-LOCALE/` | Core taxonomy |
| `skos_class_qids` | `wikicore-DATE-LOCALE/classes/` | One `.nt` per class QID |
| `skos_class_groups` | `wikicore-DATE-LOCALE/classes/groups/` | One `.nt` per class group |
| `skos_occ_qids` | `wikicore-DATE-LOCALE/occupations/` | One `.nt` per occupation QID |
| `skos_occ_groups` | `wikicore-DATE-LOCALE/occupations/groups/` | One `.nt` per occupation group |

Each file is named `wikicore-YYYYMMDD-<class|QID|group-name>-<locale>.nt` (or `.ttl.gz` after `make turtle`). SKOS triples per concept: `rdf:type skos:Concept`, `skos:inScheme`, `skos:prefLabel`/`skos:altLabel`, and `skos:broader`.

`make fulltext` output is written to `wikicore-DATE-LOCALE/fulltext/`, mirroring the SKOS layout, ~5 GB total. Each line: `text<TAB><http://www.wikidata.org/entity/QID>`.

| Target | Location |
|--------|----------|
| `fulltext_core` | `wikicore-DATE-LOCALE/fulltext/` |
| `fulltext_class_qids` | `wikicore-DATE-LOCALE/fulltext/classes/qids/` |
| `fulltext_class_groups` | `wikicore-DATE-LOCALE/fulltext/classes/` |
| `fulltext_occ_groups` | `wikicore-DATE-LOCALE/fulltext/occupations/` |

---

## License

Wiki Core is licensed under **GPLv3**. See [LICENSE](https://github.com/mjsuhonos/wikicore?tab=GPL-3.0-1-ov-file) for details.

## References

* [Annif: Tool for automated subject indexing and classification](https://github.com/NatLibFi/Annif/)
* [Wikidata5m: million-scale knowledge graph dataset](https://deepgraphlearning.github.io/project/wikidata5m)
* [SKOS: Simple Knowledge Organization System](https://www.w3.org/TR/skos-reference/)
* [LCSH: Library of Congress Subject Headings](https://www.loc.gov/aba/cataloging/subject/)
* [FAST: Faceted Application of Subject Terminology](https://www.oclc.org/en/fast.html)
* [YSO: Finnish General Upper Ontology](https://finto.fi/yso/en/)
* [GND: Gemeinsame Normdatei](https://www.dnb.de/EN/Standardisierung/GND/gnd_node.html)

---

<p align="center">
  Made with love in Canada
  <img src="https://flagcdn.com/w20/ca.png" alt="Canada" width="20" height="10" style="vertical-align:middle; margin-right:6px;">
</p>
