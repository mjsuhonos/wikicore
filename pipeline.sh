#!/bin/zsh
# Wikidata processing pipeline
# Author: MJ Suhonos <mj@suhonos.ca>
# Usage: ./pipeline.sh <source_dir> <working_dir> <class_names_file> <output_dir>

set -euo pipefail

# -----------------------
# INPUT VARIABLES
# -----------------------
SOURCE_DIR=${1:-"../source"}
WORK_DIR=${2:-"./working"}
CLASS_NAMES_FILE=${3:-"$WORK_DIR/class_names.tsv"}
OUTPUT_DIR=${4:-"$WORK_DIR/output"}

NT_DIR="$WORK_DIR/nt"
JENA_DIR="$WORK_DIR/jena"
SUBJECTS_DIR="$WORK_DIR/subjects"
QUERIES_DIR="$WORK_DIR/queries"

RUN_DATE=$(date +%Y%m%d)
COLLECTION_URI="https://wikicore.ca/$RUN_DATE"

mkdir -p "$NT_DIR" "$SUBJECTS_DIR" "$JENA_DIR" "$OUTPUT_DIR"

# -----------------------
# 1. Extract core properties
# -----------------------
echo "Extracting P31 / P279 / P361…"

CORE_PROPS_NT="$WORK_DIR/wikidata-core-props-P31-P279-P361.nt"

gzcat "$SOURCE_DIR/wikidata-20251229-propdirect.nt.gz" \
  | rg '/prop/direct/(P31|P279|P361)>' \
  > "$CORE_PROPS_NT"

# -----------------------
# 2. Split by P31 class vs backbone
# -----------------------
echo "Partitioning P31 statements…"
cd "$NT_DIR"

mawk -v OFS=' ' -v CLASS_NAMES_FILE="$CLASS_NAMES_FILE" '
function trim(s){ gsub(/^[ \t]+|[ \t]+$/, "", s); return s }

BEGIN {
    while ((getline < CLASS_NAMES_FILE) > 0)
        class_names[trim($1)] = trim($2)
    close(CLASS_NAMES_FILE)
}

{
    subj=$1; pred=$2; obj=$3
    gsub(/[<>]/,"",subj); gsub(/[<>]/,"",pred); gsub(/[<>]/,"",obj)

    if (pred ~ /prop\/direct\/P31$/) {
        qid = obj
        sub(".*/","",qid)
        out_file = (qid in class_names)
            ? qid "_" class_names[qid] "_instances.nt"
            : "P31_other_instances.nt"
    } else {
        out_file = "concept_backbone.nt"
    }

    print $0 >> out_file
    open[out_file]
}

END {
    for (f in open) close(f)
}
' "$CORE_PROPS_NT"

# -----------------------
# 3. Extract subject vocabularies
# -----------------------
echo "Extracting unique subjects…"
for f in Q*_instances.nt; do
    ../../extract_unique_subjects.sh "$f" "$SUBJECTS_DIR/${f%.nt}.subjects.tsv"
done

# -----------------------
# 4. Load backbone into Jena
# -----------------------
echo "Loading backbone into Jena…"
cd "$JENA_DIR"
tdb2.tdbloader "$NT_DIR/concept_backbone.nt"

# -----------------------
# 5. Materialize + export core concepts
# -----------------------
echo "Materializing graph and exporting core concepts…"
tdb2.tdbupdate --update="$QUERIES_DIR/materialize_graph.rq"

tdb2.tdbquery --query="$QUERIES_DIR/export.rq" --results=TSV \
  > "$OUTPUT_DIR/core_concepts_raw.tsv"

rg '<http://www.wikidata.org/entity/' "$OUTPUT_DIR/core_concepts_raw.tsv" \
  | sort \
  > "$WORK_DIR/core_concepts_qids.tsv"

# -----------------------
# 6. Remove core concepts from P31 instances
# -----------------------
echo "Filtering out core concepts…"
cd "$WORK_DIR"

cat "$SUBJECTS_DIR"/*.subjects.tsv \
  | sort -u \
  | join -v 1 core_concepts_qids.tsv - \
  > p31_noncore_qids.tsv

# -----------------------
# 7. Generate SKOS triples
# -----------------------
echo "Generating SKOS triples…"

sed -E 's|(.*)|\1 <http://www.w3.org/1999/02/22-rdf-syntax-ns#type> <http://www.w3.org/2004/02/skos/core#Concept> .|' \
  p31_noncore_qids.tsv \
  > skos_concepts.nt

{
  echo "<$COLLECTION_URI> <http://www.w3.org/1999/02/22-rdf-syntax-ns#type> <http://www.w3.org/2004/02/skos/core#Collection> ."
  sed -E "s|(.*)|<$COLLECTION_URI> <http://www.w3.org/2004/02/skos/core#member> \1 .|" \
      p31_noncore_qids.tsv
} > skos_collection.nt

gzcat "$SOURCE_DIR/wikidata-20251229-skos-labels-en.nt.gz" \
  | join - p31_noncore_qids.tsv \
  > skos_labels_en.nt

# -----------------------
# 8. Export Turtle
# -----------------------
echo "Writing Turtle output…"

cat skos_*.nt \
  | rapper -i ntriples -o turtle - -I 'http://www.wikidata.org/entity/' \
  > "$OUTPUT_DIR/wikicore-$RUN_DATE.ttl"

echo "Done → $OUTPUT_DIR/wikicore-$RUN_DATE.ttl"
