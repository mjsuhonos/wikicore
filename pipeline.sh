#!/bin/zsh
# Wikidata processing pipeline
# Author: MJ Suhonos <mj@suhonos.ca>
# Usage: ./pipeline.sh <source_dir> <working_dir> <class_names_file> <output_dir>

set -euo pipefail

# -----------------------
# INPUT VARIABLES
# -----------------------
ROOT_DIR="$PWD"

SOURCE_DIR=${1:-"$ROOT_DIR/source.nosync"}
WORK_DIR=${2:-"$ROOT_DIR/working.nosync"}
CLASS_NAMES_FILE=${3:-"$ROOT_DIR/class_names.tsv"}
OUTPUT_DIR=${4:-"$WORK_DIR/output"}

NT_DIR="$WORK_DIR/nt"
JENA_DIR="$WORK_DIR/jena"
SUBJECTS_DIR="$WORK_DIR/subjects"
QUERIES_DIR="$ROOT_DIR/queries"
SKOS_DIR="$WORK_DIR/skos"

RUN_DATE=$(date +%Y%m%d)
COLLECTION_URI="https://wikicore.ca/$RUN_DATE"

mkdir -p "$NT_DIR" "$SUBJECTS_DIR" "$JENA_DIR" "$SKOS_DIR" "$OUTPUT_DIR"

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

mawk -v OFS=' ' -v CLASS_NAMES_FILE="$CLASS_NAMES_FILE" -v OUT_DIR="$NT_DIR" '
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
        if (qid in class_names)
            out_file = OUT_DIR "/" qid "_" class_names[qid] "_instances.nt"
        else
            out_file = OUT_DIR "/P31_other_instances.nt"
    } else {
        out_file = OUT_DIR "/concept_backbone.nt"
    }

    print $0 >> out_file
    open[out_file] = 1
}

END {
    for (f in open) close(f)
}
' "$CORE_PROPS_NT"

# -----------------------
# 3. Extract subject vocabularies
# -----------------------
echo "Extracting unique subjects…"
for f in "$NT_DIR"/Q*_instances.nt; do
    "$ROOT_DIR/extract_unique_subjects.sh" "$f" "$SUBJECTS_DIR/$(basename "${f%.nt}.subjects.tsv")"
done

# -----------------------
# 4. Load backbone into Jena
# -----------------------
echo "Loading backbone into Jena…"
tdb2.tdbloader --loc "$JENA_DIR" "$NT_DIR/concept_backbone.nt"

# -----------------------
# 5. Materialize + export core concepts
# -----------------------
echo "Materializing graph and exporting core concepts…"
tdb2.tdbupdate --loc "$JENA_DIR" --update="$QUERIES_DIR/materialize_graph.rq"

tdb2.tdbquery --loc "$JENA_DIR" --query="$QUERIES_DIR/export.rq" --results=TSV \
  > "$WORK_DIR/core_concepts_raw.tsv"

rg '<http://www.wikidata.org/entity/' "$WORK_DIR/core_concepts_raw.tsv" \
  | sort \
  > "$WORK_DIR/core_concepts_qids.tsv"

# -----------------------
# 6. Remove P31 instances from core concepts
# -----------------------
echo "Filtering out instances…"

sort -m "$SUBJECTS_DIR"/*.subjects.tsv \
  | join -v 1 "$WORK_DIR/core_concepts_qids.tsv" - \
  > "$WORK_DIR/p31_noncore_qids.tsv"

# -----------------------
# 7. Generate SKOS triples
# -----------------------
echo "Generating SKOS triples…"

sed -E 's|(.*)|\1 <http://www.w3.org/1999/02/22-rdf-syntax-ns#type> <http://www.w3.org/2004/02/skos/core#Concept> .|' \
  "$WORK_DIR/p31_noncore_qids.tsv" \
  > "$SKOS_DIR/skos_concepts.nt"

{
  echo "<$COLLECTION_URI> <http://www.w3.org/1999/02/22-rdf-syntax-ns#type> <http://www.w3.org/2004/02/skos/core#Collection> ."
  sed -E "s|(.*)|<$COLLECTION_URI> <http://www.w3.org/2004/02/skos/core#member> \1 .|" \
      "$WORK_DIR/p31_noncore_qids.tsv"
} > "$SKOS_DIR/skos_collection.nt"

gzcat "$SOURCE_DIR/wikidata-20251229-skos-labels-en.nt.gz" \
  | join - "$WORK_DIR/p31_noncore_qids.tsv" \
  > "$SKOS_DIR/skos_labels_en.nt"

# -----------------------
# 8. Export Turtle
# -----------------------
echo "Writing Turtle output…"

cat "$SKOS_DIR"/skos_*.nt \
  | rapper -i ntriples -o turtle - -I 'http://www.wikidata.org/entity/' \
  > "$OUTPUT_DIR/wikicore-$RUN_DATE.ttl"

echo "Done → $OUTPUT_DIR/wikicore-$RUN_DATE.ttl"
