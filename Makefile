# -----------------------
# Wikidata processing pipeline (Makefile version)
# Fully parallel, uses external AWK for section 2
# -----------------------
SHELL := /bin/zsh
.PHONY: all clean process_chunks subjects_sorted cleanup_tmp

# Directories
ROOT_DIR := $(PWD)
SOURCE_DIR := $(ROOT_DIR)/source.nosync
WORK_DIR := $(ROOT_DIR)/working.nosync
NT_DIR := $(WORK_DIR)/nt
JENA_DIR := $(WORK_DIR)/jena
SUBJECTS_DIR := $(WORK_DIR)/subjects
SKOS_DIR := $(WORK_DIR)/skos
OUTPUT_DIR := $(WORK_DIR)/output
TMP_DIR := $(WORK_DIR)/tmp_outputs
SPLIT_DIR := $(WORK_DIR)/splits
QUERIES_DIR := $(ROOT_DIR)/queries

# Files
RUN_DATE := $(shell date +%Y%m%d)
COLLECTION_URI := https://wikicore.ca/$(RUN_DATE)
CORE_PROPS_NT := $(WORK_DIR)/wikidata-core-props-P31-P279-P361.nt
CORE_CONCEPTS_RAW := $(WORK_DIR)/core_concepts_raw.tsv
CORE_CONCEPTS_QIDS := $(WORK_DIR)/core_concepts_qids.tsv
P31_NONCORE_QIDS := $(WORK_DIR)/p31_noncore_qids.tsv
CLASS_NAMES_FILE := $(ROOT_DIR)/class_names.tsv

# SKOS outputs
SKOS_CONCEPTS := $(SKOS_DIR)/skos_concepts.nt
SKOS_COLLECTION := $(SKOS_DIR)/skos_collection.nt
SKOS_LABELS := $(SKOS_DIR)/skos_labels_en.nt
SKOS_NT := $(SKOS_CONCEPTS) $(SKOS_COLLECTION) $(SKOS_LABELS)

# -----------------------
# Default target
# -----------------------
all: $(OUTPUT_DIR)/wikicore-$(RUN_DATE).ttl

# -----------------------
# Step 1: Extract core properties
# -----------------------
$(CORE_PROPS_NT): $(SOURCE_DIR)/wikidata-20251229-propdirect.nt.gz
	mkdir -p $(WORK_DIR)
	pigz -dc $< \
		| rg -F \
			-e '/prop/direct/P31>' \
			-e '/prop/direct/P279>' \
			-e '/prop/direct/P361>' \
		> $@


# -----------------------
# Step 2: Split & process chunks
# -----------------------
$(SPLIT_DIR)/.done: $(CORE_PROPS_NT)
	mkdir -p $(SPLIT_DIR)
	echo "Splitting $(CORE_PROPS_NT) into chunks…"
	gsplit -n l/$$(nproc) $(CORE_PROPS_NT) $(SPLIT_DIR)/chunk_
	touch $@

$(WORK_DIR)/process_chunks.done: $(SPLIT_DIR)/.done
	mkdir -p $(TMP_DIR) $(SUBJECTS_DIR)
	echo "Processing chunks in parallel…"
	ls $(SPLIT_DIR)/chunk_* | \
	parallel -j $$(nproc) \
	         --joblog $(WORK_DIR)/partitioning.log \
	         --eta \
	         --halt now,fail=1 \
	         'echo "[{#}] Processing {}"; \
	         'gawk -v OFS=" " \
	               -v CLASS_NAMES_FILE="$(CLASS_NAMES_FILE)" \
	               -v TMP_DIR="$(TMP_DIR)" \
	               -v SUBJECTS_DIR="$(SUBJECTS_DIR)" \
	               -f partition_chunks.awk {}'
	touch $@


# Merge per-chunk temp outputs into final NT files
$(NT_DIR)/merged_instances.nt: process_chunks
	mkdir -p $(NT_DIR)
	cat $(TMP_DIR)/*_instances.nt > $@

$(NT_DIR)/concept_backbone.nt: $(WORK_DIR)/process_chunks.done
	mkdir -p $(NT_DIR)
	cat $(TMP_DIR)/concept_backbone.nt > $@

# Optional cleanup
cleanup_tmp:
	rm -rf $(TMP_DIR) $(SPLIT_DIR)

# -----------------------
# Step 3: Sort subject vocabularies
# -----------------------
subjects_sorted: $(SUBJECTS_DIR)/*.subjects.tsv
	printf '%s\0' $^ | xargs -0 -P $(nproc) sh -c 'LC_ALL=C sort -u $$1 -o $$1' _

# -----------------------
# Step 4: Load backbone into Jena
# -----------------------
$(JENA_DIR)/tdb_ready: $(NT_DIR)/concept_backbone.nt
	mkdir -p $(JENA_DIR)
	export JENA_JAVA_OPTS="-Xmx32g -XX:ParallelGCThreads=$$(nproc)"
	tdb2.tdbloader --loc $(JENA_DIR) $<
	touch $@

# -----------------------
# Step 5: Materialize + export core concepts
# -----------------------
$(CORE_CONCEPTS_RAW): $(JENA_DIR)/tdb_ready
	tdb2.tdbupdate --loc $(JENA_DIR) --update="$(QUERIES_DIR)/materialize_graph.rq"
	tdb2.tdbquery --loc $(JENA_DIR) --query="$(QUERIES_DIR)/export.rq" --results=TSV > $@

$(CORE_CONCEPTS_QIDS): $(CORE_CONCEPTS_RAW)
	grep -F '<http://www.wikidata.org/entity/' $< | LC_ALL=C sort --parallel=$(shell nproc) -u > $@

# -----------------------
# Step 6: Remove P31 instances from core concepts
# -----------------------
$(P31_NONCORE_QIDS): $(CORE_CONCEPTS_QIDS) subjects_sorted
	LC_ALL=C sort -m $(SUBJECTS_DIR)/*.subjects.tsv | join -v 1 $(CORE_CONCEPTS_QIDS) - > $@

# -----------------------
# Step 7: Generate SKOS triples
# -----------------------
$(SKOS_CONCEPTS): $(P31_NONCORE_QIDS)
	mkdir -p $(SKOS_DIR)
	sed -E 's|(.*)|\1 <http://www.w3.org/1999/02/22-rdf-syntax-ns#type> <http://www.w3.org/2004/02/skos/core#Concept> .|' $< > $@

$(SKOS_COLLECTION): $(P31_NONCORE_QIDS)
	mkdir -p $(SKOS_DIR)
	{ echo "<$(COLLECTION_URI)> <http://www.w3.org/1999/02/22-rdf-syntax-ns#type> <http://www.w3.org/2004/02/skos/core#Collection> ."; \
	  sed -E "s|(.*)|<$(COLLECTION_URI)> <http://www.w3.org/2004/02/skos/core#member> \1 .|" $<; } > $@

$(SKOS_LABELS): $(P31_NONCORE_QIDS) $(SOURCE_DIR)/wikidata-20251229-skos-labels-en.nt.gz
	pigz -dc $(SOURCE_DIR)/wikidata-20251229-skos-labels-en.nt.gz | join - $(P31_NONCORE_QIDS) > $@

# -----------------------
# Step 8: Export Turtle
# -----------------------
$(OUTPUT_DIR)/wikicore-$(RUN_DATE).ttl: $(SKOS_NT)
	mkdir -p $(OUTPUT_DIR)
	riot --syntax=ntriples --output=turtle --base='http://www.wikidata.org/entity/' $^

# -----------------------
# Clean
# -----------------------
clean:
	rm -rf $(WORK_DIR)
