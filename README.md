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

## Governance and Community

Wiki Core is intentionally designed as a community project from the ground up — not a product of any single institution, and not beholden to any vendor or standards body. That independence is a feature, not a limitation.  This project emerged from over a decade working on linked data infrastructure in academic libraries, and a growing conviction that the field needs an alternative that isn't owned by any single institution.

The project is currently in early community formation. The core vocabulary and architecture reflect a year of experimentation and research, but the goal is explicitly not to present a finished system for adoption — it's to find collaborators who will stress-test the ideas, identify gaps, and help shape what Wiki Core becomes.

### What we're looking for:

Developers building discovery systems, cataloguing tools, or semantic pipelines who want an alternative to LCSH that is web-native, Wikidata-anchored, and machine-friendly. Ontologists and information scientists who see problems with existing controlled vocabularies and want to work on something better. Critics who think the approach is wrong in interesting ways.

### How decisions get made (for now):

Wiki Core is currently maintained by a single developer, but the explicit intention is to distribute governance as the community grows. Significant changes to vocabulary structure, identifier policies, or core philosophy will be discussed openly in GitHub Issues before implementation. Nothing about the architecture is considered settled.

### What we explicitly don't want:

For Wiki Core to become another project where one institution's priorities quietly dominate. If you're considering contributing, you have as much right to shape the direction as anyone.
Contributions, critique, and questions are welcome via GitHub Issues or by reaching out directly.

---

## Coverage

Wiki Core is derived from Wikidata and filtered to items with English-language sitelinks (~10.1M of 116.6M total entities). Subject coverage is organized into two main tracks: **named classes** (things) and **humans** (people by occupation).

### Subject filtering pipeline

| Stage | Count |
|-------|------:|
| Total Wikidata entities | 116,659,543 |
| Has English sitelink | 10,150,254 |
| In scope (has P31 / concepts) | 9,718,047 |
| Named classes (unique entities) | 3,399,735 |
| Named classes (across 42 groups, with overlap) | 3,906,431 |
| Humans Q5 (unique entities) | 2,106,826 |
| Humans Q5 (across 19 occupation groups, with overlap) | 2,632,939 |
| Core concepts | 29,508 |

![Coverage Sankey Diagram](https://github.com/mjsuhonos/wikicore/blob/main/wikicore-sankey.png?raw=true)

**Note:** Entities can appear in multiple groups. "Unique entities" counts each QID once; "across groups" counts include the same entity multiple times if it appears in multiple groups.

---

## Build Pipeline

Wiki Core is built from Wikidata dumps using a GNU Make pipeline. The pipeline extracts SKOS concept vocabularies in N-Triples format and fulltext TSVs, organized by subject class or occupation group.

### Prerequisites

- GNU Make, `parallel`, `pigz`, `gsplit`, `ripgrep` (`rg`)
- [Apache Jena](https://jena.apache.org/) (`tdb2.tdbloader`, `tdb2.tdbupdate`, `tdb2.tdbquery`, `riot`)
- Python 3
- Wikidata property-direct and SKOS labels dumps in `source.nosync/`

### Pipeline stages

The build proceeds through the following stages:

1. **Extract core properties** — filters P31, P279, P361 triples from the Wikidata property-direct dump
2. **Split & partition** — chunks the core properties and partitions them by class into per-subject TSVs
3. **Prepare subject vocabularies** — sorts, deduplicates, and filters each per-subject TSV against the sitelinks list
4. **Extract P106 & group Q5 humans** — extracts P106 (occupation) triples, identifies Q5 (human) entities, and groups them by occupation
5. **Load backbone into Jena TDB2** — loads the concept backbone graph
6. **Materialize & export core concepts** — runs SPARQL to materialize ancestor paths and child counts, then exports core QIDs
7. **Extract localized labels** — decompresses and splits the SKOS labels dump by locale
8. **Generate SKOS vocabs** — assembles concept declarations, concept scheme membership, labels, and `skos:broader` relations into `.nt` files
9. **Convert to Turtle** — re-serializes `.nt` files to prefixed, compressed Turtle using Jena RIOT

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
| `skos_occ_qids` | Build one `.nt` per occupation QID (1,449 files, SKOS about Q5 humans) |
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

On a 48-CPU VPS, `make skos -j` takes about 20 minutes and 48GB of memory, with an average load around 750.

```sh
real    20m15.173s
user    612m17.784s
sys     64m10.606s
```

---

## Output

### SKOS vocabularies (`make skos`)

Output is written to a dated release directory (`wikicore-YYYYMMDD/`):

| Target | Files | Location | Description |
|--------|------:|----------|-------------|
| `core` | 1 | `wikicore-DATE/` | Core taxonomy (29,508 concepts) |
| `skos_class_qids` | 777 | `wikicore-DATE/classes/` | One `.nt` per class QID |
| `skos_class_groups` | 42 | `wikicore-DATE/classes/groups/` | One `.nt` per class group |
| `skos_occ_qids` | 1,449 | `wikicore-DATE/occupations/` | One `.nt` per occupation QID (SKOS about Q5 humans) |
| `skos_occ_groups` | 19 | `wikicore-DATE/occupations/groups/` | One `.nt` per occupation group (SKOS about Q5 humans) |
| `skos_occ_unmatched` | 1 | `wikicore-DATE/occupations/groups/` | SKOS for Q5 humans with no matched occupation |
| **TOTAL** | **2,289** | | ~5-7 GB disk space |

Each file is named `wikicore-YYYYMMDD-<class|QID|group-name>-<locale>.nt` (or `.ttl.gz` after `make turtle`). SKOS triples per concept: `rdf:type skos:Concept`, `skos:inScheme`, `skos:prefLabel`/`skos:altLabel`, and `skos:broader`. Occupation files generate SKOS about **Q5 (human) entities** grouped by occupation, not about the occupation concepts themselves.

### Fulltext TSVs (`make fulltext`)

Fulltext output is written to `fulltext/`, mirroring the SKOS layout. Each line: `text<TAB><http://www.wikidata.org/entity/QID>`.

| Target | Files | Location |
|--------|------:|----------|
| `fulltext_class_qids` | 777 | `fulltext/classes/qids/` |
| `fulltext_class_groups` | 42 | `fulltext/classes/` |
| `fulltext_occ_groups` | 19 (+1 unmatched) | `fulltext/occupations/` |
| **TOTAL** | **839** | |

### Verification

```bash
# SKOS output
find wikicore-DATE/ -name '*.nt' | wc -l          # Expected: 2,289
ls wikicore-DATE/classes/*.nt | wc -l              # Expected: 777
ls wikicore-DATE/classes/groups/*.nt | wc -l       # Expected: 42
ls wikicore-DATE/occupations/*.nt | wc -l          # Expected: 1,449
ls wikicore-DATE/occupations/groups/*.nt | wc -l   # Expected: 20 (19 + unmatched)

# Fulltext output
find fulltext/ -name '*.tsv' | wc -l              # Expected: 839
ls fulltext/classes/qids/*.tsv | wc -l            # Expected: 777
ls fulltext/classes/*.tsv | wc -l                 # Expected: 42
ls fulltext/occupations/*.tsv | wc -l             # Expected: 20 (19 + unmatched)
```

---

## License

Wiki Core is licensed under **GPLv3**. See [LICENSE](https://github.com/mjsuhonos/wikicore?tab=GPL-3.0-1-ov-file) for details.

## References

* [Wikidata](https://www.wikidata.org/)
* [Library of Congress Subject Headings](https://www.loc.gov/aba/cataloging/subject/)
* [FAST: Faceted Application of Subject Terminology](https://www.oclc.org/en/fast.html)
* [YSO Ontology](https://finto.fi/yso/en/)
* [GND: Gemeinsame Normdatei](https://www.dnb.de/EN/Standardisierung/GND/gnd_node.html)
* [Apache Jena](https://jena.apache.org/)

---

<p align="center">
  Made with love in Canada
  <img src="https://flagcdn.com/w20/ca.png" alt="Canada" width="20" height="10" style="vertical-align:middle; margin-right:6px;">
</p>
