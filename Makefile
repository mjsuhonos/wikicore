# -----------------------
# Wiki Core processing pipeline
# -----------------------

SHELL := /bin/bash
.SHELLFLAGS := -o pipefail -c
.PHONY: all core subjects occ_subjects classes occupations skos_subjects skos_class skos_occupation skos_by_occupation turtle clean distclean help

help:
	@echo "Wiki Core processing pipeline"
	@echo ""
	@echo "Usage: make <target> [OPTIONS]"
	@echo ""
	@echo "Targets:"
	@echo "  core                                Build the core SKOS vocab (wikicore-DATE-core-LOCALE.nt)"
	@echo "  subjects                            Build one .nt per QID across all classes/ TSVs (732 files)"
	@echo "  occ_subjects                        Build one .nt per occupation QID (1,451 files, SKOS about Q5 humans)"
	@echo "  classes                             Build one combined .nt per classes/ TSV (42 files)"
	@echo "  occupations                         Build one combined .nt per occupations/ TSV (19 files, SKOS about Q5 humans)"
	@echo "  all                                 Run core + subjects + occ_subjects + classes + occupations"
	@echo "  skos_subjects SUBJECTS='...'        Build SKOS for specific QIDs (eg. 'Q5 Q532')"
	@echo "  skos_class CLASS_FILE=<path>        Build combined .nt for a single classes/ TSV"
	@echo "  skos_occupation OCC_FILE=<path>     Build combined .nt for a single occupations/ TSV (output prefixed occ-)"
	@echo "  skos_by_occupation OBJECT=<QID>     Build SKOS for Q5 humans with a specific occupation QID"
	@echo "  turtle                              Convert all .nt files to compressed Turtle (.ttl.gz)"
	@echo "  clean                               Remove working files"
	@echo "  distclean                           Remove working files and all generated .nt/.ttl.gz"
	@echo ""
	@echo "Options:"
	@echo "  LOCALE=<lang>   Output language (default: en)"
	@echo "  JOBS=<n>        Parallel jobs (default: nproc)"
	@echo ""
	@echo "Examples:"
	@echo "  make core"
	@echo "  make subjects       # 732 class QID files"
	@echo "  make occ_subjects   # 1,451 occupation QID files"
	@echo "  make skos_subjects SUBJECTS='Q5 Q532'"
	@echo "  make skos_class CLASS_FILE=classes/aircraft.tsv"
	@echo "  make occupations    # 19 occupation group files"
	@echo "  make skos_occupation OCC_FILE=occupations/engineering.tsv"
	@echo "  make skos_by_occupation OBJECT=Q7888586    # Chemical engineers"

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
OCC_NAMES_FILE   := $(WORK_DIR)/occ_names.tsv
ALL_NAMES_FILE   := $(WORK_DIR)/all_names.tsv

# -----------------------
# Inputs
# -----------------------
PROP_DIRECT_GZ   := $(SOURCE_DIR)/wikidata-20251229-propdirect.nt.gz
SKOS_LABELS_GZ   := $(SOURCE_DIR)/wikidata-20251229-skos-labels-$(LOCALE).nt.gz
# TODO: replace this with a WikiData JSON download file and use the jq command to parse it
SITELINKS_FILE   := $(SOURCE_DIR)/sitelinks_$(LOCALE)_qids.tsv

# -----------------------
# Working files
# -----------------------
JENA_DIR              := $(WORK_DIR)/jena
SKOS_DIR              := $(WORK_DIR)/skos
SPLIT_DIR             := $(WORK_DIR)/splits
SUBJECTS_DIR          := $(WORK_DIR)/subjects
SUBJECTS_SORTED       := $(SUBJECTS_DIR)/subjects_sorted.tsv
SUBJECTS_DONE         := $(SUBJECTS_DIR)/.subjects_individually_sorted
LABELS_SPLIT_DIR      := $(WORK_DIR)/label_splits
LABELS_SPLIT_DONE     := $(LABELS_SPLIT_DIR)/.labels_split_done
CONCEPT_BACKBONE_SORTED := $(WORK_DIR)/concept_backbone_sorted.nt

# -----------------------
# Core files
# -----------------------
CONCEPT_BACKBONE    := $(WORK_DIR)/concept_backbone.nt
CORE_PROPS_NT       := $(WORK_DIR)/wikidata-core-props-P31-P279-P361.nt
SKOS_LABELS_NT      := $(WORK_DIR)/wikidata-skos-labels-$(LOCALE).nt
CORE_CONCEPTS_QIDS  := $(SUBJECTS_DIR)/core_subjects.tsv

# -----------------------
# P106 (occupation) files
# -----------------------
P106_NT             := $(WORK_DIR)/wikidata-P106-sitelinks.nt
Q5_SUBJECTS_FILE    := $(SUBJECTS_DIR)/Q5_subjects.tsv
Q5_OCC_GROUPED      := $(SUBJECTS_DIR)/.q5_occupation_grouped
OCC_QIDS_FILE       := $(WORK_DIR)/occ_qids.txt

# -----------------------
# RDF / SKOS URIs
# -----------------------
RDF_TYPE_URI        = http://www.w3.org/1999/02/22-rdf-syntax-ns\#type
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
FINAL_NT := $(ROOT_DIR)/wikicore-$(RUN_DATE)-core-$(LOCALE).nt

# All class TSV files and their derived targets
ALL_CLASS_FILES   := $(wildcard $(ROOT_DIR)/classes/*.tsv)
ALL_CLASS_NAMES   := $(basename $(notdir $(ALL_CLASS_FILES)))
ALL_CLASS_NTS     := $(foreach C,$(ALL_CLASS_NAMES),$(ROOT_DIR)/wikicore-$(RUN_DATE)-$(C)-$(LOCALE).nt)
ALL_SUBJECT_QIDS  := $(sort $(foreach F,$(ALL_CLASS_FILES),$(shell awk '{print $$1}' $(F))))
ALL_SUBJECT_NTS   := $(foreach Q,$(ALL_SUBJECT_QIDS),$(ROOT_DIR)/wikicore-$(RUN_DATE)-$(Q)-$(LOCALE).nt)

# All occupation TSV files and their derived targets
# Occupations now generate SKOS about Q5 (humans) who have those occupations
ALL_OCC_FILES          := $(wildcard $(ROOT_DIR)/occupations/*.tsv)
ALL_OCC_NAMES          := $(basename $(notdir $(ALL_OCC_FILES)))
ALL_OCC_NTS            := $(foreach O,$(ALL_OCC_NAMES),$(ROOT_DIR)/wikicore-$(RUN_DATE)-occ-$(O)-$(LOCALE).nt)

# Individual occupation QID files (one per occupation QID)
ALL_OCC_QIDS           := $(sort $(foreach F,$(ALL_OCC_FILES),$(shell awk '{print $$1}' $(F))))
ALL_OCC_QID_NTS        := $(foreach Q,$(ALL_OCC_QIDS),$(ROOT_DIR)/wikicore-$(RUN_DATE)-$(Q)-$(LOCALE).nt)

core: $(FINAL_NT)

subjects: $(ALL_SUBJECT_NTS)

occ_subjects: $(ALL_OCC_QID_NTS)

classes: $(ALL_CLASS_NTS)

occupations: $(ALL_OCC_NTS)

all: core subjects occ_subjects classes occupations

# -----------------------
# Directories
# -----------------------
$(WORK_DIR) $(SPLIT_DIR) $(JENA_DIR) $(SUBJECTS_DIR) $(SKOS_DIR) $(LABELS_SPLIT_DIR):
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

$(SPLIT_DONE): $(CORE_PROPS_NT) | $(SPLIT_DIR)
	split -n l/$(JOBS) $(CORE_PROPS_NT) $(SPLIT_DIR)/chunk_
	@touch $@

# Merge class and occupation names so partition_chunks routes occupation QIDs
# into their own per-QID subjects files (rather than P31_other)
$(OCC_NAMES_FILE): $(ALL_OCC_FILES) | $(WORK_DIR)
	cat $(ALL_OCC_FILES) > $@

# Create list of occupation QIDs for concept_scheme rule
$(OCC_QIDS_FILE): $(ALL_OCC_FILES) | $(WORK_DIR)
	cat $(ALL_OCC_FILES) | awk '{print $$1}' | sort -u > $@

$(ALL_NAMES_FILE): $(CLASS_NAMES_FILE) $(OCC_NAMES_FILE)
	cat $^ > $@

$(CONCEPT_BACKBONE): $(SPLIT_DONE) $(ALL_NAMES_FILE) | $(SUBJECTS_DIR)
	ls $(SPLIT_DIR)/chunk_* | \
	  parallel -j $(JOBS) --bar --halt now,fail=1 \
	    'python3 $(ROOT_DIR)/partition_chunks.py {} $(ALL_NAMES_FILE) $(WORK_DIR) $(SUBJECTS_DIR)'

# -----------------------
# 3. Prepare subject vocabularies
# -----------------------

# Sort, deduplicate, and pre-filter each per-subject TSV against sitelinks
$(SUBJECTS_DONE): $(CONCEPT_BACKBONE) $(SITELINKS_FILE)
	parallel -j $(JOBS) --bar --halt now,fail=1 \
	  'tmp=$$(mktemp); LC_ALL=C sort -u {1} | LC_ALL=C join -o 2.1 $(SITELINKS_FILE) - > "$$tmp" && mv "$$tmp" {1}' \
	  ::: $(SUBJECTS_DIR)/*subjects.tsv
	@touch $@

# Claim per-subject TSVs as outputs of SUBJECTS_DONE
$(SUBJECTS_DIR)/%_subjects.tsv: $(SUBJECTS_DONE) ;

# Merge all pre-filtered per-subject files into a single sorted, deduplicated file
#
# NB: to exclude ALL instance subjects,  use "$(SUBJECTS_DIR)/*subjects.tsv"
#     to include p31_other.subjects.tsv, use "$(SUBJECTS_DIR)/Q*subjects.tsv"
$(SUBJECTS_SORTED): $(SUBJECTS_DONE)
	LC_ALL=C sort -m -u $(SUBJECTS_DIR)/*subjects.tsv \
	 > $@

# -----------------------
# 3b. Extract P106 (occupation) and group Q5 humans by occupation
# -----------------------

# Extract all P106 triples from property-direct dump
$(P106_NT): $(PROP_DIRECT_GZ) | $(WORK_DIR)
	pigz -dc $(PROP_DIRECT_GZ) \
	  | rg -F '/prop/direct/P106>' \
	  | rg -F -v '_:' \
	  > $@

# Extract Q5 (human) subjects - filter for instance of Q5
$(Q5_SUBJECTS_FILE): $(PROP_DIRECT_GZ) $(SITELINKS_FILE) | $(SUBJECTS_DIR)
	pigz -dc $(PROP_DIRECT_GZ) \
	  | rg -F '/prop/direct/P31> <http://www.wikidata.org/entity/Q5>' \
	  | awk '{print $$1}' \
	  | LC_ALL=C sort -u \
	  | LC_ALL=C join -o 2.1 $(SITELINKS_FILE) - \
	  > $@

# Group Q5 subjects by occupation into Q5_{occupation}_subjects.tsv files
$(Q5_OCC_GROUPED): $(P106_NT) $(Q5_SUBJECTS_FILE) $(ALL_OCC_FILES) | $(SUBJECTS_DIR)
	python3 $(ROOT_DIR)/python/group_q5_by_occupation.py
	@touch $@

# Generate individual occupation QID subject files (Q7888586_subjects.tsv)
# Pattern rule: for each occupation QID, extract Q5 subjects with P106=that QID
define OCC_QID_SUBJECTS_RULE
$(SUBJECTS_DIR)/$(1)_subjects.tsv: $(P106_NT) $(Q5_SUBJECTS_FILE) | $(SUBJECTS_DIR)
	@echo "Extracting Q5 subjects with P106=$(1)"
	@grep -F '<http://www.wikidata.org/entity/$(1)>' $(P106_NT) \
	  | awk '{print $$$$1}' \
	  | LC_ALL=C sort -u \
	  | LC_ALL=C join - $(Q5_SUBJECTS_FILE) \
	  > $$@
	@echo "Found $$$$(wc -l < $$@) Q5 subjects with P106=$(1)"
endef
$(foreach Q,$(ALL_OCC_QIDS),$(eval $(call OCC_QID_SUBJECTS_RULE,$(Q))))

# -----------------------
# 4. Load backbone into Jena
# -----------------------
$(JENA_DIR)/tdb2_loaded: $(CONCEPT_BACKBONE) | $(JENA_DIR)
	tdb2.tdbloader --loc $(JENA_DIR) $(CONCEPT_BACKBONE)
	touch $@

# -----------------------
# 5. Materialize + export core concepts
# -----------------------
$(CORE_CONCEPTS_QIDS): $(JENA_DIR)/tdb2_loaded $(SUBJECTS_SORTED) $(SITELINKS_FILE)
	tdb2.tdbupdate --loc $(JENA_DIR) --update="$(QUERIES_DIR)/materialize_ancestors.rq"
	tdb2.tdbupdate --loc $(JENA_DIR) --update="$(QUERIES_DIR)/materialize_child_counts.rq"
	tdb2.tdbquery  --loc $(JENA_DIR) --query="$(QUERIES_DIR)/export.rq" --results=TSV \
	  | grep -F '<http://www.wikidata.org/entity/' \
	  | LC_ALL=C sort -u \
	  | LC_ALL=C join -v 1 - $(SUBJECTS_SORTED) \
	  | LC_ALL=C join -o 2.1 - $(SITELINKS_FILE) \
	  > $@

# -----------------------
# 6. Extract and split localized labels
# -----------------------
$(SKOS_LABELS_NT): $(SKOS_LABELS_GZ) | $(WORK_DIR)
	pigz -dc $(SKOS_LABELS_GZ) > $@

$(LABELS_SPLIT_DONE): $(SKOS_LABELS_NT) | $(LABELS_SPLIT_DIR)
	split -n l/$(JOBS) $(SKOS_LABELS_NT) $(LABELS_SPLIT_DIR)/chunk_
	@touch $@

# -----------------------
# 7. Generate SKOS subject (instance) vocabs
# eg. make skos_subjects SUBJECTS="Q5 Q532"
# -----------------------

SUBJECTS ?= core

SUBJECT_OUTS := $(foreach S,$(SUBJECTS),\
  $(ROOT_DIR)/wikicore-$(RUN_DATE)-$(S)-$(LOCALE).nt)

skos_subjects: $(SUBJECT_OUTS)

.PRECIOUS: $(SKOS_DIR)/skos_%_concepts.nt \
           $(SKOS_DIR)/skos_%_concept_scheme.nt \
           $(SKOS_DIR)/skos_%_labels_$(LOCALE).nt \
           $(SKOS_DIR)/skos_%_broader.nt \
           $(CONCEPT_BACKBONE_SORTED)

$(SKOS_DIR)/skos_%_concepts.nt: $(SUBJECTS_DIR)/%_subjects.tsv | $(SKOS_DIR)
	awk -v type="$(RDF_TYPE_URI)" -v concept="$(SKOS_CONCEPT_URI)" \
	  '!seen[$$1]++ { print $$1, "<" type ">", "<" concept ">", "." }' $< > $@

$(SKOS_DIR)/skos_%_concept_scheme.nt: $(SUBJECTS_DIR)/%_subjects.tsv $(OCC_QIDS_FILE) | $(SKOS_DIR)
	@id='$*'; \
	if [ "$$id" = "core" ]; then \
		vocab_uri="$(VOCAB_URI)/core"; \
	elif echo "$$id" | grep -qE '^Q5_'; then \
		category=$$(echo "$$id" | sed 's/^Q5_//'); \
		vocab_uri="$(VOCAB_URI)/occupations/$$category"; \
	elif echo "$$id" | grep -qE '^P106-Q'; then \
		occ_qid=$$(echo "$$id" | sed 's/^P106-//'); \
		vocab_uri="$(VOCAB_URI)/occupations/$$occ_qid"; \
	elif echo "$$id" | grep -qE '^Q[0-9]+$$' && grep -qF "$$id" $(OCC_QIDS_FILE); then \
		vocab_uri="$(VOCAB_URI)/occupations/$$id"; \
	elif echo "$$id" | grep -qE '^Q[0-9]+$$'; then \
		vocab_uri="$(VOCAB_URI)/subjects/$$id"; \
	elif [ "$$id" = "P31_other" ]; then \
		vocab_uri="$(VOCAB_URI)/subjects/other"; \
	else \
		vocab_uri="$(VOCAB_URI)/subjects/$$id"; \
	fi; \
	echo "<$$vocab_uri> <$(RDF_TYPE_URI)> <$(SKOS_CONCEPT_SCHEME_URI)> ." > $@; \
	awk -v inscheme="$(SKOS_INSCHEME_URI)" -v vocab="$$vocab_uri" \
	  '!seen[$$1]++ { print $$1, "<" inscheme ">", "<" vocab ">", "." }' $< >> $@

$(SKOS_DIR)/skos_%_labels_$(LOCALE).nt: \
	$(LABELS_SPLIT_DONE) $(SUBJECTS_DIR)/%_subjects.tsv | $(SKOS_DIR)
	parallel -j $(JOBS) --bar --halt now,fail=1 \
	  'awk '\''NR==FNR { core[$$1]; next } $$1 in core && !seen[$$0]++ { print }'\'' \
	    $(SUBJECTS_DIR)/$*_subjects.tsv {}' \
	  ::: $(LABELS_SPLIT_DIR)/chunk_* \
	  | LC_ALL=C sort -u > $@

$(CONCEPT_BACKBONE_SORTED): $(CONCEPT_BACKBONE)
	LC_ALL=C sort -u $< > $@

$(SKOS_DIR)/skos_%_broader.nt: $(SUBJECTS_DIR)/%_subjects.tsv $(CONCEPT_BACKBONE_SORTED) | $(SKOS_DIR)
	LC_ALL=C join $(SUBJECTS_DIR)/$*_subjects.tsv $(CONCEPT_BACKBONE_SORTED) \
	  | awk -v broader="$(SKOS_BROADER_URI)" '{ print $$1 " <" broader "> " $$3 " ." }' \
	  > $@

$(ROOT_DIR)/wikicore-$(RUN_DATE)-%-$(LOCALE).nt: \
	$(SKOS_DIR)/skos_%_concepts.nt \
	$(SKOS_DIR)/skos_%_concept_scheme.nt \
	$(SKOS_DIR)/skos_%_labels_$(LOCALE).nt \
	$(SKOS_DIR)/skos_%_broader.nt
	cat $^ > $@

# -----------------------
# 8. Generate SKOS vocab from a classes/ TSV
# eg. make skos_class CLASS_FILE=classes/aircraft.tsv
# -----------------------

CLASS_FILE  ?=
CLASS_NAME   = $(basename $(notdir $(CLASS_FILE)))
CLASS_NT     = $(ROOT_DIR)/wikicore-$(RUN_DATE)-$(CLASS_NAME)-$(LOCALE).nt

skos_class:
ifndef CLASS_FILE
	$(error CLASS_FILE is not set. Usage: make skos_class CLASS_FILE=classes/aircraft.tsv)
endif
	$(MAKE) $(CLASS_NT)

# Per-class combined NTs — one rule per classes/*.tsv (used by skos_class and make classes)
define CLASS_RULE
$(ROOT_DIR)/wikicore-$(RUN_DATE)-$(1)-$(LOCALE).nt: \
    $$(foreach Q,$$(shell awk '{print $$$$1}' $(ROOT_DIR)/classes/$(1).tsv),\
      $(ROOT_DIR)/wikicore-$(RUN_DATE)-$$(Q)-$(LOCALE).nt)
	cat $$^ > $$@
	@echo "Generated $$@"
endef
$(foreach C,$(ALL_CLASS_NAMES),$(eval $(call CLASS_RULE,$(C))))

# -----------------------
# 9. Generate SKOS vocabs from occupations/ TSVs
# Each occupation generates SKOS about Q5 (human) entities that have that occupation
# eg. make skos_occupation OCC_FILE=occupations/engineering.tsv
# -----------------------

OCC_FILE   ?=
OCC_NAME    = $(basename $(notdir $(OCC_FILE)))
OCC_NT      = $(ROOT_DIR)/wikicore-$(RUN_DATE)-occ-$(OCC_NAME)-$(LOCALE).nt

skos_occupation:
ifndef OCC_FILE
	$(error OCC_FILE is not set. Usage: make skos_occupation OCC_FILE=occupations/engineering.tsv)
endif
	$(MAKE) $(OCC_NT)

# Per-occupation combined NTs — one rule per occupations/*.tsv
# Generates SKOS from Q5_{occupation}_subjects.tsv files created by group_q5_by_occupation.py
# Prefixed with "occ-" to avoid collision with same-named classes/ targets
define OCC_RULE
$(ROOT_DIR)/wikicore-$(RUN_DATE)-occ-$(1)-$(LOCALE).nt: \
    $(Q5_OCC_GROUPED) \
    $(SKOS_DIR)/skos_Q5_$(1)_concepts.nt \
    $(SKOS_DIR)/skos_Q5_$(1)_concept_scheme.nt \
    $(SKOS_DIR)/skos_Q5_$(1)_labels_$(LOCALE).nt \
    $(SKOS_DIR)/skos_Q5_$(1)_broader.nt
	cat $(SKOS_DIR)/skos_Q5_$(1)_concepts.nt \
	    $(SKOS_DIR)/skos_Q5_$(1)_concept_scheme.nt \
	    $(SKOS_DIR)/skos_Q5_$(1)_labels_$(LOCALE).nt \
	    $(SKOS_DIR)/skos_Q5_$(1)_broader.nt \
	    > $$@
	@echo "Generated $$@"
endef
$(foreach O,$(ALL_OCC_NAMES),$(eval $(call OCC_RULE,$(O))))

# -----------------------
# 10. Generate SKOS for Q5 humans by occupation QID
# eg. make skos_by_occupation OBJECT=Q7888586
# -----------------------

OBJECT ?=
OBJECT_NT = $(ROOT_DIR)/wikicore-$(RUN_DATE)-P106-$(OBJECT)-$(LOCALE).nt

skos_by_occupation:
ifndef OBJECT
	$(error OBJECT is not set. Usage: make skos_by_occupation OBJECT=Q7888586)
endif
	@echo "Generating SKOS for Q5 humans with P106=$(OBJECT)"
	$(MAKE) $(OBJECT_NT)

# Extract Q5 subjects that have P106 = OBJECT
$(SUBJECTS_DIR)/P106-$(OBJECT)_subjects.tsv: $(P106_NT) $(Q5_SUBJECTS_FILE) | $(SUBJECTS_DIR)
	@echo "Extracting Q5 subjects with P106=$(OBJECT)"
	@grep -F '<http://www.wikidata.org/entity/$(OBJECT)>' $(P106_NT) \
	  | awk '{print $$1}' \
	  | LC_ALL=C sort -u \
	  | LC_ALL=C join - $(Q5_SUBJECTS_FILE) \
	  > $@
	@echo "Found $$(wc -l < $@) Q5 subjects with P106=$(OBJECT)"

# Generate SKOS from P106-{OBJECT}_subjects.tsv using standard pattern rules
$(ROOT_DIR)/wikicore-$(RUN_DATE)-P106-%-$(LOCALE).nt: \
    $(SUBJECTS_DIR)/P106-%_subjects.tsv \
    $(SKOS_DIR)/skos_P106-%_concepts.nt \
    $(SKOS_DIR)/skos_P106-%_concept_scheme.nt \
    $(SKOS_DIR)/skos_P106-%_labels_$(LOCALE).nt \
    $(SKOS_DIR)/skos_P106-%_broader.nt
	cat $(SKOS_DIR)/skos_P106-$*_concepts.nt \
	    $(SKOS_DIR)/skos_P106-$*_concept_scheme.nt \
	    $(SKOS_DIR)/skos_P106-$*_labels_$(LOCALE).nt \
	    $(SKOS_DIR)/skos_P106-$*_broader.nt \
	    > $@
	@echo "Generated $@"

# -----------------------
# Convert .nt files to compressed Turtle
# -----------------------
EXISTING_NTS := $(wildcard $(ROOT_DIR)/wikicore-*.nt)
TURTLE_GZS   := $(EXISTING_NTS:.nt=.ttl.gz)

RIOT_PREFIXES := \
  --prefix skos=http://www.w3.org/2004/02/skos/core# \
  --prefix rdf=http://www.w3.org/1999/02/22-rdf-syntax-ns# \
  --prefix rdfs=http://www.w3.org/2000/01/rdf-schema# \
  --prefix owl=http://www.w3.org/2002/07/owl# \
  --prefix xsd=http://www.w3.org/2001/XMLSchema# \
  --prefix wd=http://www.wikidata.org/entity/ \
  --prefix wikicore=https://wikicore.ca/

PIGZ_JOBS := $(shell echo $$(( $(JOBS) > 4 ? 4 : $(JOBS) )))

%.ttl.gz: %.nt
	riot --output=turtle $(RIOT_PREFIXES) $< | pigz -p $(PIGZ_JOBS) > $@
	@echo "Generated $@"

turtle: $(TURTLE_GZS)

# -----------------------
# Clean
# -----------------------
clean:
	rm -rf $(WORK_DIR)

distclean: clean
	rm -f $(ROOT_DIR)/wikicore-*.nt $(ROOT_DIR)/wikicore-*.ttl.gz

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
# working.nosync/Q16521_subjects.tsv \
# | sed -E 's/^<([^>]+)>[[:space:]]+(.*)$/\2\t<\1>/' \
# > source.nosync/fulltext/wd5m_wikicore-20260204-Q16521.tsv