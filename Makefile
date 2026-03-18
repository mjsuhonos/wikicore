# -----------------------
# Wiki Core processing pipeline
# -----------------------

SHELL := /bin/bash
.SHELLFLAGS := -o pipefail -c
.PHONY: all skos fulltext \
        skos_core skos_class_qids skos_class_groups skos_occ_qids skos_occ_groups \
        skos_class_qid skos_class_group skos_occ_qid skos_occ_group skos_occ_unmatched \
        turtle clean help \
        fulltext_core fulltext_class_qids fulltext_class_groups fulltext_class_qid fulltext_class_group \
        fulltext_occ_groups fulltext_occ_group fulltext_occ_unmatched \
        fulltext_occ_qids fulltext_occ_qid \
        skos_P31_other fulltext_P31_other \
        annif_projects

help:
	@echo "Wiki Core processing pipeline"
	@echo ""
	@echo "Usage: make <target> [OPTIONS]"
	@echo ""
	@echo "Aggregate targets:"
	@echo "  all                                   Build everything: skos + fulltext"
	@echo "  skos                                  Build all SKOS .nt files (core + class_qids/groups + occ_qids/groups + unmatched + P31_other)"
	@echo "  fulltext                              Build all fulltext TSVs (require source.nosync/wikidata5m_text.txt.gz)"
	@echo ""
	@echo "SKOS targets:"
	@echo "  skos_core                             Build the core SKOS vocab (wikicore-DATE-core-LOCALE.nt)"
	@echo "  skos_class_qids                       Build one .nt per class QID across all classes/ TSVs (777 files)"
	@echo "  skos_class_groups                     Build one combined .nt per classes/ TSV (43 files)"
	@echo "  skos_occ_qids                         Build one .nt per occupation QID (up to 1,449 files, SKOS about Q5 humans)"
	@echo "  skos_occ_groups                       Build one combined .nt per occupations/ TSV (19 files, SKOS about Q5 humans)"
	@echo "  skos_class_qid QIDS='...'             Build SKOS for specific class QIDs (eg. 'Q5 Q532')"
	@echo "  skos_class_group CLASS_FILE=<path>    Build combined .nt for a single classes/ TSV"
	@echo "  skos_occ_qid QID=<QID>                Build SKOS for Q5 humans with a specific occupation QID"
	@echo "  skos_occ_group OCC_FILE=<path>        Build combined .nt for a single occupations/ TSV"
	@echo "  skos_occ_unmatched                    Build SKOS for Q5 humans with no matched occupation"
	@echo "  skos_P31_other                        Build SKOS for entities with unrecognized P31 values"
	@echo "  turtle                                Convert all .nt files to compressed Turtle (.ttl.gz)"
	@echo ""
	@echo "Fulltext targets:"
	@echo "  fulltext_core                         Build fulltext TSV for core vocabulary concepts"
	@echo "  fulltext_class_qids                   Build one fulltext TSV per class QID"
	@echo "  fulltext_class_groups                 Build one combined fulltext TSV per classes/ TSV"
	@echo "  fulltext_occ_groups                   Build one combined fulltext TSV per occupations/ TSV (people)"
	@echo "  fulltext_class_qid QIDS='...'         Build fulltext TSVs for specific class QIDs (eg. 'Q5 Q532')"
	@echo "  fulltext_class_group CLASS_FILE=<path> Build combined fulltext TSV for a single classes/ TSV"
	@echo "  fulltext_occ_group OCC_FILE=<path>    Build combined fulltext TSV for a single occupations/ TSV"
	@echo "  fulltext_occ_qids                     Build one fulltext TSV per occupation QID (people)"
	@echo "  fulltext_occ_qid QIDS='...'           Build fulltext TSVs for specific occupation QIDs (eg. 'Q33999')"
	@echo "  fulltext_occ_unmatched                Build fulltext TSV for Q5 humans with no matched occupation"
	@echo "  fulltext_P31_other                    Build fulltext TSV for entities with unrecognized P31 values"
	@echo ""
	@echo "Annif targets:"
	@echo "  annif_projects                        Generate Annif project .cfg files into annif/"
	@echo ""
	@echo "Utility targets:"
	@echo "  clean                                 Remove working files"
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

# -----------------------
# Paths
# -----------------------
ROOT_DIR         := $(PWD)
SOURCE_DIR       := $(ROOT_DIR)/source.nosync
WORK_DIR         := $(ROOT_DIR)/working.nosync
CLASS_NAMES_FILE := $(ROOT_DIR)/class_names.tsv
OCC_NAMES_FILE   := $(WORK_DIR)/occ_names.tsv
ALL_NAMES_FILE   := $(WORK_DIR)/all_names.tsv

# Output directories (dated release layout)
OUT_DIR          := $(ROOT_DIR)/wikicore-$(RUN_DATE)-$(LOCALE)
CLASS_QIDS_DIR   := $(OUT_DIR)/classes/qids
CLASS_GROUPS_DIR := $(OUT_DIR)/classes
OCC_QIDS_DIR     := $(OUT_DIR)/occupations/qids
OCC_GROUPS_DIR   := $(OUT_DIR)/occupations
SUBJECTS_OUT_DIR := $(OUT_DIR)/subjects

# Fulltext output directories
FULLTEXT_DIR              := $(OUT_DIR)/fulltext
FULLTEXT_CLASS_QIDS_DIR   := $(FULLTEXT_DIR)/classes/qids
FULLTEXT_CLASS_GROUPS_DIR := $(FULLTEXT_DIR)/classes
FULLTEXT_OCC_GROUPS_DIR   := $(FULLTEXT_DIR)/occupations
FULLTEXT_OCC_QIDS_DIR     := $(FULLTEXT_DIR)/occupations/qids
FULLTEXT_SUBJECTS_DIR     := $(FULLTEXT_DIR)/subjects

# -----------------------
# Inputs
# -----------------------
CLEANED_GZ       := $(SOURCE_DIR)/wikidata-20251229-cleaned.gz
SITELINKS_GZ     := $(SOURCE_DIR)/sitelinks_en.tsv.gz

# -----------------------
# Working files
# -----------------------
SITELINKS_FILE        := $(WORK_DIR)/sitelinks_en_qids.tsv
SKOS_DIR              := $(WORK_DIR)/skos
SPLIT_DIR             := $(WORK_DIR)/splits
SUBJECTS_DIR          := $(WORK_DIR)/subjects
SUBJECTS_SORTED       := $(SUBJECTS_DIR)/subjects_sorted.tsv
SUBJECTS_DONE         := $(SUBJECTS_DIR)/.subjects_individually_sorted
LABELS_ROUTED_DONE    := $(SKOS_DIR)/.labels_routed_done
CONCEPT_BACKBONE_SORTED := $(WORK_DIR)/concept_backbone_sorted.nt

# Fulltext working files
FULLTEXT_GZ                := $(SOURCE_DIR)/wikidata5m_text.txt.gz
FULLTEXT_CORE_MAP          := $(WORK_DIR)/fulltext_core_map.tsv
FULLTEXT_CORE_DONE         := $(WORK_DIR)/.fulltext_core_done
FULLTEXT_CLASS_QIDS_FILE   := $(WORK_DIR)/fulltext_class_qids.txt
FULLTEXT_CLASS_INSTANCE_MAP := $(WORK_DIR)/fulltext_class_instance_map.tsv
FULLTEXT_CLASS_SPLIT_DONE  := $(WORK_DIR)/.fulltext_class_split_done
FULLTEXT_OCC_GROUP_MAP     := $(WORK_DIR)/fulltext_occ_group_map.tsv
FULLTEXT_OCC_GROUPS_DONE   := $(WORK_DIR)/.fulltext_occ_groups_done
FULLTEXT_OCC_QID_MAP      := $(WORK_DIR)/fulltext_occ_qid_map.tsv
FULLTEXT_OCC_QIDS_DONE    := $(WORK_DIR)/.fulltext_occ_qids_done
FULLTEXT_P31_OTHER_MAP    := $(WORK_DIR)/fulltext_p31_other_map.tsv
FULLTEXT_P31_OTHER_DONE   := $(WORK_DIR)/.fulltext_p31_other_done

# Fulltext output files
FULLTEXT_CORE_TSV          := $(FULLTEXT_DIR)/wikicore-$(RUN_DATE)-core-$(LOCALE).tsv
FULLTEXT_P31_OTHER_TSV     := $(FULLTEXT_SUBJECTS_DIR)/wikicore-$(RUN_DATE)-other-$(LOCALE).tsv

# -----------------------
# Core files
# -----------------------
CONCEPT_BACKBONE    := $(WORK_DIR)/concept_backbone.nt
CORE_PROPS_NT       := $(WORK_DIR)/wikidata-core-properties.nt
SKOS_LABELS_NT      := $(WORK_DIR)/wikidata-skos-labels-$(LOCALE).nt
CORE_QIDS           := $(SUBJECTS_DIR)/core_subjects.tsv

# -----------------------
# P106 (occupation) files
# -----------------------
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
FINAL_CORE_NT       := $(OUT_DIR)/wikicore-$(RUN_DATE)-core-$(LOCALE).nt

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
# ALL_OCC_QIDS: full list from TSV files for claim rules
# ALL_OCC_WITH_UNMATCHED: includes synthetic "unmatched" group for Q5 humans without occupation matches
ALL_OCC_QIDS         := $(sort $(foreach F,$(ALL_OCC_FILES),$(shell awk '{print $$1}' $(F))))
ALL_OCC_WITH_UNMATCHED := $(ALL_OCC_NAMES) unmatched

# Fulltext derived targets
ALL_CLASS_QIDS_FULLTEXT   := $(foreach Q,$(ALL_CLASS_QIDS),$(FULLTEXT_CLASS_QIDS_DIR)/wikicore-$(RUN_DATE)-$(Q)-$(LOCALE).tsv)
ALL_CLASS_GROUPS_FULLTEXT := $(foreach C,$(ALL_CLASS_NAMES),$(FULLTEXT_CLASS_GROUPS_DIR)/wikicore-$(RUN_DATE)-$(C)-$(LOCALE).tsv)

skos_core: $(FINAL_CORE_NT)

# Core-only version of Q5 occupation grouping (skips per-QID subject files)
Q5_OCC_GROUPED_CORE := $(SUBJECTS_DIR)/.q5_occupation_grouped_core

$(Q5_OCC_GROUPED_CORE): $(CORE_PROPS_NT) $(Q5_SUBJECTS_FILE) $(ALL_OCC_FILES) $(SUBJECTS_DONE) | $(SUBJECTS_DIR)
	python3 $(ROOT_DIR)/python/group_q5_by_occupation.py --core-only <(rg -F '/prop/direct/P106>' $(CORE_PROPS_NT))
	@touch $@

# Q5_unmatched_subjects.tsv is claimed as output below (after both core and full versions are defined)

# Full version of Q5 occupation grouping (creates per-QID subject files)
Q5_OCC_GROUPED_FULL := $(Q5_OCC_GROUPED)
Q5_OCC_GROUPED := $(Q5_OCC_GROUPED_FULL)

$(Q5_OCC_GROUPED_FULL): $(CORE_PROPS_NT) $(Q5_SUBJECTS_FILE) $(ALL_OCC_FILES) $(SUBJECTS_DONE) | $(SUBJECTS_DIR)
	python3 $(ROOT_DIR)/python/group_q5_by_occupation.py <(rg -F '/prop/direct/P106>' $(CORE_PROPS_NT))
	@touch $@

# Per-occupation-QID subject files are generated as a side effect of Q5_OCC_GROUPED_FULL
$(foreach Q,$(ALL_OCC_QIDS),$(SUBJECTS_DIR)/$(Q)_subjects.tsv): $(Q5_OCC_GROUPED_FULL) ;

# active_occ_qids.txt is also written as a side effect of group_q5_by_occupation.py
$(ACTIVE_OCC_QIDS_FILE): $(Q5_OCC_GROUPED_FULL) ;

# Remove the old Q5_OCC_GROUPED target definition to avoid duplicates
# The variable Q5_OCC_GROUPED now points to Q5_OCC_GROUPED_FULL

skos_class_qids: $(SUBJECTS_DONE) $(LABELS_ROUTED_DONE) $(CONCEPT_BACKBONE_SORTED) | $(CLASS_QIDS_DIR)
	$(MAKE) -j $(JOBS) $(ALL_CLASS_QIDS_NTS)

skos_occ_qids: $(Q5_OCC_GROUPED_FULL) $(SUBJECTS_DONE) $(LABELS_ROUTED_DONE) $(CONCEPT_BACKBONE_SORTED)
	@if [ -s $(ACTIVE_OCC_QIDS_FILE) ]; then \
	  $(MAKE) -j $(JOBS) $(foreach Q,$(shell cat $(ACTIVE_OCC_QIDS_FILE)),$(OCC_QIDS_DIR)/wikicore-$(RUN_DATE)-$(Q)-$(LOCALE).nt); \
	else \
	  echo "Warning: no active occupation QIDs found in $(ACTIVE_OCC_QIDS_FILE)"; \
	fi

skos_class_groups: skos_class_qids | $(CLASS_GROUPS_DIR)
	$(MAKE) -j $(JOBS) $(ALL_CLASS_GROUP_NTS)

skos_occ_groups: $(Q5_OCC_GROUPED_FULL) $(SUBJECTS_DONE) $(LABELS_ROUTED_DONE) $(CONCEPT_BACKBONE_SORTED) | $(OCC_GROUPS_DIR)
	$(MAKE) -j $(JOBS) $(ALL_OCC_GROUP_NTS)

skos: skos_core skos_class_qids skos_occ_qids skos_class_groups skos_occ_groups skos_occ_unmatched

# Build P31_other SKOS after all subjects are processed
skos: skos_P31_other

fulltext: fulltext_core fulltext_class_qids fulltext_class_groups fulltext_occ_groups fulltext_occ_qids fulltext_occ_unmatched fulltext_P31_other

all: skos fulltext

# -----------------------
# Directories
# -----------------------
$(WORK_DIR) $(SPLIT_DIR) $(SUBJECTS_DIR) $(SKOS_DIR) \
$(OUT_DIR) $(CLASS_QIDS_DIR) $(CLASS_GROUPS_DIR) $(OCC_QIDS_DIR) $(OCC_GROUPS_DIR) \
$(SUBJECTS_OUT_DIR) \
$(FULLTEXT_DIR) $(FULLTEXT_CLASS_QIDS_DIR) $(FULLTEXT_CLASS_GROUPS_DIR) \
$(FULLTEXT_OCC_GROUPS_DIR) $(FULLTEXT_OCC_QIDS_DIR) $(FULLTEXT_SUBJECTS_DIR):
	mkdir -p $@

# -----------------------
# 0. Extract QIDs from sitelinks (first column of sitelinks_en.tsv.gz)
# -----------------------
$(SITELINKS_FILE): $(SITELINKS_GZ) | $(WORK_DIR)
	pigz -dc $< | awk '{print $$1}' | LC_ALL=C sort -u > $@

# -----------------------
# 1. Extract core properties and P106 in a single decompression pass
# -----------------------

# Direct rule for core properties extraction (includes P106)
# This replaces the CORE_EXTRACT_DONE sentinel with direct file dependencies
$(CORE_PROPS_NT): $(CLEANED_GZ) $(SITELINKS_FILE) | $(WORK_DIR) $(SUBJECTS_DIR)
	pigz -dc -p 4 $(CLEANED_GZ) \
	  | rg -F -e '/prop/direct/P31>' -e '/prop/direct/P279>' -e '/prop/direct/P361>' -e '/prop/direct/P106>' \
	  | rg -F -v '_:' \
	  | awk -v sf=$(SITELINKS_FILE) \
	      'BEGIN{while((getline<sf)>0)sl[$$1]=1}{if($$1 in sl)print}' \
	  > $@; wait

# Extract Q5 (human) subjects with sitelinks from core props
$(Q5_SUBJECTS_FILE): $(CORE_PROPS_NT) | $(SUBJECTS_DIR)
	rg -F '/prop/direct/P31> <http://www.wikidata.org/entity/Q5>' $(CORE_PROPS_NT) \
	  | awk '{print $$1}' \
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
	rm -f $@
	ls $(SPLIT_DIR)/chunk_* | \
	  parallel -j $(JOBS) --bar --halt now,fail=1 \
	    'python3 $(ROOT_DIR)/python/partition_chunks.py {} $(ALL_NAMES_FILE) $(WORK_DIR) $(SUBJECTS_DIR)'

# -----------------------
# 3. Prepare subject vocabularies
# -----------------------

# Sort and deduplicate each per-subject TSV (sitelinks already filtered at extraction)
# NOTE: $(CORE_QIDS) prevents race condition with parallel SUBJECTS_DONE
$(SUBJECTS_DONE): $(CONCEPT_BACKBONE) $(CORE_QIDS)
	parallel -j $(JOBS) --bar --halt now,fail=1 \
	  'tmp=$$(mktemp); LC_ALL=C sort -u {1} > "$$tmp" && mv "$$tmp" {1}' \
	  ::: $(SUBJECTS_DIR)/*subjects.tsv
	@touch $@

# Claim per-subject TSVs as outputs of SUBJECTS_DONE
$(SUBJECTS_DIR)/%_subjects.tsv: $(SUBJECTS_DONE) ;

# Merge all pre-filtered per-subject files into a single sorted, deduplicated file
$(SUBJECTS_SORTED): $(SUBJECTS_DONE)
	LC_ALL=C sort -m -u $(SUBJECTS_DIR)/*subjects.tsv \
	 > $@

# -----------------------
# 3b. Group Q5 humans by occupation
# -----------------------

# Note: Q5_OCC_GROUPED targets defined above in core and full versions

# -----------------------
# 4. Extract core concepts using file operations
# -----------------------
$(CORE_QIDS): $(CONCEPT_BACKBONE) $(CORE_PROPS_NT) | $(SUBJECTS_DIR)
	LC_ALL=C comm -23 \
	  <(rg -F -e 'P279>' -e 'P361>' $(CONCEPT_BACKBONE) | awk '{print $$1}' | LC_ALL=C sort -u --parallel=$(JOBS)) \
	  <(rg -F 'P31>' $(CORE_PROPS_NT) | awk '{print $$1}' | LC_ALL=C sort -u --parallel=$(JOBS)) \
	  | LC_ALL=C sort -u > $@

# -----------------------
# 6. Extract and split localized labels
# -----------------------
$(SKOS_LABELS_NT): $(CLEANED_GZ) | $(WORK_DIR)
	pigz -dc $(CLEANED_GZ) | rg 'skos/core#.*"@$(LOCALE) \.' > $@

$(LABELS_ROUTED_DONE): $(SKOS_LABELS_NT) $(SUBJECTS_DONE) $(CORE_QIDS) $(Q5_OCC_GROUPED_FULL) | $(SKOS_DIR)
	python3 $(ROOT_DIR)/python/route_labels.py \
	  --labels   $(SKOS_LABELS_NT) \
	  --subjects $(SUBJECTS_DIR) \
	  --out-dir  $(SKOS_DIR) \
	  --locale   $(LOCALE) \
	  --sort-workers $(JOBS)
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
	if [[ "$$id" == "core" ]]; then \
		vocab_uri="$(VOCAB_URI)/core"; \
	elif [[ "$$id" == Q5_* ]]; then \
		vocab_uri="$(VOCAB_URI)/occupations/$${id#Q5_}"; \
	elif [[ "$$id" == P106-Q* ]]; then \
		vocab_uri="$(VOCAB_URI)/occupations/$${id#P106-}"; \
	elif [[ "$$id" =~ ^Q[0-9]+$$ ]] && grep -qF "$$id" $(OCC_QIDS_FILE); then \
		vocab_uri="$(VOCAB_URI)/occupations/$$id"; \
	elif [[ "$$id" =~ ^Q[0-9]+$$ ]]; then \
		vocab_uri="$(VOCAB_URI)/subjects/$$id"; \
	elif [[ "$$id" == "P31_other" ]]; then \
		vocab_uri="$(VOCAB_URI)/subjects/other"; \
	else \
		vocab_uri="$(VOCAB_URI)/subjects/$$id"; \
	fi; \
	echo "<$$vocab_uri> <$(RDF_TYPE_URI)> <$(SKOS_CONCEPT_SCHEME_URI)> ." > $@; \
	awk -v inscheme="$(SKOS_INSCHEME_URI)" -v vocab="$$vocab_uri" \
	  '!seen[$$1]++ { print $$1, "<" inscheme ">", "<" vocab ">", "." }' $< >> $@

$(SKOS_DIR)/skos_%_labels_$(LOCALE).nt: $(LABELS_ROUTED_DONE) ;

$(CONCEPT_BACKBONE_SORTED): $(CONCEPT_BACKBONE)
	LC_ALL=C sort -u --parallel=$(JOBS) $< > $@

$(SKOS_DIR)/skos_%_broader.nt: $(SUBJECTS_DIR)/%_subjects.tsv $(CONCEPT_BACKBONE_SORTED) | $(SKOS_DIR)
	LC_ALL=C join $(SUBJECTS_DIR)/$*_subjects.tsv $(CONCEPT_BACKBONE_SORTED) \
	  | awk -v broader="$(SKOS_BROADER_URI)" '{ print $$1 " <" broader "> " $$3 " ." }' \
	  > $@

$(FINAL_CORE_NT): \
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
	cat $$^ > $$@
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
    $(Q5_OCC_GROUPED_FULL) \
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

UNMATCHED_OCC_NT    := $(OCC_GROUPS_DIR)/wikicore-$(RUN_DATE)-unmatched-$(LOCALE).nt
FINAL_P31_OTHER_NT  := $(SUBJECTS_OUT_DIR)/wikicore-$(RUN_DATE)-other-$(LOCALE).nt

# Claim Q5_unmatched_subjects.tsv as output of both core and full versions
$(SUBJECTS_DIR)/Q5_unmatched_subjects.tsv: $(Q5_OCC_GROUPED_CORE) $(Q5_OCC_GROUPED_FULL) ;

skos_occ_unmatched: $(UNMATCHED_OCC_NT)

$(UNMATCHED_OCC_NT): \
    $(Q5_OCC_GROUPED_FULL) \
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
# 9c. Generate SKOS for P31_other (entities with unrecognized P31 values)
# eg. make skos_P31_other
# -----------------------

skos_P31_other: $(FINAL_P31_OTHER_NT)

# Explicit rules for P31_other SKOS files to ensure SUBJECTS_DONE completes first
$(SKOS_DIR)/skos_P31_other_concepts.nt: $(SUBJECTS_DONE) | $(SKOS_DIR)
	awk -v type="$(RDF_TYPE_URI)" -v concept="$(SKOS_CONCEPT_URI)" \
	  '!seen[$$1]++ { print $$1, "<" type ">", "<" concept ">", "." }' $(SUBJECTS_DIR)/P31_other.subjects.tsv > $@

$(SKOS_DIR)/skos_P31_other_concept_scheme.nt: $(SUBJECTS_DONE) | $(SKOS_DIR)
	@vocab_uri="$(VOCAB_URI)/subjects/other"; \
	echo "<$$vocab_uri> <$(RDF_TYPE_URI)> <$(SKOS_CONCEPT_SCHEME_URI)> ." > $@; \
	awk -v inscheme="$(SKOS_INSCHEME_URI)" -v vocab="$$vocab_uri" \
	  '!seen[$$1]++ { print $$1, "<" inscheme ">", "<" vocab ">", "." }' $(SUBJECTS_DIR)/P31_other.subjects.tsv >> $@

$(SKOS_DIR)/skos_P31_other_broader.nt: $(SUBJECTS_DONE) $(CONCEPT_BACKBONE_SORTED) | $(SKOS_DIR)
	LC_ALL=C join $(SUBJECTS_DIR)/P31_other.subjects.tsv $(CONCEPT_BACKBONE_SORTED) \
	  | awk -v broader="$(SKOS_BROADER_URI)" '{ print $$1 " <" broader "> " $$3 " ." }' \
	  > $@

$(FINAL_P31_OTHER_NT): $(SUBJECTS_DONE) $(LABELS_ROUTED_DONE) $(CONCEPT_BACKBONE_SORTED) \
    $(SKOS_DIR)/skos_P31_other_concepts.nt \
    $(SKOS_DIR)/skos_P31_other_concept_scheme.nt \
    $(SKOS_DIR)/skos_P31_other_labels_$(LOCALE).nt \
    $(SKOS_DIR)/skos_P31_other_broader.nt | $(SUBJECTS_OUT_DIR)
	cat $^ > $@
	@echo "Generated $@"
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
	$(MAKE) $(Q5_OCC_GROUPED_FULL)
	$(MAKE) $(OCC_QID_NT)

# -----------------------
# Convert .nt files to compressed Turtle
# -----------------------
TURTLE_GZS := $(FINAL_CORE_NT:.nt=.ttl.gz) \
              $(ALL_CLASS_GROUP_NTS:.nt=.ttl.gz) \
              $(ALL_OCC_GROUP_NTS:.nt=.ttl.gz) \
              $(FINAL_P31_OTHER_NT:.nt=.ttl.gz)

PREFIXES_TTL := $(ROOT_DIR)/prefixes.ttl

PIGZ_JOBS := $(shell echo $$(( $(JOBS) > 4 ? 4 : $(JOBS) )))

%.ttl.gz: %.nt $(PREFIXES_TTL)
	rapper -i ntriples -o turtle $< 2>/dev/null | pigz -p $(PIGZ_JOBS) > $@
	@echo "Generated $@"

turtle: $(TURTLE_GZS)

# -----------------------
# Clean
# -----------------------
clean:
	rm -rf $(WORK_DIR)

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
# Core vocabulary fulltext
# eg. make fulltext_core
# -----------------------

# Build core QID → "core" group map from core_subjects.tsv (URI format)
$(FULLTEXT_CORE_MAP): $(CORE_QIDS) | $(WORK_DIR)
	sed 's|<http://www.wikidata.org/entity/||;s|>||g' $< \
	  | awk '{print $$1 "\tcore"}' > $@

# Single pass through fulltext GZ for all core concept QIDs
$(FULLTEXT_CORE_DONE): $(FULLTEXT_GZ) $(FULLTEXT_CORE_MAP) | $(FULLTEXT_DIR)
	python3 $(ROOT_DIR)/python/split_fulltext.py occs \
	  --map     $(FULLTEXT_CORE_MAP) \
	  --gz      $(FULLTEXT_GZ) \
	  --out-dir $(FULLTEXT_DIR) \
	  --date    $(RUN_DATE) \
	  --locale  $(LOCALE) \
	  --groups  core
	@touch $@

$(FULLTEXT_CORE_TSV): $(FULLTEXT_CORE_DONE) ;

fulltext_core: $(FULLTEXT_CORE_TSV)

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
$(FULLTEXT_CLASS_SPLIT_DONE): $(FULLTEXT_GZ) $(FULLTEXT_CLASS_INSTANCE_MAP) $(FULLTEXT_CLASS_QIDS_FILE) $(ALL_CLASS_FILES) | $(FULLTEXT_CLASS_QIDS_DIR)
	python3 $(ROOT_DIR)/python/split_fulltext.py classes \
	  --map     $(FULLTEXT_CLASS_INSTANCE_MAP) \
	  --qids    $(FULLTEXT_CLASS_QIDS_FILE) \
	  --gz      $(FULLTEXT_GZ) \
	  --out-dir $(FULLTEXT_CLASS_QIDS_DIR) \
	  --date    $(RUN_DATE) \
	  --locale  $(LOCALE)
	@touch $@

# Claim per-class-QID fulltext TSVs as outputs of the split
$(FULLTEXT_CLASS_QIDS_DIR)/wikicore-$(RUN_DATE)-%-$(LOCALE).tsv: $(FULLTEXT_CLASS_SPLIT_DONE)
	@[ -f $@ ] || touch $@

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
	cat $$^ > $$@
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
$(FULLTEXT_OCC_GROUP_MAP): $(Q5_OCC_GROUPED_FULL) | $(WORK_DIR)
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

# -----------------------
# P31_other fulltext
# eg. make fulltext_P31_other
# -----------------------

# Build QID → "other" map from P31_other.subjects.tsv
$(FULLTEXT_P31_OTHER_MAP): $(SUBJECTS_DONE) | $(WORK_DIR)
	sed 's|<http://www.wikidata.org/entity/||;s|>||g' $(SUBJECTS_DIR)/P31_other.subjects.tsv \
	  | awk '{print $$1 "\tother"}' > $@

$(FULLTEXT_P31_OTHER_DONE): $(FULLTEXT_GZ) $(FULLTEXT_P31_OTHER_MAP) | $(FULLTEXT_SUBJECTS_DIR)
	python3 $(ROOT_DIR)/python/split_fulltext.py occs \
	  --map     $(FULLTEXT_P31_OTHER_MAP) \
	  --gz      $(FULLTEXT_GZ) \
	  --out-dir $(FULLTEXT_SUBJECTS_DIR) \
	  --date    $(RUN_DATE) \
	  --locale  $(LOCALE) \
	  --groups  other
	@touch $@

$(FULLTEXT_P31_OTHER_TSV): $(FULLTEXT_P31_OTHER_DONE) ;

fulltext_P31_other: $(FULLTEXT_P31_OTHER_TSV)

# -----------------------
# Per-occupation-QID fulltext TSVs
# One TSV per active occupation QID, analogous to fulltext/classes/qids/
# -----------------------

# Build human-QID → occupation-QID mapping from per-QID subject files
$(FULLTEXT_OCC_QID_MAP): $(Q5_OCC_GROUPED_FULL) | $(WORK_DIR)
	@echo "Building occupation QID fulltext map..."
	@while IFS= read -r qid; do \
	    f="$(SUBJECTS_DIR)/$${qid}_subjects.tsv"; \
	    [ -f "$$f" ] && \
	      sed 's|<http://www.wikidata.org/entity/||;s|>||g' "$$f" \
	        | awk -v q="$$qid" '{print $$1 "\t" q}'; \
	done < $(ACTIVE_OCC_QIDS_FILE) | LC_ALL=C sort -u > $@

# Single pass through fulltext GZ: one TSV per occupation QID.
$(FULLTEXT_OCC_QIDS_DONE): $(FULLTEXT_GZ) $(FULLTEXT_OCC_QID_MAP) $(ACTIVE_OCC_QIDS_FILE) | $(FULLTEXT_OCC_QIDS_DIR)
	python3 $(ROOT_DIR)/python/split_fulltext.py occs \
	  --map     $(FULLTEXT_OCC_QID_MAP) \
	  --gz      $(FULLTEXT_GZ) \
	  --out-dir $(FULLTEXT_OCC_QIDS_DIR) \
	  --date    $(RUN_DATE) \
	  --locale  $(LOCALE) \
	  --groups  $(shell cat $(ACTIVE_OCC_QIDS_FILE))
	@touch $@

# Claim per-occ-QID fulltext TSVs as outputs of the split
$(FULLTEXT_OCC_QIDS_DIR)/wikicore-$(RUN_DATE)-%-$(LOCALE).tsv: $(FULLTEXT_OCC_QIDS_DONE) ;

# All occupation QID fulltext files
fulltext_occ_qids: $(FULLTEXT_OCC_QIDS_DONE)

# Specific occupation QID(s): make fulltext_occ_qid QIDS='Q33999 Q10800557'
OCC_QID_FULLTEXT_OUTS := $(foreach Q,$(QIDS),\
  $(FULLTEXT_OCC_QIDS_DIR)/wikicore-$(RUN_DATE)-$(Q)-$(LOCALE).tsv)

fulltext_occ_qid: $(OCC_QID_FULLTEXT_OUTS)

# -----------------------
# Annif project files
# -----------------------
ANNIF_DIR := $(ROOT_DIR)/annif

annif_projects: | $(ANNIF_DIR)
	python3 $(ROOT_DIR)/python/generate_annif_projects.py \
	  --date $(RUN_DATE) \
	  --lang $(LOCALE) \
	  --classes-dir $(ROOT_DIR)/classes \
	  --occs-dir $(ROOT_DIR)/occupations \
	  --outdir $(ANNIF_DIR)

$(ANNIF_DIR):
	mkdir -p $@

