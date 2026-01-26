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
JENA_DIR := $(WORK_DIR)/jena
SUBJECTS_DIR := $(WORK_DIR)/subjects
SKOS_DIR := $(WORK_DIR)/skos
SPLIT_DIR := $(WORK_DIR)/splits
QUERIES_DIR := $(ROOT_DIR)/queries
CLASS_NAMES_FILE := $(ROOT_DIR)/class_names.tsv

# -----------------------
# Options
# -----------------------
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
CORE_NOSUBJECT_QIDS := $(WORK_DIR)/core_nosubject_qids.tsv
CONCEPT_BACKBONE := $(WORK_DIR)/concept_backbone.nt

# -----------------------
# SKOS outputs
# -----------------------
SKOS_CONCEPTS   := $(SKOS_DIR)/skos_concepts.nt
SKOS_COLLECTION := $(SKOS_DIR)/skos_collection.nt
SKOS_LABELS     := $(SKOS_DIR)/skos_labels_en.nt
SKOS_BROADER    := $(SKOS_DIR)/skos_broader.nt

SKOS_NT := \
	$(SKOS_CONCEPTS) \
	$(SKOS_COLLECTION) \
	$(SKOS_LABELS) \
	$(SKOS_BROADER)

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
# Shared RDF / SKOS constants
# -----------------------

RDF_TYPE_URI        = http://www.w3.org/1999/02/22-rdf-syntax-ns\#type
SKOS_CONCEPT_URI    = http://www.w3.org/2004/02/skos/core\#Concept
SKOS_COLLECTION_URI = http://www.w3.org/2004/02/skos/core\#Collection
SKOS_MEMBER_URI     = http://www.w3.org/2004/02/skos/core\#member
SKOS_BROADER_URI    = http://www.w3.org/2004/02/skos/core\#broader

# -----------------------
# Shared SKOS emitters (macros)
# -----------------------

# Emit: <QID> rdf:type skos:Concept .
# $(1) = file containing <QID> IRIs (one per line)
define emit_skos_concepts
sed -E 's|(.*)|\1 <$(RDF_TYPE_URI)> <$(SKOS_CONCEPT_URI)> .|' $(1)
endef

# Emit:
#   <COLLECTION> rdf:type skos:Collection .
#   <COLLECTION> skos:member <QID> .
# $(1) = collection URI (no <>)
# $(2) = file containing <QID> IRIs
define emit_skos_collection
{ \
  echo "<$(1)> <$(RDF_TYPE_URI)> <$(SKOS_COLLECTION_URI)> ."; \
  sed -E 's|(.*)|<$(1)> <$(SKOS_MEMBER_URI)> \1 .|' $(2); \
}
endef

# -----------------------
# Default target
# -----------------------
FINAL_TTL := $(ROOT_DIR)/wikicore-$(RUN_DATE).ttl
all: $(FINAL_TTL)

# -----------------------
# 1. Extract core properties
# -----------------------
$(EXTRACT_DONE): $(PROP_DIRECT_GZ)
	@echo "=====> Extracting core properties…"
	mkdir -p $(WORK_DIR)
	pigz -dc $< \
	  | rg -F \
	      -e '/prop/direct/P31>' \
	      -e '/prop/direct/P279>' \
	      -e '/prop/direct/P361>' \
	  | rg -F -v '_:' \
	  > $(CORE_PROPS_NT)
	touch $@

# -----------------------
# 2a. Split into chunks
# -----------------------
$(SPLIT_DONE): $(EXTRACT_DONE)
	mkdir -p $(SPLIT_DIR)
	@echo "=====> Splitting core properties into chunks…"
	gsplit -n l/$$(nproc) $(CORE_PROPS_NT) $(SPLIT_DIR)/chunk_
	touch $@

# -----------------------
# 2b. Partition chunks (parallel)
# -----------------------
$(CONCEPT_BACKBONE): $(SPLIT_DONE)
	mkdir -p $(SUBJECTS_DIR)
	@echo "=====> Partitioning chunks in parallel and generating backbone…"
	ls $(SPLIT_DIR)/chunk_* | \
	  parallel -j $$(nproc) \
	           --eta \
	           --halt now,fail=1 \
	           'echo "[{#}] Processing {}"; \
	            python3 $(ROOT_DIR)/partition_chunks.py {} $(CLASS_NAMES_FILE) $(WORK_DIR) $(SUBJECTS_DIR)'
	@echo "=====> → $(CONCEPT_BACKBONE) created"

# Partition done now depends on the backbone
$(PARTITION_DONE): $(CONCEPT_BACKBONE)
	touch $@

# -----------------------
# 3. Sort subject vocabularies
# -----------------------
$(SUBJECTS_SORTED_DONE): $(PARTITION_DONE)
	@echo "=====> Sorting and deduplicating subject vocabularies…"
	find $(SUBJECTS_DIR) -name '*.subjects.tsv' -print0 \
	  | xargs -0 -n 1 -P $$(nproc) \
	      sh -c 'echo "Sorting $$1…"; LC_ALL=C sort -u "$$1" -o "$$1"' _
	touch $@

# -----------------------
# 4. Load backbone into Jena
# -----------------------
$(JENA_DONE): $(PARTITION_DONE)
	mkdir -p $(JENA_DIR)
	tdb2.tdbloader --loc $(JENA_DIR) $(CONCEPT_BACKBONE)
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
	@echo "=====> Filtering out P31 instances from core concepts…"
	LC_ALL=C sort -m $(SUBJECTS_DIR)/*subjects.tsv \
	  | LC_ALL=C sort -u \
	  | join -v 1 $(CORE_CONCEPTS_QIDS) - \
	  | LC_ALL=C sort -u \
	  > $(CORE_NOSUBJECT_QIDS)
	touch $@

# -----------------------
# 7. Generate SKOS triples (batch pipeline)
# -----------------------

# --- 7a. skos:Concept typing
$(SKOS_CONCEPTS): $(FILTER_DONE)
	mkdir -p $(SKOS_DIR)
	$(call emit_skos_concepts,$(CORE_NOSUBJECT_QIDS)) > $@

# --- 7b. skos:Collection + members
$(SKOS_COLLECTION): $(FILTER_DONE)
	mkdir -p $(SKOS_DIR)
	$(call emit_skos_collection,$(COLLECTION_URI),$(CORE_NOSUBJECT_QIDS)) > $@

# --- 7c. English labels (join)
$(SKOS_LABELS): $(FILTER_DONE) $(SKOS_LABELS_GZ)
	mkdir -p $(SKOS_DIR)
	pigz -dc $(SKOS_LABELS_GZ) \
	  | join - $(CORE_NOSUBJECT_QIDS) \
	  > $@

# --- 7d. skos:broader from backbone
# FIXME: this will include QIDS from subjects
$(SKOS_BROADER): $(CONCEPT_BACKBONE)
	mkdir -p $(SKOS_DIR)
	sed -E 's|<[^>]+>|<$(SKOS_BROADER_URI)>|2' \
	  $< > $@

# --- 7e. Stamp (fan-in)
$(SKOS_DONE): $(SKOS_NT)
	touch $@

# -----------------------
# 8. Export Turtle
# -----------------------

$(FINAL_TTL): $(SKOS_NT)
	@echo "=====> Merging SKOS N-Triples and converting to Turtle…"
	cat $^ | riot --formatted=turtle --base='http://www.w3.org/2004/02/skos/core#' > $@

# -----------------------
# Clean
# -----------------------
clean:
	rm -rf $(WORK_DIR)

# -----------------------
# Subject-specific SKOS export
# Usage: make skos_subject SUBJECT=Q5
# -----------------------

SUBJECT          ?=
SUBJECT_FILE      = $(SUBJECTS_DIR)/$(SUBJECT)_subjects.tsv
SUBJECT_URI       = http://www.wikidata.org/entity/$(SUBJECT)
SUBJECT_COL_URI   = $(COLLECTION_URI)/subject/$(SUBJECT)
SUBJECT_OUT       = $(ROOT_DIR)/wikicore-$(RUN_DATE)-$(SUBJECT).ttl

.PHONY: skos_subject check_subject

skos_subject: check_subject $(SUBJECT_OUT)
	@echo "=====> → $(SUBJECT_OUT)"

check_subject:
	@if [ -z "$(SUBJECT)" ]; then \
	  echo "ERROR: SUBJECT=QID required (e.g. make skos_subject SUBJECT=Q5)"; \
	  exit 1; \
	fi
	@if [ ! -f "$(SUBJECT_FILE)" ]; then \
	  echo "ERROR: Subject file $(SUBJECT_FILE) does not exist"; \
	  exit 1; \
	fi

$(SUBJECT_OUT): $(SUBJECT_FILE) $(SKOS_LABELS)
	@echo "=====> Generating SKOS for subject $(SUBJECT)…"
	@mkdir -p $(ROOT_DIR)
	@{ \
	  $(call emit_skos_concepts,$(SUBJECT_FILE)); \
	  $(call emit_skos_collection,$(SUBJECT_COL_URI),$(SUBJECT_FILE)); \
	  grep -F "<$(SUBJECT_URI)>" $(SKOS_LABELS) || true; \
	} | riot --syntax=ntriples --output=turtle \
	         --base='http://www.wikidata.org/entity/' \
	> $@