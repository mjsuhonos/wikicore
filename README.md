<img src="https://github.com/mjsuhonos/wikicore/blob/main/wikicore_logo_trans.png?raw=true" alt="wikicore" width="200"/>

# Wiki Core

Wiki Core is a modern, open approach to subject organization. By anchoring topics in stable identifiers from Wikidata instead of pre-coordinated strings, it separates meaning from syntax, supports multilingual labels, and enables flexible, faceted discovery.

For developers, Wiki Core provides an ID-based, machine-readable vocabulary designed for modern applications. Its faceted, graph-oriented structure and multilingual labels support semantic search, API integration, and flexible data linking. Unlike legacy library vocabularies, it is web-native, interoperable, and ready for automated indexing workflows, while still preserving human oversight.

**Wiki Core does not replace cataloguers** — it repositions their expertise. Rather than encoding complex subject strings, cataloguers focus on curating concepts, defining boundaries, and shaping relationships that guide discovery. This approach makes their judgment more visible and impactful, while allowing systems to handle repetitive or automated tasks.

## Features

- **Openly licensed** (GPLv3), community-driven, and designed to evolve transparently
- **Machine-friendly**: intended for integration with automated indexing tools, catalogs, and semantic pipelines
- Anchors topics in **Wikidata identifiers** to ensure global interoperability and stable semantics
- Outputs standard **SKOS** (Simple Knowledge Organization System) for broad compatibility
- Components can be **combined, extended, or adapted** to different domains and applications
- Supports metadata, indexing, and subject classification workflows
- **Native multilingual labels** via Wikidata's built-in language support
- **Reproducible builds** from Wikidata dumps using a fully automated `make` pipeline

## How It Works

Wiki Core is built from Wikidata through a 10-step pipeline that extracts class hierarchies (P279 subclass-of, P361 part-of) and instance relationships (P31 instance-of), materializes transitive closures in Apache Jena, and outputs a SKOS vocabulary of concepts, labels, and broader/narrower relationships.

```
Wikidata dumps ──► Extract P31/P279/P361 ──► Build class backbone
                                                     │
           Sitelinks ──────────────────┐             ▼
                                       ├──► Partition instances
           Discover top-level buckets ─┘         │
                                                 ▼
                    Labels ──► Filter ──► Generate SKOS ──► Final vocabulary
```

The output is a single N-Triples file (`wikicore-YYYYMMDD-LOCALE.nt`) containing:
- **Concept declarations** (`skos:Concept`)
- **Preferred labels** (`skos:prefLabel`) in the target language
- **Broader relationships** (`skos:broader`) derived from the Wikidata class hierarchy
- **Concept scheme membership** (`skos:inScheme`)

Subject-specific vocabularies (e.g. humans, geographic features) can also be generated as separate files.

## Getting Started

### Prerequisites

- [Apache Jena](https://jena.apache.org/) (TDB2 tools)
- GNU coreutils (`gsplit`), [pigz](https://zlib.net/pigz/), [ripgrep](https://github.com/BurntSushi/ripgrep), [GNU Parallel](https://www.gnu.org/software/parallel/)
- Python 3
- ~800GB disk space, 32GB+ RAM

### Input Data

Download and place in `source.nosync/`:

| File | Description | Size |
|------|-------------|------|
| `wikidata-YYYYMMDD-propdirect.nt.gz` | Wikidata property direct dump | ~100GB |
| `wikidata-YYYYMMDD-skos-labels-en.nt.gz` | SKOS labels for target locale | ~50GB |
| `sitelinks_en_qids.tsv` | QIDs with Wikipedia articles | ~1GB |

### Build

```bash
# Validate your setup
bash setup_check.sh

# Build the full vocabulary
make all

# Verify the output
make verify
```

### Options

| Variable | Default | Description |
|----------|---------|-------------|
| `LOCALE` | `en` | Language for labels |
| `JOBS` | CPU cores | Parallel processing jobs |
| `ROOT_QID` | `Q35120` | Root entity for bucket discovery |
| `SUBJECTS` | `Q5` | Subject QIDs for `skos_subjects` |

```bash
# French labels, 16 parallel jobs
make all LOCALE=fr JOBS=16

# Subject-specific vocabularies
make skos_subjects SUBJECTS="Q5 Q215627"
```

See [QUICK_REFERENCE.md](QUICK_REFERENCE.md) for a command cheat sheet and [README_WORKFLOW.md](README_WORKFLOW.md) for full pipeline documentation.

## Modern Subject Systems

Wiki Core aligns philosophically with **modern, flexible subject systems**, including:

* **YSO** (Finnish General Upper Ontology for Knowledge Organization) — a multilingual ontology used for Finnish cultural and scientific metadata
* **GND** (Gemeinsame Normdatei) — a German authority file for persons, organizations, subjects, and works, widely used in Europe
* **FAST** — a simplified faceted version of LCSH for online catalogs and digital libraries

Unlike these systems, Wiki Core **leverages Wikidata identifiers as its backbone**, providing global interoperability and native multilingual support, while keeping governance and relationships transparent and community-driven.

---

## LCSH vs Wiki Core

|   Feature  |        LCSH       |        Wiki Core      |
|------------|-------------------|-----------------------|
| Foundation | String-based      | ID-based              |
| Syntax     | Pre-coordinated   | Faceted               |
| Language   | English-centric   | Multilingual          |
| Evolution  | Slow, centralized | Open iteration        |
| Governance | Institutional     | Community-driven      |
| Structure  | Encoded hierarchy | Projected graph       |
| Bias       | Implicit, opaque  | Explicit, inspectable |
| Interoperability | Library-specific | Web-native Linked Data |

![LCSH vs Wikicore](https://github.com/mjsuhonos/wikicore/blob/main/lcsh_vs_wikicore.png?raw=true)

## Project Structure

```
wikicore/
├── Makefile                   # Build pipeline (make all)
├── extract_backbone.py        # Extract class hierarchy from chunks
├── generate_buckets.py        # Discover and generate top-level buckets
├── partition_instances.py     # Partition instances into buckets
├── queries/                   # SPARQL queries for Jena
├── source.nosync/             # Input data (not in git)
└── working.nosync/            # Intermediate files (not in git)
```

## Contributing

Contributions are welcome. See [README_WORKFLOW.md](README_WORKFLOW.md) for details on how the pipeline works.

## License

Wiki Core is licensed under **GPLv3**. See [LICENSE](https://github.com/mjsuhonos/wikicore?tab=GPL-3.0-1-ov-file) for details.

## References

* [Wikidata](https://www.wikidata.org/)
* [SKOS Specification](https://www.w3.org/TR/skos-reference/)
* [Library of Congress Subject Headings](https://www.loc.gov/aba/cataloging/subject/)
* [FAST: Faceted Application of Subject Terminology](https://www.oclc.org/en/fast.html)
* [YSO Ontology](https://finto.fi/yso/en/)
* [GND: Gemeinsame Normdatei](https://www.dnb.de/EN/Standardisierung/GND/gnd_node.html)
* [Apache Jena](https://jena.apache.org/)

<p align="center">
  Made with love in Canada
  <img src="https://flagcdn.com/w20/ca.png" alt="Canada" width="20" height="10" style="vertical-align:middle; margin-right:6px;">
</p>
