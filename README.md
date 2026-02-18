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

Wiki Core is built from Wikidata dumps using a GNU Make pipeline. The pipeline extracts SKOS concept vocabularies in N-Triples format, organized by subject class or occupation group.

### Prerequisites

- GNU Make, `parallel`, `pigz`, `gsplit`, `ripgrep` (`rg`)
- [Apache Jena](https://jena.apache.org/) (`tdb2.tdbloader`, `tdb2.tdbupdate`, `tdb2.tdbquery`, `riot`)
- Python 3
- Wikidata property-direct and SKOS labels dumps in `source.nosync/`

### Expected Output from `make all`

Running `make all` generates **2,245 SKOS vocabulary files**:

| Target | Files | Description |
|--------|------:|-------------|
| `core` | 1 | Core taxonomy (29,508 concepts) |
| `subjects` | 732 | Individual class QID files |
| `occ_subjects` | 1,451 | Individual occupation QID files (SKOS about Q5 humans) |
| `classes` | 42 | Class group files |
| `occupations` | 19 | Occupation group files (SKOS about Q5 humans) |
| **TOTAL** | **2,245** | ~5-7 GB disk space |

### Usage

```
make <target> [OPTIONS]
```

**Main targets:**

| Target | Description |
|--------|-------------|
| `core` | Build the core SKOS vocab (`wikicore-DATE-core-LOCALE.nt`) |
| `subjects` | Build one `.nt` per class QID (732 files) |
| `occ_subjects` | Build one `.nt` per occupation QID (1,451 files) |
| `classes` | Build one combined `.nt` per class group (42 files) |
| `occupations` | Build one combined `.nt` per occupation group (19 files) |
| `all` | Run all targets above |
| `turtle` | Convert all `.nt` files to compressed Turtle (`.ttl.gz`) |
| `clean` | Remove working files |

**Targeted builds:**

| Target | Description |
|--------|-------------|
| `skos_subjects SUBJECTS='Q5 Q532'` | Build SKOS for specific QIDs |
| `skos_class CLASS_FILE=classes/aircraft.tsv` | Build combined `.nt` for a single class |
| `skos_occupation OCC_FILE=occupations/engineering.tsv` | Build SKOS for a specific occupation group |
| `skos_by_occupation OBJECT=Q7888586` | Build SKOS for Q5 humans with a specific occupation QID |

**Options:**

| Option | Default | Description |
|--------|---------|-------------|
| `LOCALE` | `en` | Output language |
| `JOBS` | `nproc` | Parallel jobs |

**Examples:**

```sh
make core              # Generate core taxonomy
make subjects          # Generate 732 class QID files
make occ_subjects      # Generate 1,451 occupation QID files
make all               # Generate all 2,245 files
make all LOCALE=fr     # Generate French-language output
make skos_by_occupation OBJECT=Q7888586    # Chemical engineers only
make turtle            # Convert to compressed Turtle
```

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

### Output Files

**Individual class files** (732 files):
- `wikicore-20260218-Q3305213-en.nt` (aircraft types)
- `wikicore-20260218-Q11424-en.nt` (films)
- ConceptScheme: `https://wikicore.ca/DATE/subjects/{QID}`

**Individual occupation files** (1,451 files):
- `wikicore-20260218-Q7888586-en.nt` (chemical engineers - 491 people)
- `wikicore-20260218-Q82955-en.nt` (politicians - 297,739 people)
- ConceptScheme: `https://wikicore.ca/DATE/occupations/{QID}`
- Contains SKOS about Q5 humans with that occupation

**Class group files** (42 files):
- `wikicore-20260218-aircraft-en.nt` (combined from multiple aircraft class QIDs)
- `wikicore-20260218-science-en.nt` (combined from multiple science class QIDs)

**Occupation group files** (19 files):
- `wikicore-20260218-occ-engineering-en.nt` (all engineer types: Q81096, Q1326886, Q13582652, etc.)
- `wikicore-20260218-occ-science-en.nt` (all scientist types)

### Occupation Vocabularies

**Important:** Occupation SKOS vocabularies generate statements about **Q5 (human) entities**, not about occupation concepts.

**Individual occupation files** (`occ_subjects`):
- One file per occupation QID (e.g., Q7888586 = chemical engineer)
- Contains SKOS about all Q5 humans with that specific occupation
- Example: `wikicore-DATE-Q7888586-en.nt` has SKOS about 491 chemical engineers

**Grouped occupation files** (`occupations`):
- One file per thematic group (e.g., engineering, science, arts)
- Combines multiple related occupations
- Example: `wikicore-DATE-occ-engineering-en.nt` includes engineers, electrical engineers, mechanical engineers, chemical engineers, etc. (25 occupation types, 46,684 people total)

The pipeline:
1. Extracts all P106 (occupation) statements from Wikidata
2. Filters for Q5 (human) entities with English sitelinks
3. Groups humans by occupation QID or occupation group
4. Generates SKOS with `skos:inScheme <https://wikicore.ca/DATE/occupations/{QID or category}>`

### Output format

Each output file is an N-Triples (or compressed Turtle) SKOS vocabulary named:

```
wikicore-YYYYMMDD-<class|QID|occ-name>-<locale>.nt
```

SKOS triples included per concept:
- `rdf:type skos:Concept`
- `skos:inScheme <https://wikicore.ca/YYYYMMDD/...>`
- `skos:prefLabel` / `skos:altLabel` (localized)
- `skos:broader` (from Wikidata P279 / P31 hierarchy)

**Example SKOS for a human (from occupation file):**
```turtle
<http://www.wikidata.org/entity/Q7254> rdf:type skos:Concept .
<http://www.wikidata.org/entity/Q7254> skos:inScheme <https://wikicore.ca/20260218/occupations/Q1326886> .
<http://www.wikidata.org/entity/Q7254> skos:prefLabel "Ada Lovelace"@en .
<http://www.wikidata.org/entity/Q7254> skos:broader <...> .
```

---

## Verification

After running `make all`, verify output:

```bash
# Count total generated files
ls -1 wikicore-*.nt | wc -l
# Expected: 2,245

# Count occupation QID files
cat working.nosync/occ_qids.txt | wc -l
# Expected: 1,451

# Count class group files
ls -1 wikicore-*.nt | grep -v -E 'Q[0-9]+|occ-|core' | wc -l
# Expected: 42

# Count occupation group files
ls -1 wikicore-*-occ-*.nt | wc -l
# Expected: 19
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
