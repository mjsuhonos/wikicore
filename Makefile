# -----------------------
# Wiki Core processing pipeline
# -----------------------

SHELL := /bin/bash
.SHELLFLAGS := -o pipefail -c
.PHONY: all skos fulltext \
        core skos_class_qids skos_class_groups skos_occ_qids skos_occ_groups \
        skos_class_qid skos_class_group skos_occ_qid skos_occ_group skos_occ_unmatched \
        turtle clean distclean help \
        fulltext_class_qids fulltext_class_groups fulltext_class_qid fulltext_class_group \
        fulltext_occ_groups fulltext_occ_group fulltext_occ_unmatched

help:
	@echo "Wiki Core processing pipeline"
	@echo ""
	@echo "Usage: make <target> [OPTIONS]"
	@echo ""
	@echo "Aggregate targets:"
	@echo "  all                                   Build everything: skos + fulltext"
	@echo "  skos                                  Build all SKOS .nt files (core + class_qids/groups + occ_qids/groups)"
	@echo "  fulltext                              Build all fulltext TSVs (require source.nosync/wikidata5m_text.txt.gz)"
	@echo ""
	@echo "SKOS targets:"
	@echo "  core                                  Build the core SKOS vocab (wikicore-DATE-core-LOCALE.nt)"
	@echo "  skos_class_qids                       Build one .nt per class QID across all classes/ TSVs (732 files)"
	@echo "  skos_class_groups                     Build one combined .nt per classes/ TSV (42 files)"
	@echo "  skos_occ_qids                         Build one .nt per occupation QID (1,451 files, SKOS about Q5 humans)"
	@echo "  skos_occ_groups                       Build one combined .nt per occupations/ TSV (19 files, SKOS about Q5 humans)"
	@echo "  skos_class_qid QIDS='...'             Build SKOS for specific class QIDs (eg. 'Q5 Q532')"
	@echo "  skos_class_group CLASS_FILE=<path>    Build combined .nt for a single classes/ TSV"
	@echo "  skos_occ_qid QID=<QID>                Build SKOS for Q5 humans with a specific occupation QID"
	@echo "  skos_occ_group OCC_FILE=<path>        Build combined .nt for a single occupations/ TSV"
	@echo "  skos_occ_unmatched                    Build SKOS for Q5 humans with no matched occupation"
	@echo "  turtle                                Convert all .nt files to compressed Turtle (.ttl.gz)"
	@echo ""
	@echo "Fulltext targets:"
	@echo "  fulltext_class_qids                   Build one fulltext TSV per class QID"
	@echo "  fulltext_class_groups                 Build one combined fulltext TSV per classes/ TSV"
	@echo "  fulltext_occ_groups                   Build one combined fulltext TSV per occupations/ TSV (people)"
	@echo "  fulltext_class_qid QIDS='...'         Build fulltext TSVs for specific class QIDs (eg. 'Q5 Q532')"
	@echo "  fulltext_class_group CLASS_FILE=<path> Build combined fulltext TSV for a single classes/ TSV"
	@echo "  fulltext_occ_group OCC_FILE=<path>    Build combined fulltext TSV for a single occupations/ TSV"
	@echo "  fulltext_occ_unmatched                Build fulltext TSV for Q5 humans with no matched occupation"
	@echo ""
	@echo "Utility targets:"
	@echo "  clean                                 Remove working files"
	@echo "  distclean                             Remove working files and all generated .nt/.ttl.gz"
	@echo ""
	@echo "Options:"
	@echo "  LOCALE=<lang>   Output language (default: en)"
	@echo "  JOBS=<n>        Parallel jobs (default: nproc)"
	@echo ""

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

# Output directories (dated release layout)
OUT_DIR          := $(ROOT_DIR)/wikicore-$(RUN_DATE)
CLASS_QIDS_DIR   := $(OUT_DIR)/classes
CLASS_GROUPS_DIR := $(OUT_DIR)/classes/groups
OCC_QIDS_DIR     := $(OUT_DIR)/occupations
OCC_GROUPS_DIR   := $(OUT_DIR)/occupations/groups

# Fulltext output directories (under ./fulltext/, mirroring the NT layout)
FULLTEXT_DIR              := $(ROOT_DIR)/fulltext
FULLTEXT_CLASS_QIDS_DIR   := $(FULLTEXT_DIR)/classes/qids
FULLTEXT_CLASS_GROUPS_DIR := $(FULLTEXT_DIR)/classes
FULLTEXT_OCC_GROUPS_DIR   := $(FULLTEXT_DIR)/occupations

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

# Fulltext working files
FULLTEXT_GZ                := $(SOURCE_DIR)/wikidata5m_text.txt.gz
FULLTEXT_CLASS_QIDS_FILE   := $(WORK_DIR)/fulltext_class_qids.txt
FULLTEXT_CLASS_INSTANCE_MAP := $(WORK_DIR)/fulltext_class_instance_map.tsv
FULLTEXT_CLASS_SPLIT_DONE  := $(WORK_DIR)/.fulltext_class_split_done
FULLTEXT_OCC_GROUP_MAP     := $(WORK_DIR)/fulltext_occ_group_map.tsv
FULLTEXT_OCC_GROUPS_DONE   := $(WORK_DIR)/.fulltext_occ_groups_done

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
P106_NT              := $(WORK_DIR)/wikidata-P106-sitelinks.nt
Q5_SUBJECTS_FILE     := $(SUBJECTS_DIR)/Q5_subjects.tsv
Q5_OCC_GROUPED       := $(SUBJECTS_DIR)/.q5_occupation_grouped
OCC_QIDS_FILE        := $(WORK_DIR)/occ_qids.txt
ACTIVE_OCC_QIDS_FILE := $(WORK_DIR)/active_occ_qids.txt

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
FINAL_NT := $(OUT_DIR)/wikicore-$(RUN_DATE)-core-$(LOCALE).nt

# All class TSV files and their derived targets
ALL_CLASS_FILES      := $(wildcard $(ROOT_DIR)/classes/*.tsv)
ALL_CLASS_NAMES      := $(basename $(notdir $(ALL_CLASS_FILES)))
ALL_CLASS_GROUP_NTS  := $(foreach C,$(ALL_CLASS_NAMES),$(CLASS_GROUPS_DIR)/wikicore-$(RUN_DATE)-$(C)-$(LOCALE).nt)
ALL_CLASS_QIDS       := $(sort $(foreach F,$(ALL_CLASS_FILES),$(shell awk '{print $$1}' $(F))))
ALL_CLASS_QIDS_NTS   := $(foreach Q,$(ALL_CLASS_QIDS),$(CLASS_QIDS_DIR)/wikicore-$(RUN_DATE)-$(Q)-$(LOCALE).nt)

# All occupation TSV files and their derived targets
# Occupations generate SKOS about Q5 (humans) who have those occupations
ALL_OCC_FILES        := $(wildcard $(ROOT_DIR)/occupations/*.tsv)
ALL_OCC_NAMES        := $(basename $(notdir $(ALL_OCC_FILES)))
ALL_OCC_GROUP_NTS    := $(foreach O,$(ALL_OCC_NAMES),$(OCC_GROUPS_DIR)/wikicore-$(RUN_DATE)-$(O)-$(LOCALE).nt)

# Individual occupation QID files (one per occupation QID).
# ALL_OCC_QIDS is the full list from TSV files; used for the "claim" rule and OCC_QIDS_FILE.
# occ_qids uses a sub-make driven by active_occ_qids.txt (written by group_q5_by_occupation.py)
# so that QIDs with zero Q5 subjects are never targeted.
ALL_OCC_QIDS         := $(sort $(foreach F,$(ALL_OCC_FILES),$(shell awk '{print $$1}' $(F))))

# ALL_OCC_WITH_UNMATCHED includes the synthetic "unmatched" group (Q5 humans with no
# occupation match) generated as a side effect of group_q5_by_occupation.py.
ALL_OCC_WITH_UNMATCHED := $(ALL_OCC_NAMES) unmatched

# Fulltext derived targets
ALL_CLASS_QIDS_FULLTEXT   := $(foreach Q,$(ALL_CLASS_QIDS),$(FULLTEXT_CLASS_QIDS_DIR)/wikicore-$(RUN_DATE)-$(Q)-$(LOCALE).tsv)
ALL_CLASS_GROUPS_FULLTEXT := $(foreach C,$(ALL_CLASS_NAMES),$(FULLTEXT_CLASS_GROUPS_DIR)/wikicore-$(RUN_DATE)-$(C)-$(LOCALE).tsv)

core: $(FINAL_NT)

skos_class_qids: $(ALL_CLASS_QIDS_NTS)

skos_occ_qids: $(Q5_OCC_GROUPED)
	@if [ -s $(ACTIVE_OCC_QIDS_FILE) ]; then \
	  $(MAKE) $(foreach Q,$(shell cat $(ACTIVE_OCC_QIDS_FILE)),$(OCC_QIDS_DIR)/wikicore-$(RUN_DATE)-$(Q)-$(LOCALE).nt); \
	else \
	  echo "Warning: no active occupation QIDs found in $(ACTIVE_OCC_QIDS_FILE)"; \
	fi

skos_class_groups: $(ALL_CLASS_GROUP_NTS)

skos_occ_groups: $(ALL_OCC_GROUP_NTS)

skos: core skos_class_qids skos_occ_qids skos_class_groups skos_occ_groups

fulltext: fulltext_class_qids fulltext_class_groups fulltext_occ_groups

all: skos fulltext

# -----------------------
# Directories
# -----------------------
$(WORK_DIR) $(SPLIT_DIR) $(JENA_DIR) $(SUBJECTS_DIR) $(SKOS_DIR) $(LABELS_SPLIT_DIR) \
$(OUT_DIR) $(CLASS_QIDS_DIR) $(CLASS_GROUPS_DIR) $(OCC_QIDS_DIR) $(OCC_GROUPS_DIR) \
$(FULLTEXT_CLASS_QIDS_DIR) $(FULLTEXT_CLASS_GROUPS_DIR) \
$(FULLTEXT_OCC_GROUPS_DIR):
	mkdir -p $@

# -----------------------
# 1. Extract core properties and P106 in a single decompression pass
# -----------------------
$(CORE_PROPS_NT) $(P106_NT) &: $(PROP_DIRECT_GZ) $(SITELINKS_FILE) | $(WORK_DIR) $(SUBJECTS_DIR)
	pigz -dc $(PROP_DIRECT_GZ) \
	  | tee \
	    >(rg -F -e '/prop/direct/P31>' -e '/prop/direct/P279>' -e '/prop/direct/P361>' \
	        | rg -F -v '_:' > $(CORE_PROPS_NT)) \
	    >(rg -F '/prop/direct/P106>' \
	        | rg -F -v '_:' > $(P106_NT)) \
	    > /dev/null; wait

# Extract Q5 (human) subjects with sitelinks from core props (separate rule to
# avoid race condition with parallel builds: process substitution in step 1 may
# not flush Q5_SUBJECTS_FILE before make considers the &: recipe done)
$(Q5_SUBJECTS_FILE): $(CORE_PROPS_NT) $(SITELINKS_FILE) | $(SUBJECTS_DIR)
	rg -F '/prop/direct/P31> <http://www.wikidata.org/entity/Q5>' $(CORE_PROPS_NT) \
	  | awk '{print $$1}' \
	  | LC_ALL=C sort -u \
	  | LC_ALL=C join -o 2.1 $(SITELINKS_FILE) - \
	  | LC_ALL=C sort -u > $@

# -----------------------
# 2. Split + partition core properties
# -----------------------
SPLIT_DONE := $(SPLIT_DIR)/.split_done

$(SPLIT_DONE): $(CORE_PROPS_NT) | $(SPLIT_DIR)
	split -l $$(( ($$(wc -l < $(CORE_PROPS_NT)) + $(JOBS) - 1) / $(JOBS) )) $(CORE_PROPS_NT) $(SPLIT_DIR)/chunk_
	@touch $@

# Merge class and occupation names so partition_chunks routes occupation QIDs
# into their own per-QID subjects files (rather than P31_other)
$(OCC_NAMES_FILE): $(ALL_OCC_FILES) | $(WORK_DIR)
	cat $(ALL_OCC_FILES) > $@

# Create list of occupation QIDs for concept_scheme rule
$(OCC_QIDS_FILE): $(ALL_OCC_FILES) | $(WORK_DIR)
	cat $(ALL_OCC_FILES) | awk '{print $$1}' | LC_ALL=C sort -u > $@

$(ALL_NAMES_FILE): $(CLASS_NAMES_FILE) $(OCC_NAMES_FILE)
	cat $^ > $@

$(CONCEPT_BACKBONE): $(SPLIT_DONE) $(ALL_NAMES_FILE) | $(SUBJECTS_DIR)
	ls $(SPLIT_DIR)/chunk_* | \
	  parallel -j $(JOBS) --bar --halt now,fail=1 \
	    'python3 $(ROOT_DIR)/python/partition_chunks.py {} $(ALL_NAMES_FILE) $(WORK_DIR) $(SUBJECTS_DIR)'

# -----------------------
# 3. Prepare subject vocabularies
# -----------------------

# Sort, deduplicate, and pre-filter each per-subject TSV against sitelinks
$(SUBJECTS_DONE): $(CONCEPT_BACKBONE) $(SITELINKS_FILE)
	parallel -j $(JOBS) --bar --halt now,fail=1 \
	  'tmp=$$(mktemp); LC_ALL=C sort -u {1} | LC_ALL=C join -o 2.1 $(SITELINKS_FILE) - | LC_ALL=C sort -u > "$$tmp" && mv "$$tmp" {1}' \
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
# 3b. Group Q5 humans by occupation (P106_NT and Q5_SUBJECTS_FILE from combined step 1)
# -----------------------

# Group Q5 subjects by occupation group and by individual QID in a single P106_NT pass
$(Q5_OCC_GROUPED): $(P106_NT) $(Q5_SUBJECTS_FILE) $(ALL_OCC_FILES) | $(SUBJECTS_DIR)
	python3 $(ROOT_DIR)/python/group_q5_by_occupation.py
	@touch $@

# Per-occupation-QID subject files are generated as a side effect of Q5_OCC_GROUPED
# (replaces the former OCC_QID_SUBJECTS_RULE which did 1 rg pass per QID over P106_NT)
$(foreach Q,$(ALL_OCC_QIDS),$(SUBJECTS_DIR)/$(Q)_subjects.tsv): $(Q5_OCC_GROUPED) ;

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
	  | rg -F '<http://www.wikidata.org/entity/' \
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
	split -l $$(( ($$(wc -l < $(SKOS_LABELS_NT)) + $(JOBS) - 1) / $(JOBS) )) $(SKOS_LABELS_NT) $(LABELS_SPLIT_DIR)/chunk_
	@touch $@

# -----------------------
# 7. Generate SKOS class QID vocabs
# eg. make skos_class_qid QIDS="Q5 Q532"
# -----------------------

QIDS ?= core

CLASS_QID_OUTS := $(foreach Q,$(QIDS),\
  $(CLASS_QIDS_DIR)/wikicore-$(RUN_DATE)-$(Q)-$(LOCALE).nt)

skos_class_qid: $(CLASS_QID_OUTS)

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
	elif echo "$$id" | rg -qE '^Q5_'; then \
		category=$$(echo "$$id" | sed 's/^Q5_//'); \
		vocab_uri="$(VOCAB_URI)/occupations/$$category"; \
	elif echo "$$id" | rg -qE '^P106-Q'; then \
		occ_qid=$$(echo "$$id" | sed 's/^P106-//'); \
		vocab_uri="$(VOCAB_URI)/occupations/$$occ_qid"; \
	elif echo "$$id" | rg -qE '^Q[0-9]+$$' && rg -qF "$$id" $(OCC_QIDS_FILE); then \
		vocab_uri="$(VOCAB_URI)/occupations/$$id"; \
	elif echo "$$id" | rg -qE '^Q[0-9]+$$'; then \
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
	  'awk "NR==FNR{core[\$$1]=1;next}\$$1 in core&&!seen[\$$0]++" $(SUBJECTS_DIR)/$*_subjects.tsv {}' \
	  ::: $(LABELS_SPLIT_DIR)/chunk_* \
	  | LC_ALL=C sort -u > $@

$(CONCEPT_BACKBONE_SORTED): $(CONCEPT_BACKBONE)
	LC_ALL=C sort -u $< > $@

$(SKOS_DIR)/skos_%_broader.nt: $(SUBJECTS_DIR)/%_subjects.tsv $(CONCEPT_BACKBONE_SORTED) | $(SKOS_DIR)
	LC_ALL=C join $(SUBJECTS_DIR)/$*_subjects.tsv $(CONCEPT_BACKBONE_SORTED) \
	  | awk -v broader="$(SKOS_BROADER_URI)" '{ print $$1 " <" broader "> " $$3 " ." }' \
	  > $@

$(FINAL_NT): \
	$(SKOS_DIR)/skos_core_concepts.nt \
	$(SKOS_DIR)/skos_core_concept_scheme.nt \
	$(SKOS_DIR)/skos_core_labels_$(LOCALE).nt \
	$(SKOS_DIR)/skos_core_broader.nt | $(OUT_DIR)
	cat $^ > $@

$(CLASS_QIDS_DIR)/wikicore-$(RUN_DATE)-%-$(LOCALE).nt: \
	$(SKOS_DIR)/skos_%_concepts.nt \
	$(SKOS_DIR)/skos_%_concept_scheme.nt \
	$(SKOS_DIR)/skos_%_labels_$(LOCALE).nt \
	$(SKOS_DIR)/skos_%_broader.nt | $(CLASS_QIDS_DIR)
	cat $^ > $@

$(OCC_QIDS_DIR)/wikicore-$(RUN_DATE)-%-$(LOCALE).nt: \
	$(SKOS_DIR)/skos_%_concepts.nt \
	$(SKOS_DIR)/skos_%_concept_scheme.nt \
	$(SKOS_DIR)/skos_%_labels_$(LOCALE).nt \
	$(SKOS_DIR)/skos_%_broader.nt | $(OCC_QIDS_DIR)
	cat $^ > $@

# -----------------------
# 8. Generate SKOS vocab from a classes/ TSV
# eg. make skos_class_group CLASS_FILE=classes/aircraft.tsv
# -----------------------

CLASS_FILE  ?=
CLASS_NAME   = $(basename $(notdir $(CLASS_FILE)))
CLASS_NT     = $(CLASS_GROUPS_DIR)/wikicore-$(RUN_DATE)-$(CLASS_NAME)-$(LOCALE).nt

skos_class_group:
ifndef CLASS_FILE
	$(error CLASS_FILE is not set. Usage: make skos_class_group CLASS_FILE=classes/aircraft.tsv)
endif
	$(MAKE) $(CLASS_NT)

# Per-class combined NTs — one rule per classes/*.tsv (used by skos_class_group and make class_groups)
define CLASS_RULE
$(CLASS_GROUPS_DIR)/wikicore-$(RUN_DATE)-$(1)-$(LOCALE).nt: \
    $$(foreach Q,$$(shell awk '{print $$$$1}' $(ROOT_DIR)/classes/$(1).tsv),\
      $(CLASS_QIDS_DIR)/wikicore-$(RUN_DATE)-$$(Q)-$(LOCALE).nt) | $(CLASS_GROUPS_DIR)
	# Use parallel cat for faster concatenation with many files
	parallel -j $(JOBS) --bar --halt now,fail=1 'cat {}' ::: $$^ > $$@
	@echo "Generated $$@"
endef
$(foreach C,$(ALL_CLASS_NAMES),$(eval $(call CLASS_RULE,$(C))))

# -----------------------
# 9. Generate SKOS vocabs from occupations/ TSVs
# Each occupation generates SKOS about Q5 (human) entities that have that occupation
# eg. make skos_occ_group OCC_FILE=occupations/engineering.tsv
# -----------------------

OCC_FILE   ?=
OCC_NAME    = $(basename $(notdir $(OCC_FILE)))
OCC_NT      = $(OCC_GROUPS_DIR)/wikicore-$(RUN_DATE)-$(OCC_NAME)-$(LOCALE).nt

skos_occ_group:
ifndef OCC_FILE
	$(error OCC_FILE is not set. Usage: make skos_occ_group OCC_FILE=occupations/engineering.tsv)
endif
	$(MAKE) $(OCC_NT)

# Per-occupation combined NTs — one rule per occupations/*.tsv
# Generates SKOS from Q5_{occupation}_subjects.tsv files created by group_q5_by_occupation.py
define OCC_RULE
$(OCC_GROUPS_DIR)/wikicore-$(RUN_DATE)-$(1)-$(LOCALE).nt: \
    $(Q5_OCC_GROUPED) \
    $(SKOS_DIR)/skos_Q5_$(1)_concepts.nt \
    $(SKOS_DIR)/skos_Q5_$(1)_concept_scheme.nt \
    $(SKOS_DIR)/skos_Q5_$(1)_labels_$(LOCALE).nt \
    $(SKOS_DIR)/skos_Q5_$(1)_broader.nt | $(OCC_GROUPS_DIR)
	cat $(SKOS_DIR)/skos_Q5_$(1)_concepts.nt \
	    $(SKOS_DIR)/skos_Q5_$(1)_concept_scheme.nt \
	    $(SKOS_DIR)/skos_Q5_$(1)_labels_$(LOCALE).nt \
	    $(SKOS_DIR)/skos_Q5_$(1)_broader.nt \
	    > $$@
	@echo "Generated $$@"
endef
$(foreach O,$(ALL_OCC_NAMES),$(eval $(call OCC_RULE,$(O))))

# -----------------------
# 9b. Generate SKOS for Q5 humans with no matched occupation
# eg. make skos_occ_unmatched
# -----------------------

UNMATCHED_OCC_NT := $(OCC_GROUPS_DIR)/wikicore-$(RUN_DATE)-unmatched-$(LOCALE).nt

# Claim Q5_unmatched_subjects.tsv as output of Q5_OCC_GROUPED
$(SUBJECTS_DIR)/Q5_unmatched_subjects.tsv: $(Q5_OCC_GROUPED) ;

skos_occ_unmatched: $(UNMATCHED_OCC_NT)

$(UNMATCHED_OCC_NT): \
    $(Q5_OCC_GROUPED) \
    $(SKOS_DIR)/skos_Q5_unmatched_concepts.nt \
    $(SKOS_DIR)/skos_Q5_unmatched_concept_scheme.nt \
    $(SKOS_DIR)/skos_Q5_unmatched_labels_$(LOCALE).nt \
    $(SKOS_DIR)/skos_Q5_unmatched_broader.nt | $(OCC_GROUPS_DIR)
	cat $(SKOS_DIR)/skos_Q5_unmatched_concepts.nt \
	    $(SKOS_DIR)/skos_Q5_unmatched_concept_scheme.nt \
	    $(SKOS_DIR)/skos_Q5_unmatched_labels_$(LOCALE).nt \
	    $(SKOS_DIR)/skos_Q5_unmatched_broader.nt \
	    > $@
	@echo "Generated $@"

# -----------------------
# 10. Generate SKOS for Q5 humans by occupation QID
# eg. make skos_occ_qid QID=Q7888586
# -----------------------

QID ?=
OCC_QID_NT = $(OCC_QIDS_DIR)/wikicore-$(RUN_DATE)-$(QID)-$(LOCALE).nt

skos_occ_qid:
ifndef QID
	$(error QID is not set. Usage: make skos_occ_qid QID=Q7888586)
endif
	@echo "Generating SKOS for Q5 humans with P106=$(QID)"
	$(MAKE) $(Q5_OCC_GROUPED)
	$(MAKE) $(OCC_QID_NT)

# -----------------------
# Convert .nt files to compressed Turtle
# -----------------------
TURTLE_GZS := $(FINAL_NT:.nt=.ttl.gz) \
              $(ALL_CLASS_QIDS_NTS:.nt=.ttl.gz) \
              $(ALL_CLASS_GROUP_NTS:.nt=.ttl.gz) \
              $(ALL_OCC_GROUP_NTS:.nt=.ttl.gz)

PREFIXES_TTL := $(ROOT_DIR)/prefixes.ttl

PIGZ_JOBS := $(shell echo $$(( $(JOBS) > 4 ? 4 : $(JOBS) )))

%.ttl.gz: %.nt $(PREFIXES_TTL)
	riot --output=turtle $(PREFIXES_TTL) $< 2>/dev/null | pigz -p $(PIGZ_JOBS) > $@
	@echo "Generated $@"

turtle: $(TURTLE_GZS)
	@if [ -s $(ACTIVE_OCC_QIDS_FILE) ]; then \
	  $(MAKE) $(foreach Q,$(shell cat $(ACTIVE_OCC_QIDS_FILE)),$(OCC_QIDS_DIR)/wikicore-$(RUN_DATE)-$(Q)-$(LOCALE).ttl.gz); \
	fi

# -----------------------
# Clean
# -----------------------
clean:
	rm -rf $(WORK_DIR)

distclean: clean
	rm -rf $(OUT_DIR) $(FULLTEXT_DIR)

# ===========================================================
# Fulltext TSV generation from wikidata5m_text.txt.gz
#
# Class domain:  one TSV per class QID; one combined TSV per classes/ group
# Occ domain:    one TSV per occupation group (people in that group);
#                one TSV per active occupation QID (people with that occupation)
#
# Output format per line: text<TAB><http://www.wikidata.org/entity/Q###>
# ===========================================================

# -----------------------
# Class domain fulltext
# eg. make fulltext_class_qids
#     make fulltext_class_groups
#     make fulltext_class_qid QIDS='Q5 Q532'
#     make fulltext_class_group CLASS_FILE=classes/aircraft.tsv
# -----------------------

# Collect all class QIDs across all classes/ TSVs
$(FULLTEXT_CLASS_QIDS_FILE): $(ALL_CLASS_FILES) | $(WORK_DIR)
	cat $(ALL_CLASS_FILES) | awk '{print $$1}' | LC_ALL=C sort -u > $@

# Build instance QID -> class QID mapping from P31 relationships.
# Runs rg+awk in parallel over pre-split chunks (reusing SPLIT_DONE from step 2).
# awk hash lookup filters to target class QIDs before sorting, avoiding an
# expensive sort+join on the full P31 dataset.
$(FULLTEXT_CLASS_INSTANCE_MAP): $(SPLIT_DONE) $(FULLTEXT_CLASS_QIDS_FILE) | $(WORK_DIR)
	@echo "Building class instance map from P31 relationships..."
	@export qf="$(FULLTEXT_CLASS_QIDS_FILE)"; \
	 filter_p31() { \
	   rg -F '/prop/direct/P31>' "$$1" \
	   | awk -v f="$$qf" \
	     'BEGIN{p="<http://www.wikidata.org/entity/";pl=length(p);while((getline q<f)>0)c[q]=1} \
	      {s=substr($$1,pl+1,length($$1)-pl-1);o=substr($$3,pl+1,length($$3)-pl-1);if(o in c)print s"\t"o}'; \
	 }; \
	 export -f filter_p31; \
	 ls $(SPLIT_DIR)/chunk_* | \
	   parallel -j $(JOBS) --halt now,fail=1 filter_p31 \
	   | LC_ALL=C sort -u --parallel=$(JOBS) \
	   > $@

# Single pass through fulltext GZ: one TSV per class QID containing text from all instances.
# QIDs with no fulltext entry are touched (empty file) so group cat rules never fail.
$(FULLTEXT_CLASS_SPLIT_DONE): $(FULLTEXT_GZ) $(FULLTEXT_CLASS_INSTANCE_MAP) $(FULLTEXT_CLASS_QIDS_FILE) | $(FULLTEXT_CLASS_QIDS_DIR)
	python3 $(ROOT_DIR)/python/split_fulltext.py classes \
	  --map     $(FULLTEXT_CLASS_INSTANCE_MAP) \
	  --qids    $(FULLTEXT_CLASS_QIDS_FILE) \
	  --gz      $(FULLTEXT_GZ) \
	  --out-dir $(FULLTEXT_CLASS_QIDS_DIR) \
	  --date    $(RUN_DATE) \
	  --locale  $(LOCALE)
	@touch $@

# Claim per-class-QID fulltext TSVs as outputs of the split
$(FULLTEXT_CLASS_QIDS_DIR)/wikicore-$(RUN_DATE)-%-$(LOCALE).tsv: $(FULLTEXT_CLASS_SPLIT_DONE) ;

# All class QID fulltext files
fulltext_class_qids: $(FULLTEXT_CLASS_SPLIT_DONE)

# Specific class QID(s): make fulltext_class_qid QIDS='Q5 Q532'
CLASS_QID_FULLTEXT_OUTS := $(foreach Q,$(QIDS),\
  $(FULLTEXT_CLASS_QIDS_DIR)/wikicore-$(RUN_DATE)-$(Q)-$(LOCALE).tsv)

fulltext_class_qid: $(CLASS_QID_FULLTEXT_OUTS)

# Per-class-group fulltext files — concatenate per-QID files for each classes/*.tsv
define FULLTEXT_CLASS_GROUP_RULE
$(FULLTEXT_CLASS_GROUPS_DIR)/wikicore-$(RUN_DATE)-$(1)-$(LOCALE).tsv: \
    $(foreach Q,$(shell awk '{print $$1}' $(ROOT_DIR)/classes/$(1).tsv),\
      $(FULLTEXT_CLASS_QIDS_DIR)/wikicore-$(RUN_DATE)-$(Q)-$(LOCALE).tsv) | $(FULLTEXT_CLASS_GROUPS_DIR)
	# Use parallel cat for faster concatenation with many files
	parallel -j $(JOBS) --bar --halt now,fail=1 'cat {}' ::: $$^ > $$@
	@echo "Generated $$@"
endef
$(foreach C,$(ALL_CLASS_NAMES),$(eval $(call FULLTEXT_CLASS_GROUP_RULE,$(C))))

# All class group fulltext files
fulltext_class_groups: $(ALL_CLASS_GROUPS_FULLTEXT)

# Specific class group: make fulltext_class_group CLASS_FILE=classes/aircraft.tsv
CLASS_GROUP_FULLTEXT_TSV = $(FULLTEXT_CLASS_GROUPS_DIR)/wikicore-$(RUN_DATE)-$(CLASS_NAME)-$(LOCALE).tsv

fulltext_class_group:
ifndef CLASS_FILE
	$(error CLASS_FILE is not set. Usage: make fulltext_class_group CLASS_FILE=classes/aircraft.tsv)
endif
	$(MAKE) $(CLASS_GROUP_FULLTEXT_TSV)

# -----------------------
# Occupation domain fulltext
# eg. make fulltext_occ_groups
#     make fulltext_occ_group OCC_FILE=occupations/engineering.tsv
#
# Source QIDs come from the subjects/ working files (URI format) created by
# group_q5_by_occupation.py:
#   Q5_{group}_subjects.tsv  — people in each occupation group
# URIs are stripped to plain QIDs for matching against the fulltext GZ.
# People appearing in multiple groups are written to each group file.
# -----------------------

# Build human-QID → group-name mapping from Q5_*_subjects.tsv files
$(FULLTEXT_OCC_GROUP_MAP): $(Q5_OCC_GROUPED) | $(WORK_DIR)
	@echo "Building occupation group fulltext QID map..."
	@for occ in $(ALL_OCC_WITH_UNMATCHED); do \
	    f="$(SUBJECTS_DIR)/Q5_$${occ}_subjects.tsv"; \
	    [ -f "$$f" ] && \
	      sed 's|<http://www.wikidata.org/entity/||;s|>||g' "$$f" \
	        | awk -v g="$$occ" '{print $$1 "\t" g}'; \
	done | LC_ALL=C sort -u > $@

# Single pass through fulltext GZ: one TSV per occupation group.
# A person in multiple groups is written to each group file.
$(FULLTEXT_OCC_GROUPS_DONE): $(FULLTEXT_GZ) $(FULLTEXT_OCC_GROUP_MAP) | $(FULLTEXT_OCC_GROUPS_DIR)
	python3 $(ROOT_DIR)/python/split_fulltext.py occs \
	  --map     $(FULLTEXT_OCC_GROUP_MAP) \
	  --gz      $(FULLTEXT_GZ) \
	  --out-dir $(FULLTEXT_OCC_GROUPS_DIR) \
	  --date    $(RUN_DATE) \
	  --locale  $(LOCALE) \
	  --groups  $(ALL_OCC_WITH_UNMATCHED)
	@touch $@

# Claim per-occ-group fulltext TSVs as outputs of the split
$(FULLTEXT_OCC_GROUPS_DIR)/wikicore-$(RUN_DATE)-%-$(LOCALE).tsv: $(FULLTEXT_OCC_GROUPS_DONE) ;

# All occupation group fulltext files
ALL_OCC_GROUPS_FULLTEXT := $(foreach O,$(ALL_OCC_NAMES),$(FULLTEXT_OCC_GROUPS_DIR)/wikicore-$(RUN_DATE)-$(O)-$(LOCALE).tsv)

fulltext_occ_groups: $(ALL_OCC_GROUPS_FULLTEXT)

# Specific occupation group: make fulltext_occ_group OCC_FILE=occupations/engineering.tsv
OCC_GROUP_FULLTEXT_TSV = $(FULLTEXT_OCC_GROUPS_DIR)/wikicore-$(RUN_DATE)-$(OCC_NAME)-$(LOCALE).tsv

fulltext_occ_group:
ifndef OCC_FILE
	$(error OCC_FILE is not set. Usage: make fulltext_occ_group OCC_FILE=occupations/engineering.tsv)
endif
	$(MAKE) $(OCC_GROUP_FULLTEXT_TSV)

# Q5 humans with no matched occupation — produced in the same GZ pass as fulltext_occ_groups
FULLTEXT_OCC_UNMATCHED_TSV := $(FULLTEXT_OCC_GROUPS_DIR)/wikicore-$(RUN_DATE)-unmatched-$(LOCALE).tsv

fulltext_occ_unmatched: $(FULLTEXT_OCC_UNMATCHED_TSV)
