# -----------------------
# Wiki Core processing pipeline
# -----------------------

SHELL := /bin/bash
.PHONY: all clean skos_subjects

# -----------------------
# Options
# -----------------------
LOCALE ?= en
JOBS ?= $(shell nproc)
RUN_DATE := $(shell date +%Y%m%d)
VOCAB_URI := https://wikicore.ca/$(RUN_DATE)
export JENA_JAVA_OPTS="-Xmx32g -XX:ParallelGCThreads=$(JOBS)"

# -----------------------
# Paths
# -----------------------
ROOT_DIR         := $(PWD)
SOURCE_DIR       := $(ROOT_DIR)/source.nosync
WORK_DIR         := $(ROOT_DIR)/working.nosync
QUERIES_DIR      := $(ROOT_DIR)/queries
CLASS_NAMES_FILE := $(ROOT_DIR)/class_names.tsv

# -----------------------
# Inputs
# -----------------------
PROP_DIRECT_GZ   := $(SOURCE_DIR)/wikidata-20251229-propdirect.nt.gz
SKOS_LABELS_GZ   := $(SOURCE_DIR)/wikidata-20251229-skos-labels-$(LOCALE).nt.gz
# TODO: replace this with a WikiData JSON download file and use the jq command to parse it
SITELINKS_FILE   := $(SOURCE_DIR)/sitelinks_$(LOCALE)_qids.tsv

# WIP BUCKETS
BUCKETS          := $(wildcard ./buckets/*.tsv)

# -----------------------
# Working files
# -----------------------
JENA_DIR         := $(WORK_DIR)/jena
SKOS_DIR         := $(WORK_DIR)/skos
SPLIT_DIR        := $(WORK_DIR)/splits
SUBJECTS_DIR     := $(WORK_DIR)/subjects

# -----------------------
# Core files
# -----------------------
CORE_PROPS_NT       := $(WORK_DIR)/wikidata-core-props-P31-P279-P361.nt
CORE_CONCEPTS_QIDS  := $(WORK_DIR)/core_concepts_qids.tsv
CORE_NOSUBJECT_QIDS := $(WORK_DIR)/core_nosubject_qids.tsv
CONCEPT_BACKBONE    := $(WORK_DIR)/concept_backbone.nt
SKOS_LABELS_NT      := $(WORK_DIR)/wikidata-skos-labels-$(LOCALE).nt

# -----------------------
# SKOS outputs
# -----------------------
SKOS_CONCEPTS       := $(SKOS_DIR)/skos_concepts.nt
SKOS_CONCEPT_SCHEME := $(SKOS_DIR)/skos_concept_scheme.nt
SKOS_LABELS         := $(SKOS_DIR)/skos_labels_$(LOCALE).nt
SKOS_BROADER        := $(SKOS_DIR)/skos_broader.nt

# -----------------------
# RDF / SKOS URIs
# -----------------------
RDF_TYPE_URI        = http://www.w3.org/1999/02/22-rdf-syntax-ns\#type
SKOS_CORE_URI       = http://www.w3.org/2004/02/skos/core
SKOS_CONCEPT_URI    = http://www.w3.org/2004/02/skos/core\#Concept
SKOS_BROADER_URI    = http://www.w3.org/2004/02/skos/core\#broader
SKOS_CONCEPT_SCHEME_URI = http://www.w3.org/2004/02/skos/core\#ConceptScheme
SKOS_INSCHEME_URI     = http://www.w3.org/2004/02/skos/core\#inScheme

# ----------------------------------------------
#                MAIN STARTS HERE
# ----------------------------------------------

# -----------------------
# Default target
# -----------------------
FINAL_NT := $(ROOT_DIR)/wikicore-$(RUN_DATE)-$(LOCALE).nt

all: $(FINAL_NT)

# -----------------------
# Directories
# -----------------------
$(WORK_DIR) $(SPLIT_DIR) $(JENA_DIR) $(SUBJECTS_DIR) $(SKOS_DIR):
	mkdir -p $@

# -----------------------
# 1. Extract core properties
# -----------------------
$(CORE_PROPS_NT): $(PROP_DIRECT_GZ) | $(WORK_DIR)
	pigz -dc $(PROP_DIRECT_GZ) \
	  | rg -F -e '/prop/direct/P31>' -e '/prop/direct/P279>' -e '/prop/direct/P361>' \
	  | rg -F -v '_:' \
	  > $@

# -----------------------
# 2. Split + partition core properties
# -----------------------
SPLIT_DONE := $(SPLIT_DIR)/.split_done
CHUNKS := $(wildcard $(SPLIT_DIR)/chunk_*)

$(SPLIT_DONE): $(CORE_PROPS_NT) | $(SPLIT_DIR)
	gsplit -n l/$(JOBS) $(CORE_PROPS_NT) $(SPLIT_DIR)/chunk_
	@touch $@

$(CONCEPT_BACKBONE): $(SPLIT_DONE) | $(SUBJECTS_DIR)
	ls $(SPLIT_DIR)/chunk_* | \
	  parallel -j $(JOBS) --bar --halt now,fail=1 \
	    'for bucket_file in $(BUCKETS); do \
	         python3 $(ROOT_DIR)/partition_chunks.py {} $$bucket_file $(WORK_DIR) $(SUBJECTS_DIR); \
	     done'

# -----------------------
# 3. Load backbone into Jena
# -----------------------
$(JENA_DIR)/tdb2_loaded: $(CONCEPT_BACKBONE) | $(JENA_DIR)
	tdb2.tdbloader --loc $(JENA_DIR) $(CONCEPT_BACKBONE)
	touch $@

# -----------------------
# 4. Materialize + export core concepts
# -----------------------
$(CORE_CONCEPTS_QIDS): $(JENA_DIR)/tdb2_loaded
	tdb2.tdbupdate --loc $(JENA_DIR) --update="$(QUERIES_DIR)/materialize_ancestors.rq"
	tdb2.tdbupdate --loc $(JENA_DIR) --update="$(QUERIES_DIR)/materialize_child_counts.rq"
	tdb2.tdbquery  --loc $(JENA_DIR) --query="$(QUERIES_DIR)/export.rq" --results=TSV \
	  | grep -F '<http://www.wikidata.org/entity/' \
	  | LC_ALL=C sort -u \
	  > $@

# -----------------------
# 5. Prepare subject vocabularies
# -----------------------
SUBJECTS_SORTED := $(SUBJECTS_DIR)/subjects_sorted.tsv
SUBJECTS_DONE   := $(SUBJECTS_DIR)/.subjects_individually_sorted

# Sort and deduplicate each per-subject TSV
$(SUBJECTS_DONE): $(CONCEPT_BACKBONE)
	parallel -j $(JOBS) --bar --halt now,fail=1 'LC_ALL=C sort -u -o {1} {1}' ::: $(SUBJECTS_DIR)/*subjects.tsv
	@touch $@

# Claim per-subject TSVs as outputs of SUBJECTS_DONE
$(SUBJECTS_DIR)/%_subjects.tsv: $(SUBJECTS_DONE) ;

# Merge all per-subject files into a single sorted, deduplicated file
#
# NB: to exclude ALL instance subjects,  use "$(SUBJECTS_DIR)/*subjects.tsv"
#     to include p31_other.subjects.tsv, use "$(SUBJECTS_DIR)/Q*subjects.tsv"
$(SUBJECTS_SORTED): $(SUBJECTS_DONE)
	LC_ALL=C sort -m -u $(SUBJECTS_DIR)/*subjects.tsv > $@

$(CORE_NOSUBJECT_QIDS): $(CORE_CONCEPTS_QIDS) $(SUBJECTS_SORTED) $(SITELINKS_FILE) | $(WORK_DIR)
	LC_ALL=C join -v 1 $< $(SUBJECTS_SORTED) \
	  | LC_ALL=C join $(SITELINKS_FILE) - \
	  > $@

# -----------------------
# 6. Generate SKOS triples
# -----------------------

# Extract localized labels (for re-use)
$(SKOS_LABELS_NT): $(SKOS_LABELS_GZ) | $(WORK_DIR)
	pigz -dc $(SKOS_LABELS_GZ) > $@

# Join labels with core QIDs
$(SKOS_LABELS): $(SKOS_LABELS_NT) $(CORE_NOSUBJECT_QIDS) | $(SKOS_DIR)
	awk 'NR==FNR { core[$$1]; next } $$1 in core && !seen[$$0]++ { print }' \
	  $(CORE_NOSUBJECT_QIDS) $(SKOS_LABELS_NT) > $@

# Concept statements (one per core QID)
$(SKOS_CONCEPTS): $(CORE_NOSUBJECT_QIDS) | $(SKOS_DIR)
	awk -v type="$(RDF_TYPE_URI)" -v concept="$(SKOS_CONCEPT_URI)" \
	  '!seen[$$1]++ { print $$1, "<" type ">", "<" concept ">", "." }' $< > $@

# Concept Scheme aggregation
$(SKOS_CONCEPT_SCHEME): $(CORE_NOSUBJECT_QIDS) | $(SKOS_DIR)
	@echo "<$(VOCAB_URI)> <$(RDF_TYPE_URI)> <$(SKOS_CONCEPT_SCHEME_URI)> ." > $@
	awk -v inscheme="$(SKOS_INSCHEME_URI)" -v vocab="$(VOCAB_URI)" \
	  '!seen[$$1]++ { print $$1, "<" inscheme ">", "<" vocab ">", "." }' $< >> $@

# Broader statements
$(SKOS_BROADER): $(CORE_NOSUBJECT_QIDS) | $(SKOS_DIR)
	LC_ALL=C sort -u $(CONCEPT_BACKBONE) \
	  | LC_ALL=C join $(CORE_NOSUBJECT_QIDS) - \
	  | awk -v broader="$(SKOS_BROADER_URI)" '{ print $$1 " <" broader "> " $$3 " ." }' \
	  > $@

# -----------------------
# 7. Merge SKOS to output NT
# -----------------------
$(FINAL_NT): $(SKOS_CONCEPTS) $(SKOS_CONCEPT_SCHEME) $(SKOS_LABELS) $(SKOS_BROADER)
	cat $^ > $@

# -----------------------
# Clean
# -----------------------
clean:
	rm -rf $(WORK_DIR)

# -----------------------
# Generate SKOS subject (instance) vocabs
# -----------------------

SUBJECTS ?= Q5

SUBJECT_OUTS := $(foreach S,$(SUBJECTS),\
  $(ROOT_DIR)/wikicore-$(RUN_DATE)-$(S)-$(LOCALE).nt)

skos_subjects: $(SUBJECT_OUTS)

.PRECIOUS: $(SKOS_DIR)/skos_%_concepts.nt \
           $(SKOS_DIR)/skos_%_concept_scheme.nt \
           $(SKOS_DIR)/skos_%_labels_$(LOCALE).nt

$(WORK_DIR)/%_filtered.tsv: $(SUBJECTS_DIR)/%_subjects.tsv $(SITELINKS_FILE) | $(WORK_DIR)
	LC_ALL=C join $< $(SITELINKS_FILE) > $@

$(SKOS_DIR)/skos_%_concepts.nt: $(WORK_DIR)/%_filtered.tsv | $(SKOS_DIR)
	awk -v type="$(RDF_TYPE_URI)" -v concept="$(SKOS_CONCEPT_URI)" \
	  '!seen[$$1]++ { print $$1, "<" type ">", "<" concept ">", "." }' $< > $@

$(SKOS_DIR)/skos_%_concept_scheme.nt: $(WORK_DIR)/%_filtered.tsv | $(SKOS_DIR)
	@echo "<$(VOCAB_URI)> <$(RDF_TYPE_URI)> <$(SKOS_CONCEPT_SCHEME_URI)> ." > $@
	awk -v inscheme="$(SKOS_INSCHEME_URI)" -v vocab="$(VOCAB_URI)" \
	  '!seen[$$1]++ { print $$1, "<" inscheme ">", "<" vocab ">", "." }' $< >> $@

$(SKOS_DIR)/skos_%_labels_$(LOCALE).nt: \
	$(SKOS_LABELS_NT) $(WORK_DIR)/%_filtered.tsv | $(SKOS_DIR)
	awk 'NR==FNR { core[$$1]; next } $$1 in core && !seen[$$0]++ { print }' \
	  $(WORK_DIR)/$*_filtered.tsv $(SKOS_LABELS_NT) > $@

# TODO: skos:broader

$(ROOT_DIR)/wikicore-$(RUN_DATE)-%-$(LOCALE).nt: \
	$(SKOS_DIR)/skos_%_concepts.nt \
	$(SKOS_DIR)/skos_%_concept_scheme.nt \
	$(SKOS_DIR)/skos_%_labels_$(LOCALE).nt
	cat $^ > $@

# -----------------------
# TODO: generate fulltext corpus
# -----------------------
#
# eg. gzcat wikidata5m_text.txt.gz \
#	| sort \
# convert first column to URIs
# filter through CORE_NOSUBJECT_QIDS (careful of encoding!)
# awk to swap places
#	| awk -F'\t' -v OFS='\t' '{print $2, "<http://www.wikidata.org/entity/" $1 ">"}'


# join source.nosync/fulltext/wd5m_uri_first.tsv \
# working.nosync/Q16521_filtered.tsv \
# | sed -E 's/^<([^>]+)>[[:space:]]+(.*)$/\2\t<\1>/' \
# > source.nosync/fulltext/wd5m_wikicore-20260204-Q16521.tsv