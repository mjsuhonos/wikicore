# Wikicore pipeline Makefile
# Author: MJ Suhonos <mj@suhonos.ca>

SHELL := /bin/zsh
.SHELLFLAGS := -eu -o pipefail -c

ROOT_DIR := $(shell pwd)
SOURCE_DIR ?= $(ROOT_DIR)/source.nosync
WORK_DIR ?= $(ROOT_DIR)/working.nosync
CLASS_NAMES_FILE ?= $(ROOT_DIR)/class_names.tsv
OUTPUT_DIR ?= $(WORK_DIR)/output

NT_DIR := $(WORK_DIR)/nt
JENA_DIR := $(WORK_DIR)/jena
SUBJECTS_DIR := $(WORK_DIR)/subjects
QUERIES_DIR := $(ROOT_DIR)/queries

RUN_DATE := $(shell date +%Y%m%d)
COLLECTION_URI := https://wikicore.ca/$(RUN_DATE)

CORE_PROPS_NT := $(WORK_DIR)/wikidata-core-props-P31-P279-P361.nt
CONCEPT_BACKBONE := $(NT_DIR)/concept_backbone.nt
CORE_CONCEPTS_RAW := $(WORK_DIR)/core_concepts_raw.tsv
CORE_CONCEPTS_QIDS := $(WORK_DIR)/core_concepts_qids.tsv
P31_NONCORE_QIDS := $(WORK_DIR)/p31_noncore_qids.tsv
SKOS_CONCEPTS := $(WORK_DIR)/skos_concepts.nt
SKOS_COLLECTION := $(WORK_DIR)/skos_collection.nt
SKOS_LABELS := $(WORK_DIR)/skos_labels_en.nt
FINAL_TURTLE := $(OUTPUT_DIR)/wikicore-$(RUN_DATE).ttl

# Default target
all: $(FINAL_TURTLE)

# Ensure directories exist
$(NT_DIR) $(JENA_DIR) $(SUBJECTS_DIR) $(OUTPUT_DIR):
	mkdir -p $@

# Step 1: Extract core properties
$(CORE_PROPS_NT): $(SOURCE_DIR)/wikidata-20251229-propdirect.nt.gz | $(WORK_DIR)
	@echo "Extracting P31 / P279 / P361…"
	gzcat $< | rg '/prop/direct/(P31|P279|P361)>' > $@

# Step 2: Split by P31 class vs backbone
$(NT_DIR)/partition.done: $(CORE_PROPS_NT) | $(NT_DIR)
	@echo "Partitioning P31 statements…"
	mawk -v OFS=' ' -v CLASS_NAMES_FILE="$(CLASS_NAMES_FILE)" -v OUT_DIR="$(NT_DIR)" \
	'function trim(s){ gsub(/^[ \t]+|[ \t]+$/, "", s); return s }
	BEGIN {
	    while ((getline < CLASS_NAMES_FILE) > 0)
	        class_names[trim($$1)] = trim($$2)
	    close(CLASS_NAMES_FILE)
	}
	{
	    subj=$$1; pred=$$2; obj=$$3
	    gsub(/[<>]/,"",subj); gsub(/[<>]/,"",pred); gsub(/[<>]/,"",obj)
	    if (pred ~ /prop\/direct\/P31$$/) {
	        qid = obj; sub(".*/","",qid)
	        if (qid in class_names)
	            out_file = OUT_DIR "/" qid "_" class_names[qid] "_instances.nt"
	        else
	            out_file = OUT_DIR "/P31_other_instances.nt"
	    } else {
	        out_file = OUT_DIR "/concept_backbone.nt"
	    }
	    print $$0 >> out_file
	    open[out_file] = 1
	}
	END { for (f in open) close(f) }' $<
	touch $@

$(P31_SUBJECTS): $(PARTITION_DONE)
	@:

# Step 3: Extract subject vocabularies
SUBJECT_FILES := $(patsubst $(NT_DIR)/%.nt,$(SUBJECTS_DIR)/%.subjects.tsv,$(wildcard $(NT_DIR)/Q*_instances.nt))
$(SUBJECTS_DIR)/%.subjects.tsv: $(NT_DIR)/%.nt | $(SUBJECTS_DIR)
	@echo "Extracting unique subjects for $<"
	$(ROOT_DIR)/extract_unique_subjects.sh $< $@

# Step 4: Load backbone into Jena
$(JENA_DIR)/tdb_loaded: $(CONCEPT_BACKBONE) | $(JENA_DIR)
	@echo "Loading backbone into Jena…"
	tdb2.tdbloader --loc $(JENA_DIR) $(CONCEPT_BACKBONE)
	touch $@

# Step 5: Materialize + export core concepts
$(CORE_CONCEPTS_RAW): $(JENA_DIR)/tdb_loaded | $(WORK_DIR)
	@echo "Materializing graph and exporting core concepts…"
	tdb2.tdbupdate --loc $(JENA_DIR) --update="$(QUERIES_DIR)/materialize_graph.rq"
	tdb2.tdbquery --loc $(JENA_DIR) --query="$(QUERIES_DIR)/export.rq" --results=TSV \
		> $@
	@rg '<http://www.wikidata.org/entity/' $@ | sort > $(CORE_CONCEPTS_QIDS)

# Step 6: Remove P31 instances from core concepts
$(P31_NONCORE_QIDS): $(SUBJECT_FILES) $(CORE_CONCEPTS_QIDS)
	@echo "Filtering out instances…"
	cat $(SUBJECTS_DIR)/*.subjects.tsv | sort -u | join -v 1 $(CORE_CONCEPTS_QIDS) - > $@

# Step 7: Generate SKOS triples
$(SKOS_CONCEPTS): $(P31_NONCORE_QIDS)
	@echo "Generating SKOS triples…"
	sed -E 's|(.*)|\1 <http://www.w3.org/1999/02/22-rdf-syntax-ns#type> <http://www.w3.org/2004/02/skos/core#Concept> .|' \
		$< > $@

$(SKOS_COLLECTION): $(P31_NONCORE_QIDS)
	@echo "Generating SKOS collection…"
	{ \
		echo "<$(COLLECTION_URI)> <http://www.w3.org/1999/02/22-rdf-syntax-ns#type> <http://www.w3.org/2004/02/skos/core#Collection> ."; \
		sed -E "s|(.*)|<$(COLLECTION_URI)> <http://www.w3.org/2004/02/skos/core#member> \1 .|" $< ; \
	} > $@

$(SKOS_LABELS): $(P31_NONCORE_QIDS) $(SOURCE_DIR)/wikidata-20251229-skos-labels-en.nt.gz
	@echo "Extracting SKOS labels…"
	gzcat $(SOURCE_DIR)/wikidata-20251229-skos-labels-en.nt.gz | join - $< > $@

# Step 8: Export Turtle
$(FINAL_TURTLE): $(SKOS_CONCEPTS) $(SKOS_COLLECTION) $(SKOS_LABELS) | $(OUTPUT_DIR)
	@echo "Writing Turtle output…"
	cat $(WORK_DIR)/skos_*.nt | rapper -i ntriples -o turtle - -I 'http://www.wikidata.org/entity/' > $@
	@echo "Done → $@"

# Clean intermediate files
clean:
	rm -rf $(WORK_DIR)

.PHONY: all clean
