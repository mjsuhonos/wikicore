<img src="https://github.com/mjsuhonos/wikicore/blob/main/wikicore_logo_trans.png?raw=true" alt="wikicore" width="200"/>

# Wiki Core

Wiki Core is a modern, open approach to subject organization. By anchoring topics in stable identifiers from Wikidata instead of pre-coordinated strings, it separates meaning from syntax, supports multilingual labels, and enables flexible, faceted discovery.

For developers, Wiki Core provides an ID-based, machine-readable vocabulary designed for modern applications. Its faceted, graph-oriented structure and multilingual labels support semantic search, API integration, and flexible data linking. Unlike legacy library vocabularies, it is web-native, interoperable, and ready for automated indexing workflows, while still preserving human oversight.

**Wiki Core does not replace cataloguers** — it repositions their expertise. Rather than encoding complex subject strings, cataloguers focus on curating concepts, defining boundaries, and shaping relationships that guide discovery. This approach makes their judgment more visible and impactful, while allowing systems to handle repetitive or automated tasks.

## Features

- **Openly licensed** (GPLv3), community-driven, and designed to evolve transparently
- **Machine-friendly**: intended for integration with automated indexing tools, catalogs, and semantic pipelines
- Anchors topics in **Wikidata identifiers** to ensure global interoperability and stable semantics
- Components can be **combined, extended, or adapted** to different domains and applications
- Supports metadata, indexing, and subject classification workflows
- Native multilingual labels and terminology

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

Wiki Core aligns philosophically with **modern, flexible subject systems**, including:

* **YSO** (Finnish General Upper Ontology for Knowledge Organization) — a multilingual ontology used for Finnish cultural and scientific metadata
* **GND** (Gemeinsame Normdatei) — a German authority file for persons, organizations, subjects, and works, widely used in Europe
* **FAST** — a simplified faceted version of LCSH for online catalogs and digital libraries

Unlike these systems, Wiki Core **leverages Wikidata identifiers as its backbone**, providing global interoperability and native multilingual support, while keeping governance and relationships transparent and community-driven.

---

## Coverage

Wiki Core is derived from Wikidata and filtered to items with English-language sitelinks (~10.1M of 116.6M total entities). Subject coverage is organized into two main tracks: **named classes** (things) and **humans** (people by occupation).

### Subject filtering pipeline

| Stage | Count |
|-------|------:|
| Total Wikidata entities | 116,659,543 |
| Has English sitelink | 10,150,254 |
| In scope (has P31 / taxonomy) | 9,718,047 |
| Core taxonomy concepts | 29,508 |

### Humans (Q5) — by occupation group

| Occupation | Subjects |
|------------|--------:|
| Sports | 690,257 |
| Politics | 341,619 |
| Film | 186,885 |
| Literature | 176,881 |
| Science | 169,254 |
| Music | 146,976 |
| Arts | 112,919 |
| Education | 101,441 |
| Media | 84,567 |
| Business | 80,843 |
| Law | 78,448 |
| Military | 73,900 |
| Religion | 62,283 |
| Engineering | 46,684 |
| Medicine | 42,700 |
| Activism | 32,355 |
| Misc | 30,558 |
| Genealogy | 5,868 |
| Other | 1,050 |
| **Total (unique)** | **2,106,826** |

### Named classes — by domain group

| Domain | Subjects |
|--------|--------:|
| Science | 577,240 |
| Music | 347,174 |
| Sports | 299,797 |
| Village | 212,189 |
| Film | 181,801 |
| Community | 181,114 |
| Organization | 162,632 |
| Building | 161,123 |
| Railway | 115,307 |
| Television | 109,340 |
| Literary | 96,214 |
| Name | 93,497 |
| Water | 92,173 |
| Military | 82,858 |
| School | 80,530 |
| Media | 80,156 |
| Political | 67,822 |
| City | 67,479 |
| District | 66,039 |
| Municipality | 60,326 |
| Soccer | 59,464 |
| Commune | 57,774 |
| Transport | 46,900 |
| Astronomy | 46,848 |
| Town | 45,941 |
| Recurring | 44,985 |
| Religion | 44,375 |
| Cultural | 43,412 |
| Mountain | 41,005 |
| Geography | 40,755 |
| Video | 39,959 |
| Historic | 36,402 |
| Aircraft | 35,288 |
| Other | 32,476 |
| Olympic | 31,144 |
| Election | 29,881 |
| Technology | 25,473 |
| Character | 23,387 |
| Group | 19,117 |
| Language | 18,794 |
| Comic | 8,240 |
| **Total (unique)** | **3,399,735** |

![Coverage Sankey Diagram](https://github.com/mjsuhonos/wikicore/blob/main/wikicore-sankey.png?raw=true)

---

## Build Pipeline

Wiki Core is built from Wikidata dumps using a GNU Make pipeline. The pipeline extracts SKOS concept vocabularies in N-Triples format, organized by subject class or occupation group.

### Prerequisites

- GNU Make, `parallel`, `pigz`, `gsplit`, `ripgrep` (`rg`)
- [Apache Jena](https://jena.apache.org/) (`tdb2.tdbloader`, `tdb2.tdbupdate`, `tdb2.tdbquery`, `riot`)
- Python 3
- Wikidata property-direct and SKOS labels dumps in `source.nosync/`

### Usage

```
make <target> [OPTIONS]
```

**Targets:**

| Target | Description |
|--------|-------------|
| `core` | Build the core SKOS vocab (`wikicore-DATE-core-LOCALE.nt`) |
| `subjects` | Build one `.nt` per QID across all `classes/` TSVs |
| `classes` | Build one combined `.nt` per `classes/` TSV |
| `occupations` | Build one combined `.nt` per `occupations/` TSV |
| `all` | Run `core` + `subjects` + `classes` + `occupations` |
| `turtle` | Convert all `.nt` files to compressed Turtle (`.ttl.gz`) |
| `clean` | Remove all working files |

**Targeted builds:**

| Target | Description |
|--------|-------------|
| `skos_subjects SUBJECTS='Q5 Q532'` | Build SKOS for specific QIDs |
| `skos_class CLASS_FILE=classes/aircraft.tsv` | Build combined `.nt` for a single class |
| `skos_occupation OCC_FILE=occupations/engineer.tsv` | Build combined `.nt` for a single occupation (output prefixed `occ-`) |

**Options:**

| Option | Default | Description |
|--------|---------|-------------|
| `LOCALE` | `en` | Output language |
| `JOBS` | `nproc` | Parallel jobs |

**Examples:**

```sh
make core
make all LOCALE=fr
make skos_subjects SUBJECTS='Q5 Q532'
make skos_class CLASS_FILE=classes/aircraft.tsv
make skos_occupation OCC_FILE=occupations/medicine.tsv
make turtle
```

### Pipeline stages

The build proceeds through the following stages:

1. **Extract core properties** — filters P31, P279, P361 triples from the Wikidata property-direct dump
2. **Split & partition** — chunks the core properties and partitions them by class into per-subject TSVs
3. **Prepare subject vocabularies** — sorts, deduplicates, and filters each per-subject TSV against the sitelinks list
4. **Load backbone into Jena TDB2** — loads the concept backbone graph
5. **Materialize & export core concepts** — runs SPARQL to materialize ancestor paths and child counts, then exports core QIDs
6. **Extract localized labels** — decompresses and splits the SKOS labels dump by locale
7. **Generate SKOS vocabs** — assembles concept declarations, concept scheme membership, labels, and `skos:broader` relations into `.nt` files
8. **Convert to Turtle** — re-serializes `.nt` files to prefixed, compressed Turtle using Jena RIOT

### Output format

Each output file is an N-Triples (or compressed Turtle) SKOS vocabulary named:

```
wikicore-YYYYMMDD-<class|QID>-<locale>.nt
```

SKOS triples included per concept:
- `rdf:type skos:Concept`
- `skos:inScheme <https://wikicore.ca/YYYYMMDD>`
- `skos:prefLabel` / `skos:altLabel` (localized)
- `skos:broader` (from Wikidata P279 / P31 hierarchy)

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
