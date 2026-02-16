# -----------------------
# Wiki Core processing pipeline
# -----------------------

SHELL := /bin/bash
.PHONY: all core subjects occ_subjects classes occupations skos_subjects skos_class skos_occupation turtle help

help:
	@echo "Wiki Core processing pipeline"
	@echo ""
	@echo "Usage: make <target> [OPTIONS]"
	@echo ""
	@echo "Targets:"
	@echo "  core                                Build the core SKOS vocab (wikicore-DATE-core-LOCALE.nt)"
	@echo "  subjects                            Build one .nt per QID across all classes/ TSVs"
	@echo "  occ_subjects                        Build one .nt per slug across all occupations/ TSVs"
	@echo "  classes                             Build one combined .nt per classes/ TSV"
	@echo "  occupations                         Build one combined .nt per occupations/ TSV"
	@echo "  all                                 Run core + subjects + occ_subjects + classes + occupations"
	@echo "  skos_subjects SUBJECTS='...'        Build SKOS for specific QIDs (eg. 'Q5 Q532')"
	@echo "  skos_occ_subjects SUBJECTS='...'    Build SKOS for specific occupation slugs (eg. 'electricalengineer_1376')"
	@echo "  skos_class CLASS_FILE=<path>        Build combined .nt for a single classes/ TSV"
	@echo "  skos_occupation OCC_FILE=<path>     Build combined .nt for a single occupations/ TSV (output prefixed occ-)"
	@echo "  turtle                              Convert all .nt files to compressed Turtle (.ttl.gz)"
	@echo "  clean                         Remove all working files"
	@echo ""
	@echo "Options:"
	@echo "  LOCALE=<lang>   Output language (default: en)"
	@echo "  JOBS=<n>        Parallel jobs (default: nproc)"
	@echo ""
	@echo "Examples:"
	@echo "  make core"
	@echo "  make skos_subjects SUBJECTS='Q5 Q532'"
	@echo "  make skos_class CLASS_FILE=classes/aircraft.tsv"
	@echo "  make skos_occ_subjects SUBJECTS='electricalengineer_1376 civilengineer_2907'"
	@echo "  make skos_occupation OCC_FILE=occupations/engineering.tsv"

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
FINAL_NT := $(ROOT_DIR)/wikicore-$(RUN_DATE)-core-$(LOCALE).nt

# All class TSV files and their derived targets
ALL_CLASS_FILES   := $(wildcard $(ROOT_DIR)/classes/*.tsv)
ALL_CLASS_NAMES   := $(basename $(notdir $(ALL_CLASS_FILES)))
ALL_CLASS_NTS     := $(foreach C,$(ALL_CLASS_NAMES),$(ROOT_DIR)/wikicore-$(RUN_DATE)-$(C)-$(LOCALE).nt)
ALL_SUBJECT_QIDS  := $(sort $(foreach F,$(ALL_CLASS_FILES),$(shell awk '{print $$1}' $(F))))
ALL_SUBJECT_NTS   := $(foreach Q,$(ALL_SUBJECT_QIDS),$(ROOT_DIR)/wikicore-$(RUN_DATE)-$(Q)-$(LOCALE).nt)

# All occupation TSV files and their derived targets
ALL_OCC_FILES          := $(wildcard $(ROOT_DIR)/occupations/*.tsv)
ALL_OCC_NAMES          := $(basename $(notdir $(ALL_OCC_FILES)))
ALL_OCC_NTS            := $(foreach O,$(ALL_OCC_NAMES),$(ROOT_DIR)/wikicore-$(RUN_DATE)-occ-$(O)-$(LOCALE).nt)
ALL_OCC_SUBJECT_SLUGS  := $(sort $(foreach F,$(ALL_OCC_FILES),$(shell awk '{print $$2}' $(F))))
ALL_OCC_SUBJECT_NTS    := $(foreach S,$(ALL_OCC_SUBJECT_SLUGS),$(ROOT_DIR)/wikicore-$(RUN_DATE)-$(S)-$(LOCALE).nt)

core: $(FINAL_NT)

subjects: $(ALL_SUBJECT_NTS)

occ_subjects: $(ALL_OCC_SUBJECT_NTS)

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
CHUNKS := $(wildcard $(SPLIT_DIR)/chunk_*)

$(SPLIT_DONE): $(CORE_PROPS_NT) | $(SPLIT_DIR)
	gsplit -n l/$(JOBS) $(CORE_PROPS_NT) $(SPLIT_DIR)/chunk_
	@touch $@

# Merge class and occupation names so partition_chunks routes occupation QIDs
# into their own per-QID subjects files (rather than P31_other)
$(OCC_NAMES_FILE): $(ALL_OCC_FILES) | $(WORK_DIR)
	cat $(ALL_OCC_FILES) > $@

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
	gsplit -n l/$(JOBS) $(SKOS_LABELS_NT) $(LABELS_SPLIT_DIR)/chunk_
	@touch $@

# -----------------------
# 7. Generate SKOS subject (instance) vocabs
# eg. make skos_subjects SUBJECTS="Q5 Q532"
# -----------------------

SUBJECTS ?= core

SUBJECT_OUTS := $(foreach S,$(SUBJECTS),\
  $(ROOT_DIR)/wikicore-$(RUN_DATE)-$(S)-$(LOCALE).nt)

skos_subjects: $(SUBJECT_OUTS)

# -----------------------
# 7b. Generate SKOS for individual occupation slugs
# eg. make skos_occ_subjects SUBJECTS="electricalengineer_1376 civilengineer_2907"
# -----------------------

OCC_SUBJECT_OUTS := $(foreach S,$(SUBJECTS),\
  $(ROOT_DIR)/wikicore-$(RUN_DATE)-$(S)-$(LOCALE).nt)

skos_occ_subjects: $(OCC_SUBJECT_OUTS)

.PRECIOUS: $(SKOS_DIR)/skos_%_concepts.nt \
           $(SKOS_DIR)/skos_%_concept_scheme.nt \
           $(SKOS_DIR)/skos_%_labels_$(LOCALE).nt \
           $(SKOS_DIR)/skos_%_broader.nt \
           $(CONCEPT_BACKBONE_SORTED)

$(SKOS_DIR)/skos_%_concepts.nt: $(SUBJECTS_DIR)/%_subjects.tsv | $(SKOS_DIR)
	awk -v type="$(RDF_TYPE_URI)" -v concept="$(SKOS_CONCEPT_URI)" \
	  '!seen[$$1]++ { print $$1, "<" type ">", "<" concept ">", "." }' $< > $@

$(SKOS_DIR)/skos_%_concept_scheme.nt: $(SUBJECTS_DIR)/%_subjects.tsv | $(SKOS_DIR)
	@echo "<$(VOCAB_URI)> <$(RDF_TYPE_URI)> <$(SKOS_CONCEPT_SCHEME_URI)> ." > $@
	awk -v inscheme="$(SKOS_INSCHEME_URI)" -v vocab="$(VOCAB_URI)" \
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
CLASS_QIDS   = $(if $(CLASS_FILE),$(shell awk '{print $$1}' $(CLASS_FILE)),)
CLASS_PARTS  = $(foreach Q,$(CLASS_QIDS),$(ROOT_DIR)/wikicore-$(RUN_DATE)-$(Q)-$(LOCALE).nt)
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
# 9. Per-occupation-slug NTs
# Each row of an occupations/ TSV is (QID, slug). The QID-named NT is built by
# the SKOS % rules above; the slug-named NT simply copies it.
# eg. wikicore-DATE-electricalengineer_1376-LOCALE.nt <- wikicore-DATE-Q1326886-LOCALE.nt
# -----------------------

# One rule per unique slug; collects all QIDs that map to that slug across all
# occupation TSVs (handles cases where multiple QIDs share the same slug).
define OCC_SUBJ_RULE
$(ROOT_DIR)/wikicore-$(RUN_DATE)-$(1)-$(LOCALE).nt: \
    $$(foreach Q,$$(shell awk '$$$$2 == "$(1)" {print $$$$1}' $(ALL_OCC_FILES)),\
      $(ROOT_DIR)/wikicore-$(RUN_DATE)-$$(Q)-$(LOCALE).nt)
	cat $$^ > $$@
	@echo "Generated $$@"
endef
$(foreach S,$(ALL_OCC_SUBJECT_SLUGS),$(eval $(call OCC_SUBJ_RULE,$(S))))

# -----------------------
# 10. Generate SKOS vocab from an occupations/ TSV
# eg. make skos_occupation OCC_FILE=occupations/engineering.tsv
# -----------------------

OCC_FILE   ?=
OCC_NAME    = $(basename $(notdir $(OCC_FILE)))
OCC_SLUGS   = $(if $(OCC_FILE),$(shell awk '{print $$2}' $(OCC_FILE)),)
OCC_PARTS   = $(foreach S,$(OCC_SLUGS),$(ROOT_DIR)/wikicore-$(RUN_DATE)-$(S)-$(LOCALE).nt)
OCC_NT      = $(ROOT_DIR)/wikicore-$(RUN_DATE)-occ-$(OCC_NAME)-$(LOCALE).nt

skos_occupation:
ifndef OCC_FILE
	$(error OCC_FILE is not set. Usage: make skos_occupation OCC_FILE=occupations/engineering.tsv)
endif
	$(MAKE) $(OCC_NT)

# Per-occupation combined NTs — one rule per occupations/*.tsv (used by skos_occupation and make occupations)
# Depends on slug-named individual NTs (col 2), not QIDs (col 1)
# Prefixed with "occ-" to avoid collision with same-named classes/ targets
define OCC_RULE
$(ROOT_DIR)/wikicore-$(RUN_DATE)-occ-$(1)-$(LOCALE).nt: \
    $$(foreach S,$$(shell awk '{print $$$$2}' $(ROOT_DIR)/occupations/$(1).tsv),\
      $(ROOT_DIR)/wikicore-$(RUN_DATE)-$$(S)-$(LOCALE).nt)
	cat $$^ > $$@
	@echo "Generated $$@"
endef
$(foreach O,$(ALL_OCC_NAMES),$(eval $(call OCC_RULE,$(O))))

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