# -----------------------
# Wikidata processing pipeline (Makefile)
# -----------------------

SHELL := /bin/bash
.PHONY: all clean skos_subject check_subject

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
JOBS ?= $(shell nproc)
RUN_DATE := $(shell date +%Y%m%d)
COLLECTION_URI := https://wikicore.ca/$(RUN_DATE)
export JENA_JAVA_OPTS="-Xmx32g -XX:ParallelGCThreads=$(JOBS)"

# -----------------------
# Inputs
# -----------------------
PROP_DIRECT_GZ := $(SOURCE_DIR)/wikidata-20251229-propdirect.nt.gz
SKOS_LABELS_GZ := $(SOURCE_DIR)/wikidata-20251229-skos-labels-en.nt.gz

# -----------------------
# Core files
# -----------------------
CORE_PROPS_NT := $(WORK_DIR)/wikidata-core-props-P31-P279-P361.nt
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
SKOS_NT := $(SKOS_CONCEPTS) $(SKOS_COLLECTION) $(SKOS_LABELS) $(SKOS_BROADER)

# -----------------------
# RDF / SKOS URIs
# -----------------------
RDF_TYPE_URI        = http://www.w3.org/1999/02/22-rdf-syntax-ns\#type
SKOS_CONCEPT_URI    = http://www.w3.org/2004/02/skos/core\#Concept
SKOS_COLLECTION_URI = http://www.w3.org/2004/02/skos/core\#Collection
SKOS_MEMBER_URI     = http://www.w3.org/2004/02/skos/core\#member
SKOS_BROADER_URI    = http://www.w3.org/2004/02/skos/core\#broader

# -----------------------
# SKOS macros
# -----------------------
define emit_skos_concepts
sed -E 's|(.*)|\1 <$(RDF_TYPE_URI)> <$(SKOS_CONCEPT_URI)> .|' $(1)
endef

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
$(CORE_PROPS_NT): $(PROP_DIRECT_GZ) | $(WORK_DIR)
	@echo "=====> Extracting core properties…"
	pigz -dc $< \
	  | rg -F -e '/prop/direct/P31>' -e '/prop/direct/P279>' -e '/prop/direct/P361>' \
	  | rg -F -v '_:' \
	  > $@

# -----------------------
# 2. Split + partition core properties
# -----------------------
SPLIT_DONE := $(SPLIT_DIR)/.split_done
CHUNKS := $(wildcard $(SPLIT_DIR)/chunk_*)

$(SPLIT_DONE): $(CORE_PROPS_NT) | $(SPLIT_DIR)
	@echo "=====> Splitting core properties into chunks…"
	gsplit -n l/$(JOBS) $(CORE_PROPS_NT) $(SPLIT_DIR)/chunk_
	@touch $@

$(CONCEPT_BACKBONE): $(SPLIT_DONE) | $(SUBJECTS_DIR)
	@echo "=====> Partitioning chunks and generating backbone…"
	ls $(SPLIT_DIR)/chunk_* | \
	  parallel -j $(JOBS) --eta --halt now,fail=1 \
	    'python3 $(ROOT_DIR)/partition_chunks.py {} $(CLASS_NAMES_FILE) $(WORK_DIR) $(SUBJECTS_DIR)'

# -----------------------
# 3. Sort and deduplicate subject vocabularies
# -----------------------
SUBJECTS_SORTED := $(SUBJECTS_DIR)/subjects_sorted.tsv
SUBJECTS_DONE   := $(SUBJECTS_DIR)/.subjects_individually_sorted

$(SUBJECTS_DONE): $(CONCEPT_BACKBONE)
	@echo "=====> Sorting and deduplicating individual subject files…"
	parallel --bar --jobs $(JOBS) \
	  'LC_ALL=C sort -u -o {1} {1}' \
	  ::: $(SUBJECTS_DIR)/*subjects.tsv
	@touch $@

# NB: this includes ALL instance subjects (including p31_other)
$(SUBJECTS_SORTED): $(SUBJECTS_DONE)
	@echo "=====> Merging all sorted subject files into $@ …"
	LC_ALL=C sort -m -u \
	  $(SUBJECTS_DIR)/Q*subjects.tsv > $@

# -----------------------
# 4. Load backbone into Jena
# -----------------------
$(JENA_DIR)/tdb2_loaded: $(CONCEPT_BACKBONE) | $(JENA_DIR)
	@echo "=====> Loading backbone into Jena…"
	tdb2.tdbloader --loc $(JENA_DIR) $(CONCEPT_BACKBONE)
	touch $@

# -----------------------
# 5. Materialize + export core concepts
# -----------------------
$(CORE_CONCEPTS_QIDS): $(JENA_DIR)/tdb2_loaded
	@echo "=====> Materializing core concepts…"
	tdb2.tdbupdate --loc $(JENA_DIR) --update="$(QUERIES_DIR)/materialize_graph.rq"
	tdb2.tdbquery --loc $(JENA_DIR) --query="$(QUERIES_DIR)/export.rq" --results=TSV \
	 | grep -F '<http://www.wikidata.org/entity/' \
	 | LC_ALL=C sort -u \
	 > $@

# -----------------------
# 6. Filter out P31 instances
# -----------------------
$(CORE_NOSUBJECT_QIDS): $(CORE_CONCEPTS_QIDS) $(SUBJECTS_SORTED)
	@echo "=====> Filtering out P31 instances…"
	LC_ALL=C join -t '	' -1 1 -2 1 -v 1 $< $(SUBJECTS_SORTED) \
	 | LC_ALL=C sort -u \
	 > $@

# TODO: filter through en_wikipedia sitelinks? (~250K -> 95K)

# -----------------------
# 7. Generate SKOS triples
# -----------------------
$(SKOS_DIR)/%.nt: $(CORE_NOSUBJECT_QIDS) | $(SKOS_DIR)

$(SKOS_CONCEPTS): $(CORE_NOSUBJECT_QIDS)
	$(call emit_skos_concepts,$(CORE_NOSUBJECT_QIDS)) > $@

$(SKOS_COLLECTION): $(CORE_NOSUBJECT_QIDS)
	$(call emit_skos_collection,$(COLLECTION_URI),$(CORE_NOSUBJECT_QIDS)) > $@

$(SKOS_LABELS): $(CORE_NOSUBJECT_QIDS) $(SKOS_LABELS_GZ)
	@echo "=====> Joining SKOS labels with core concepts…"
	pigz -dc $(SKOS_LABELS_GZ) \
	  | LC_ALL=C sort -u \
	  | LC_ALL=C join - $(CORE_NOSUBJECT_QIDS) \
	  > $@
	
# Filter out subject entities
$(SKOS_BROADER): $(CONCEPT_BACKBONE) $(CORE_NOSUBJECT_QIDS) | $(SKOS_DIR)
	@echo "=====> Filtering backbone triples and applying SKOS broader URI…"
	LC_ALL=C join $(CONCEPT_BACKBONE) $(CORE_NOSUBJECT_QIDS) \
	  | sed -E 's|<[^>]+>|<$(SKOS_BROADER_URI)>|2' \
	  > $@

# -----------------------
# 8. Export Turtle
# -----------------------
$(FINAL_TTL): $(SKOS_NT)
	@echo "=====> Merging SKOS N-Triples and converting to Turtle…"
	cat $^ | rapper -i ntriples -o turtle -I "http://www.w3.org/2004/02/skos/core" - \
	> $@

# TODO: generate fulltext corpus
# eg. gzcat wikidata5m_text.txt.gz \
#	| sort \
# convert first column to URIs
# filter through CORE_NOSUBJECT_QIDS (careful of encoding!)
# awk to swap places
#	| awk -F'\t' -v OFS='\t' '{print $2, "<http://www.wikidata.org/entity/" $1 ">"}'

# -----------------------
# Directories
# -----------------------
$(WORK_DIR) $(SPLIT_DIR) $(JENA_DIR) $(SUBJECTS_DIR) $(SKOS_DIR):
	mkdir -p $@

# -----------------------
# Clean
# -----------------------
clean:
	rm -rf $(WORK_DIR)

# -----------------------
# Subject-specific SKOS export
# -----------------------
SUBJECT ?=
SUBJECT_FILE = $(SUBJECTS_DIR)/$(SUBJECT)_subjects.tsv
SUBJECT_URI = http://www.wikidata.org/entity/$(SUBJECT)
SUBJECT_COL_URI = $(COLLECTION_URI)/subject/$(SUBJECT)
SUBJECT_OUT = $(ROOT_DIR)/wikicore-$(RUN_DATE)-$(SUBJECT).ttl

skos_subject: check_subject $(SUBJECT_OUT)

check_subject:
	@if [ -z "$(SUBJECT)" ]; then \
	  echo "ERROR: SUBJECT=QID required"; exit 1; \
	fi
	@if [ ! -f "$(SUBJECT_FILE)" ]; then \
	  echo "ERROR: Subject file $(SUBJECT_FILE) missing"; exit 1; \
	fi

$(SUBJECT_OUT): $(SUBJECT_FILE) $(SKOS_LABELS)
	@echo "=====> Generating SKOS for subject $(SUBJECT)…"
	@mkdir -p $(ROOT_DIR)
	@{ \
	  $(call emit_skos_concepts,$(SUBJECT_FILE)); \
	  $(call emit_skos_collection,$(SUBJECT_COL_URI),$(SUBJECT_FILE)); \
	  grep -F "<$(SUBJECT_URI)>" $(SKOS_LABELS) || true; \
	} | rapper -i ntriples -o turtle -I 'http://www.wikidata.org/entity/' - \
	> $@
