<img src="https://github.com/mjsuhonos/wikicore/blob/main/wikicore_logo_trans.png?raw=true" alt="wikicore" width="200"/>

# Wiki Core

Wiki Core is a modern, open approach to subject organization. By anchoring topics in stable identifiers from Wikidata instead of pre-coordinated strings, it separates meaning from syntax, supports multilingual labels, and enables flexible, faceted discovery.

For developers, Wiki Core provides an ID-based, machine-readable vocabulary designed for modern applications. Its faceted, graph-oriented structure and multilingual labels support semantic search, API integration, and flexible data linking. Unlike legacy library vocabularies, it is web-native, interoperable, and ready for automated indexing workflows, while still preserving human oversight.

Wiki Core does not replace cataloguers — it repositions their expertise. Rather than encoding complex subject strings, cataloguers focus on curating concepts, defining boundaries, and shaping relationships that guide discovery. This approach makes their judgment more visible and impactful, while allowing systems to handle repetitive or automated tasks.

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

Wiki Core is intentionally designed as a community project from the ground up — not a product of any single institution, and not beholden to any vendor or standards body. That independence is a feature, not a limitation.  This project emerged from over a decade working on linked data infrastructure in academic libraries, and a growing conviction that the field needs an alternative that isn't owned by any single institution.

The project is currently in early community formation. The core vocabulary and architecture reflect a year of experimentation and research, but the goal is explicitly not to present a finished system for adoption — it's to find collaborators who will stress-test the ideas, identify gaps, and help shape what Wiki Core becomes.

### What we're looking for:

Developers building discovery systems, cataloguing tools, or semantic pipelines who want an alternative to LCSH that is web-native, Wikidata-anchored, and machine-friendly. Ontologists and information scientists who see problems with existing controlled vocabularies and want to work on something better. Critics who think the approach is wrong in interesting ways.

Wiki Core is currently maintained by a single developer, but the explicit intention is to distribute governance as the community grows. Significant changes to vocabulary structure, identifier policies, or core philosophy will be discussed openly in GitHub Issues before implementation. Nothing about the architecture is considered settled. If you're considering contributing, you have as much right to shape the direction as anyone. Contributions, critique, and questions are welcome via GitHub Issues or by reaching out directly.

---

## Coverage

Wiki Core is derived from Wikidata and filtered to items with English-language sitelinks (~10.1M of 116.6M total entities). Subject coverage is organized into two main tracks: **named classes** (things) and **humans** (people by occupation).

### Subject filtering pipeline

| Stage | Count |
|-------|------:|
| Total Wikidata entities | 116,659,543 |
| Has English sitelink | 10,150,254 |
| In scope (has P31 / concepts) | 9,718,047 |
| Named classes | 3,399,735 |
| Humans Q5 | 2,106,826 |
| Core concepts | ~710,000 |

![Coverage Sankey Diagram](https://github.com/mjsuhonos/wikicore/blob/main/wikicore-sankey.png?raw=true)

A complete build (`make all`) generates 795 files:
- **1 core vocabulary file** (29,508 core concepts in older builds, ~710K with leaf nodes included)
- **778 individual subject files** (one per class QID)
- **43 class group files** (3,906,431 memberships with overlap)
- **19 occupation group files** (2,632,939 Q5 memberships with overlap)

**Important Note:** One subject may appear in multiple occupation/class groups due to overlapping categorizations.

#### Subject Distribution

Occupation SKOS files contain statements about Q5 (human) entities, not about occupation concepts themselves. For example, `wikicore-DATE-occ-engineering-en.nt` contains SKOS about individual engineers (Ada Lovelace, etc.), not about the occupation concept "engineer" (Q81096).  Class SKOS files contain statements about class concepts and their instances. One item may appear in multiple groups.

725,879 subjects have P31 types that are not yet assigned to any named group (109,371 distinct class QIDs in `P31_missing_classes.tsv`). These represent uncategorized entities that could potentially be organized into new subject groups in future builds.

---

## Build Pipeline

Wiki Core is built from Wikidata dumps using a GNU Make pipeline. The pipeline extracts SKOS concept vocabularies in N-Triples format and fulltext TSVs, organized by subject class or occupation group.

### Prerequisites

- GNU Make, `parallel`, `pigz`, `ripgrep` (`rg`)
- `rapper` (Raptor RDF utilities, for `make turtle`)
- Python 3
- Wikidata property-direct and SKOS labels dumps in `source.nosync/`

### Pipeline stages

The build proceeds through the following stages:

1. **Extract core properties** — filters P31, P279, P361 triples from the Wikidata property-direct dump
2. **Split & partition** — chunks the core properties and partitions them by class into per-subject TSVs
3. **Prepare subject vocabularies** — sorts, deduplicates, and filters each per-subject TSV against the sitelinks list
4. **Extract P106 & group Q5 humans** — extracts P106 (occupation) triples, identifies Q5 (human) entities, and groups them by occupation
5. **Extract core concepts** — identifies entities with P279/P361 relationships and sitelinks using file operations
6. **Extract localized labels** — decompresses and splits the SKOS labels dump by locale
7. **Generate SKOS vocabs** — assembles concept declarations, concept scheme membership, labels, and `skos:broader` relations into `.nt` files
8. **Convert to Turtle** — re-serializes `.nt` files to compressed Turtle using `rapper`

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
| `core` | Build the core SKOS vocab (`wikicore-DATE-core-LOCALE.nt`) |
| `skos_class_qids` | Build one `.nt` per class QID (777 files) |
| `skos_class_groups` | Build one combined `.nt` per class group (42 files) |
| `skos_occ_qids` | Build one `.nt` per occupation QID (1,429 files, SKOS about Q5 humans) |
| `skos_occ_groups` | Build one combined `.nt` per occupation group (19 files, SKOS about Q5 humans) |
| `skos_occ_unmatched` | Build SKOS for Q5 humans with no matched occupation |
| `skos_class_qid QIDS='Q5 Q532'` | Build SKOS for specific class QIDs |
| `skos_class_group CLASS_FILE=classes/aircraft.tsv` | Build combined `.nt` for a single class group |
| `skos_occ_qid QID=Q7888586` | Build SKOS for Q5 humans with a specific occupation QID |
| `skos_occ_group OCC_FILE=occupations/engineering.tsv` | Build combined `.nt` for a single occupation group |
| `turtle` | Convert all `.nt` files to compressed Turtle (`.ttl.gz`) |

**Fulltext targets:**

| Target | Description |
|--------|-------------|
| `fulltext_class_qids` | Build one fulltext TSV per class QID (777 files) |
| `fulltext_class_groups` | Build one combined fulltext TSV per class group (42 files) |
| `fulltext_occ_groups` | Build one combined fulltext TSV per occupation group (19 files, people) |
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

**Build time:**

On a 60-CPU VPS, `make all -j` takes about 45 minutes and 18GB of memory, with an average load around 1400.

```sh
real    45m42.715s
user    2391m20.374s
sys     166m41.555s
```

---

## Output

### SKOS vocabularies (`make skos`)

Output is written to a dated release directory (`wikicore-YYYYMMDD/`):

| Target | Files | Location | Description |
|--------|------:|----------|-------------|
| `core` | 1 | `wikicore-DATE/` | Core taxonomy |
| `skos_class_qids` | 777 | `wikicore-DATE/classes/` | One `.nt` per class QID |
| `skos_class_groups` | 42 | `wikicore-DATE/classes/groups/` | One `.nt` per class group |
| `skos_occ_qids` | 1,429 | `wikicore-DATE/occupations/` | One `.nt` per occupation QID (SKOS about Q5 humans) |
| `skos_occ_groups` | 19 | `wikicore-DATE/occupations/groups/` | One `.nt` per occupation group (SKOS about Q5 humans) |
| **TOTAL** | **2,268** | | ~11 GB disk space |

Each file is named `wikicore-YYYYMMDD-<class|QID|group-name>-<locale>.nt` (or `.ttl.gz` after `make turtle`). SKOS triples per concept: `rdf:type skos:Concept`, `skos:inScheme`, `skos:prefLabel`/`skos:altLabel`, and `skos:broader`. Occupation files generate SKOS about **Q5 (human) entities** grouped by occupation, not about the occupation concepts themselves.

### Fulltext TSVs (`make fulltext`)

Fulltext output is written to `wikicore-DATE/fulltext/`, mirroring the SKOS layout. Each line: `text<TAB><http://www.wikidata.org/entity/QID>`.

| Target | Files | Location |
|--------|------:|----------|
| `fulltext_class_qids` | 777 | `wikicore-DATE/fulltext/classes/qids/` |
| `fulltext_class_groups` | 42 | `wikicore-DATE/fulltext/classes/` |
| `fulltext_occ_groups` | 20 (19 + unmatched) | `wikicore-DATE/fulltext/occupations/` |
| **TOTAL** | **839** | ~5 GB disk space |

---

## License

Wiki Core is licensed under **GPLv3**. See [LICENSE](https://github.com/mjsuhonos/wikicore?tab=GPL-3.0-1-ov-file) for details.

## References

* [Wikidata](https://www.wikidata.org/)
* [Library of Congress Subject Headings](https://www.loc.gov/aba/cataloging/subject/)
* [FAST: Faceted Application of Subject Terminology](https://www.oclc.org/en/fast.html)
* [YSO Ontology](https://finto.fi/yso/en/)
* [GND: Gemeinsame Normdatei](https://www.dnb.de/EN/Standardisierung/GND/gnd_node.html)

---

<p align="center">
  Made with love in Canada
  <img src="https://flagcdn.com/w20/ca.png" alt="Canada" width="20" height="10" style="vertical-align:middle; margin-right:6px;">
</p>
