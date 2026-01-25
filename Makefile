# -----------------------
# Wikidata processing pipeline (Makefile)
# -----------------------

SHELL := /bin/zsh
.PHONY: all clean

# -----------------------
# Paths
# -----------------------
ROOT_DIR := $(PWD)
SOURCE_DIR := $(ROOT_DIR)/source.nosync
WORK_DIR := $(ROOT_DIR)/working.nosync
NT_DIR := $(WORK_DIR)/nt
JENA_DIR := $(WORK_DIR)/jena
SUBJECTS_DIR := $(WORK_DIR)/subjects
SKOS_DIR := $(WORK_DIR)/skos
TMP_DIR := $(WORK_DIR)/tmp_outputs
SPLIT_DIR := $(WORK_DIR)/splits
QUERIES_DIR := $(ROOT_DIR)/queries

CLASS_NAMES_FILE := $(ROOT_DIR)/class_names.tsv

export JENA_JAVA_OPTS="-Xmx32g -XX:ParallelGCThreads=$$(nproc)"

RUN_DATE := $(shell date +%Y%m%d)
COLLECTION_URI := https://wikicore.ca/$(RUN_DATE)

# -----------------------
# Inputs
# -----------------------
PROP_DIRECT_GZ := $(SOURCE_DIR)/wikidata-20251229-propdirect.nt.gz
SKOS_LABELS_GZ := $(SOURCE_DIR)/wikidata-20251229-skos-labels-en.nt.gz

# -----------------------
# Core files
# -----------------------
CORE_PROPS_NT := $(WORK_DIR)/wikidata-core-props-P31-P279-P361.nt
CORE_CONCEPTS_RAW := $(WORK_DIR)/core_concepts_raw.tsv
CORE_CONCEPTS_QIDS := $(WORK_DIR)/core_concepts_qids.tsv
P31_NONCORE_QIDS := $(WORK_DIR)/p31_noncore_qids.tsv

# -----------------------
# SKOS outputs
# -----------------------
SKOS_CONCEPTS := $(SKOS_DIR)/skos_concepts.nt
SKOS_COLLECTION := $(SKOS_DIR)/skos_collection.nt
SKOS_LABELS := $(SKOS_DIR)/skos_labels_en.nt
SKOS_NT := $(SKOS_CONCEPTS) $(SKOS_COLLECTION) $(SKOS_LABELS)

# -----------------------
# Stamp files
# -----------------------
EXTRACT_DONE := $(WORK_DIR)/extract.done
SPLIT_DONE := $(SPLIT_DIR)/split.done
PARTITION_DONE := $(WORK_DIR)/partition.done
SUBJECTS_SORTED_DONE := $(WORK_DIR)/subjects_sorted.done
JENA_DONE := $(JENA_DIR)/jena.done
CORE_CONCEPTS_DONE := $(WORK_DIR)/core_concepts.done
FILTER_DONE := $(WORK_DIR)/filter.done
SKOS_DONE := $(WORK_DIR)/skos.done

# -----------------------
# Default target
# -----------------------
FINAL_TTL := $(ROOT_DIR)/wikicore-$(RUN_DATE).ttl
all: $(FINAL_TTL)

# -----------------------
# 1. Extract core properties
# -----------------------
$(EXTRACT_DONE): $(PROP_DIRECT_GZ)
	mkdir -p $(WORK_DIR)
	pigz -dc $< \
	  | rg -F \
	      -e '/prop/direct/P31>' \
	      -e '/prop/direct/P279>' \
	      -e '/prop/direct/P361>' \
	  > $(CORE_PROPS_NT)
	touch $@

# -----------------------
# 2a. Split into chunks
# -----------------------
$(SPLIT_DONE): $(EXTRACT_DONE)
	mkdir -p $(SPLIT_DIR)
	@echo "Splitting core properties into chunks…"
	gsplit -n l/$$(nproc) $(CORE_PROPS_NT) $(SPLIT_DIR)/chunk_
	touch $@

# -----------------------
# 2b. Partition chunks (parallel)
# -----------------------
$(PARTITION_DONE): $(SPLIT_DONE)
	mkdir -p $(TMP_DIR) $(SUBJECTS_DIR)
	@echo "Partitioning chunks in parallel…"
	ls $(SPLIT_DIR)/chunk_* | \
	  parallel -j $$(nproc) \
	           --eta \
	           --halt now,fail=1 \
	           'echo "[{#}] Processing {}"; \
	            python3 $(ROOT_DIR)/partition_chunks.py {} $(CLASS_NAMES_FILE) $(TMP_DIR) $(SUBJECTS_DIR)'
	touch $@

# -----------------------
# 3. Sort subject vocabularies
# -----------------------
$(SUBJECTS_SORTED_DONE): $(PARTITION_DONE)
	@echo "Sorting and deduplicating subject vocabularies…"
	# Use null-delimited list for safety with spaces in filenames
	find $(SUBJECTS_DIR) -name '*.subjects.tsv' -print0 \
	  | xargs -0 -n 1 -P $$(nproc) \
	      sh -c 'echo "Sorting $$1…"; LC_ALL=C sort -u "$$1" -o "$$1"' _
	touch $@

# -----------------------
# 4. Load backbone into Jena
# -----------------------
$(JENA_DONE): $(PARTITION_DONE)
	mkdir -p $(JENA_DIR)
	tdb2.tdbloader --loc $(JENA_DIR) $(TMP_DIR)/concept_backbone.nt
	touch $@

# -----------------------
# 5. Materialize + export core concepts
# -----------------------
$(CORE_CONCEPTS_DONE): $(JENA_DONE)
	tdb2.tdbupdate --loc $(JENA_DIR) --update="$(QUERIES_DIR)/materialize_graph.rq"
	tdb2.tdbquery --loc $(JENA_DIR) --query="$(QUERIES_DIR)/export.rq" --results=TSV \
	  > $(CORE_CONCEPTS_RAW)
	grep -F '<http://www.wikidata.org/entity/' $(CORE_CONCEPTS_RAW) \
	  | LC_ALL=C sort --parallel=$$(nproc) -u \
	  > $(CORE_CONCEPTS_QIDS)
	touch $@

# -----------------------
# 6. Remove P31 instances from core concepts
# -----------------------
$(FILTER_DONE): $(CORE_CONCEPTS_DONE) $(SUBJECTS_SORTED_DONE)
	@echo "Filtering out P31 instances from core concepts…"
	LC_ALL=C sort -m $(SUBJECTS_DIR)/*.subjects.tsv \
	  | join -v 1 $(CORE_CONCEPTS_QIDS) - \
	  > $(P31_NONCORE_QIDS)
	touch $@

# -----------------------
# 7. Generate SKOS triples (parallel substeps)
# -----------------------

SKOS_CONCEPTS := $(SKOS_DIR)/skos_concepts.nt
SKOS_COLLECTION := $(SKOS_DIR)/skos_collection.nt
SKOS_LABELS := $(SKOS_DIR)/skos_labels_en.nt
SKOS_NT := $(SKOS_CONCEPTS) $(SKOS_COLLECTION) $(SKOS_LABELS)

# --- 7a. skos:Concept typing
$(SKOS_CONCEPTS): $(FILTER_DONE)
	mkdir -p $(SKOS_DIR)
	sed -E 's|(.*)|\1 <http://www.w3.org/1999/02/22-rdf-syntax-ns#type> <http://www.w3.org/2004/02/skos/core#Concept> .|' \
	  $(P31_NONCORE_QIDS) \
	  > $@

# --- 7b. skos:Collection + members
$(SKOS_COLLECTION): $(FILTER_DONE)
	mkdir -p $(SKOS_DIR)
	{ \
	  echo "<$(COLLECTION_URI)> <http://www.w3.org/1999/02/22-rdf-syntax-ns#type> <http://www.w3.org/2004/02/skos/core#Collection> ."; \
	  sed -E "s|(.*)|<$(COLLECTION_URI)> <http://www.w3.org/2004/02/skos/core#member> \1 .|" \
	    $(P31_NONCORE_QIDS); \
	} > $@

# --- 7c. English labels (join)
$(SKOS_LABELS): $(FILTER_DONE) $(SKOS_LABELS_GZ)
	mkdir -p $(SKOS_DIR)
	pigz -dc $(SKOS_LABELS_GZ) \
	  | join - $(P31_NONCORE_QIDS) \
	  > $@

# --- 7d. Stamp (fan-in)
$(SKOS_DONE): $(SKOS_NT)
	touch $@

# -----------------------
# 8. Export Turtle
# -----------------------

$(FINAL_TTL): $(SKOS_NT)
	@echo "Merging SKOS N-Triples and converting to Turtle…"
	riot --formatted=turtle \
	     --base='http://www.w3.org/2004/02/skos/core#' \
	     <(cat $^) > $@

# -----------------------
# Clean
# -----------------------
clean:
	rm -rf $(WORK_DIR)
