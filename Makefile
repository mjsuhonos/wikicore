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
# Inputs
# -----------------------
PROP_DIRECT_GZ := $(SOURCE_DIR)/wikidata-20251229-propdirect.nt.gz
SKOS_LABELS_GZ := $(SOURCE_DIR)/wikidata-20251229-skos-labels-$(LOCALE).nt.gz
SITELINKS_FILE := $(SOURCE_DIR)/sitelinks_$(LOCALE)_qids.tsv

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
SKOS_CONCEPTS       := $(SKOS_DIR)/skos_concepts_core.nt
SKOS_CONCEPT_SCHEME := $(SKOS_DIR)/skos_concept_scheme_core.nt
SKOS_LABELS         := $(SKOS_DIR)/skos_labels_core_$(LOCALE).nt
SKOS_BROADER        := $(SKOS_DIR)/skos_broader_core.nt
SKOS_NT := $(SKOS_CONCEPTS) $(SKOS_CONCEPT_SCHEME) $(SKOS_LABELS) $(SKOS_BROADER)

# -----------------------
# RDF / SKOS URIs
# -----------------------
RDF_TYPE_URI        = http://www.w3.org/1999/02/22-rdf-syntax-ns\#type
SKOS_CORE_URI       = http://www.w3.org/2004/02/skos/core
SKOS_CONCEPT_URI    = http://www.w3.org/2004/02/skos/core\#Concept
SKOS_BROADER_URI    = http://www.w3.org/2004/02/skos/core\#broader
SKOS_CONCEPT_SCHEME_URI = http://www.w3.org/2004/02/skos/core\#ConceptScheme
SKOS_INSCHEME_URI     = http://www.w3.org/2004/02/skos/core\#inScheme

# -----------------------
# Macros
# -----------------------
define emit_skos_concepts
	sed -E 's|(.*)|\1 <$(RDF_TYPE_URI)> <$(SKOS_CONCEPT_URI)> .|' $(1)
endef

define emit_skos_concept_scheme
	echo "<$(strip $(1))> <$(RDF_TYPE_URI)> <$(SKOS_CONCEPT_SCHEME_URI)> ."
	sed -E 's|(.*)|\1 <$(SKOS_INSCHEME_URI)> <$(strip $(1))> .|' $(2)
endef

define join_skos_labels
	LC_ALL=C sort -u \
	  | LC_ALL=C join - $(1)
endef

define join_sitelinks
	LC_ALL=C join <(awk '{print $$1}' $(SITELINKS_FILE)) $(1) \
	  | LC_ALL=C sort -u
endef

# -----------------------
### Reusable SKOS bundle (concepts + scheme + labels)
### args:
###  1 = output prefix (full path, no suffix)
###  2 = input QID/TSV file
###  3 = scheme URI
# -----------------------

define skos_bundle
$(1)_concepts.nt: $(2) | $(SKOS_DIR)
	$(call emit_skos_concepts,$$<) > $$@

$(1)_concept_scheme.nt: $(2) | $(SKOS_DIR)
	$(call emit_skos_concept_scheme,$(3),$$<) > $$@

$(1)_labels.nt: $(2) $(SKOS_LABELS_GZ) | $(SKOS_DIR)
	pigz -dc $(SKOS_LABELS_GZ) \
	  | $(call join_skos_labels,$$<) \
	  > $$@
endef

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
	  parallel -j $(JOBS) --eta --halt now,fail=1 \
	    'python3 $(ROOT_DIR)/partition_chunks.py {} $(CLASS_NAMES_FILE) $(WORK_DIR) $(SUBJECTS_DIR)'

# -----------------------
# 3. Sort and deduplicate subject vocabularies
# -----------------------
SUBJECTS_SORTED := $(SUBJECTS_DIR)/subjects_sorted.tsv
SUBJECTS_DONE   := $(SUBJECTS_DIR)/.subjects_individually_sorted

$(SUBJECTS_DONE): $(CONCEPT_BACKBONE)
	parallel --bar --jobs $(JOBS) \
	  'LC_ALL=C sort -u -o {1} {1}' \
	  ::: $(SUBJECTS_DIR)/*subjects.tsv
	@touch $@

# =*=*=*=*=*=*=*=*=*=*=*=*
# NOTE: this includes ALL instance subjects INCLUDING p31_other.subjects.tsv
#
# to exclude p31_other.subjects.tsv, use "$(SUBJECTS_DIR)/Q*subjects.tsv"
# =*=*=*=*=*=*=*=*=*=*=*=*
$(SUBJECTS_SORTED): $(SUBJECTS_DONE)
	LC_ALL=C sort -m -u \
	  $(SUBJECTS_DIR)/*subjects.tsv > $@

# -----------------------
# 4. Load backbone into Jena
# -----------------------
$(JENA_DIR)/tdb2_loaded: $(CONCEPT_BACKBONE) | $(JENA_DIR)
	tdb2.tdbloader --loc $(JENA_DIR) $(CONCEPT_BACKBONE)
	touch $@

# -----------------------
# 5. Materialize + export core concepts
# -----------------------
$(CORE_CONCEPTS_QIDS): $(JENA_DIR)/tdb2_loaded
	tdb2.tdbupdate --loc $(JENA_DIR) --update="$(QUERIES_DIR)/materialize_graph.rq"
	tdb2.tdbquery --loc $(JENA_DIR) --query="$(QUERIES_DIR)/export.rq" --results=TSV \
	 | grep -F '<http://www.wikidata.org/entity/' \
	 | LC_ALL=C sort -u \
	 > $@

# -----------------------
# 6. Filter out P31 instances
#    Filter through Wikipedia sitelinks
# -----------------------
$(CORE_NOSUBJECT_QIDS): $(CORE_CONCEPTS_QIDS) $(SUBJECTS_SORTED)
	LC_ALL=C join -t '	' -1 1 -2 1 -v 1 $< $(SUBJECTS_SORTED) \
	  | $(call join_sitelinks,-) \
	  > $@

# -----------------------
# 7. Generate SKOS triples
# -----------------------

$(eval $(call skos_bundle,\
  $(SKOS_DIR)/skos,\
  $(CORE_NOSUBJECT_QIDS),\
  $(VOCAB_URI)))

$(FINAL_NT): \
	$(SKOS_DIR)/skos_concepts.nt \
	$(SKOS_DIR)/skos_concept_scheme.nt \
	$(SKOS_DIR)/skos_labels.nt
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

$(WORK_DIR)/%_filtered.tsv: $(SUBJECTS_DIR)/%_subjects.tsv
	$(call join_sitelinks,$<) > $@

$(foreach S,$(SUBJECTS),\
  $(eval $(call skos_bundle,\
    $(SKOS_DIR)/skos_$(S)_$(LOCALE),\
    $(WORK_DIR)/$(S)_filtered.tsv,\
    $(VOCAB_URI)/subject/$(S))))

.SECONDARY:

$(ROOT_DIR)/wikicore-$(RUN_DATE)-%-$(LOCALE).nt: \
	$(SKOS_DIR)/skos_%_$(LOCALE)_concepts.nt \
	$(SKOS_DIR)/skos_%_$(LOCALE)_concept_scheme.nt \
	$(SKOS_DIR)/skos_%_$(LOCALE)_labels.nt
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