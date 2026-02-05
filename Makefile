# -----------------------
# Wikidata processing pipeline (Makefile)
# -----------------------

SHELL := /bin/bash
.PHONY: all clean skos_subjects

# -----------------------
# Options
# -----------------------
LOCALE ?= en
JOBS ?= $(shell nproc)
SITELINKS ?= 0
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
OWL_CLASS_URI       = http://www.w3.org/2002/07/owl\#Class

SKOS_CORE_URI       = http://www.w3.org/2004/02/skos/core
SKOS_CONCEPT_URI    = http://www.w3.org/2004/02/skos/core\#Concept
SKOS_BROADER_URI    = http://www.w3.org/2004/02/skos/core\#broader
SKOS_CONCEPT_SCHEME_URI = http://www.w3.org/2004/02/skos/core\#ConceptScheme
SKOS_INSCHEME_URI     = http://www.w3.org/2004/02/skos/core\#inScheme

# -----------------------
# SKOS macros
# -----------------------
define emit_rdf_type
	{ \
	  echo "<$(1)> <$(RDF_TYPE_URI)> <$(OWL_CLASS_URI)> ."; \
	  sed -E 's|(.*)|\1 <$(RDF_TYPE_URI)> <$(1)> .|' $(2); \
	}
endef

define emit_skos_concepts
	sed -E 's|(.*)|\1 <$(RDF_TYPE_URI)> <$(SKOS_CONCEPT_URI)> .|' $(1)
endef

define emit_skos_concept_scheme
	{ \
	  echo "<$(1)> <$(RDF_TYPE_URI)> <$(SKOS_CONCEPT_SCHEME_URI)> ."; \
	  sed -E 's|(.*)|\1 <$(SKOS_INSCHEME_URI)> <$(1)> .|' $(2); \
	}
endef

define join_skos_labels
	pigz -dc $(1) \
	  | LC_ALL=C sort -u \
	  | LC_ALL=C join - $(2) \
	  > $@
endef

define emit_subject_skos
	@echo "=====> Generating SKOS for subject $(1)…"
	$(call emit_skos_concepts,$(2)) > $@
	$(call emit_skos_concept_scheme,$(3),$(2)) >> $@
	$(call join_skos_labels,$(SKOS_LABELS_GZ),$(2)) >> $@
endef

# -----------------------
# Default target
# -----------------------
FINAL_NT := $(ROOT_DIR)/wikicore-$(RUN_DATE)-$(LOCALE).nt
all: $(FINAL_NT)

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
#    Filter through Wikipedia sitelinks
# -----------------------
$(CORE_NOSUBJECT_QIDS): $(CORE_CONCEPTS_QIDS) $(SUBJECTS_SORTED)
	@echo "=====> Filtering out P31 instances…"
	LC_ALL=C join -t '	' -1 1 -2 1 -v 1 $< $(SUBJECTS_SORTED) \
	 | LC_ALL=C join <(awk '{print $$1}' $(SOURCE_DIR)/sitelinks_en_qids.tsv) - \
	 | LC_ALL=C sort -u \
	 > $@

# -----------------------
# 7. Generate SKOS triples
# -----------------------
$(SKOS_DIR)/%.nt: $(CORE_NOSUBJECT_QIDS) | $(SKOS_DIR)

$(SKOS_CONCEPTS): $(CORE_NOSUBJECT_QIDS)
	$(call emit_skos_concepts,$(CORE_NOSUBJECT_QIDS)) > $@

$(SKOS_CONCEPT_SCHEME): $(CORE_NOSUBJECT_QIDS)
	$(call emit_skos_concept_scheme,$(VOCAB_URI),$(CORE_NOSUBJECT_QIDS)) > $@

$(SKOS_LABELS): $(CORE_NOSUBJECT_QIDS) $(SKOS_LABELS_GZ)
	@echo "=====> Joining SKOS labels with core concepts…"
	$(call join_skos_labels,$(SKOS_LABELS_GZ),$(CORE_NOSUBJECT_QIDS)) > $@
	
# Filter out subject entities
$(SKOS_BROADER): $(CONCEPT_BACKBONE) $(CORE_NOSUBJECT_QIDS) | $(SKOS_DIR)
	@echo "=====> Filtering backbone triples and applying SKOS broader URI…"
	LC_ALL=C join $(CONCEPT_BACKBONE) $(CORE_NOSUBJECT_QIDS) \
	  | sed -E 's|<[^>]+>|<$(SKOS_BROADER_URI)>|2' \
	  > $@

$(FINAL_NT): $(SKOS_NT)
	@echo "=====> Merging SKOS N-Triples…"
	cat $^ > $@

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

SUBJECTS ?= Q5

SUBJECT_OUTS := $(foreach S,$(SUBJECTS),\
  $(ROOT_DIR)/wikicore-$(RUN_DATE)-$(S)-$(LOCALE).nt)

skos_subjects: $(SUBJECT_OUTS)

$(WORK_DIR)/%_filtered.tsv: $(SUBJECTS_DIR)/%_subjects.tsv
	LC_ALL=C join <(awk '{print $$1}' $(SOURCE_DIR)/sitelinks_en_qids.tsv) $< \
	| LC_ALL=C sort -u \
	> $@

# Intermediate: generate label triples for a subject
$(SKOS_DIR)/skos_labels_%_$(LOCALE).nt: \
	$(WORK_DIR)/%_filtered.tsv \
	$(SKOS_LABELS_GZ)
	$(call join_skos_labels,$(SKOS_LABELS_GZ),$<)

# Intermediate: generate SKOS concept triples
$(SKOS_DIR)/skos_concepts_%_$(LOCALE).nt: \
	$(WORK_DIR)/%_filtered.tsv
	@echo "=====> Generating SKOS concepts for subject $*…"
	@if [ ! -f "$<" ]; then \
	  echo "ERROR: Subject file $< missing"; exit 1; \
	fi
	$(call emit_skos_concepts,$<) > $@

# Intermediate: generate SKOS concept scheme triples
$(SKOS_DIR)/skos_concept_scheme_%_$(LOCALE).nt: \
	$(WORK_DIR)/%_filtered.tsv
	@echo "=====> Generating SKOS concept scheme for subject $*…"
	@if [ ! -f "$<" ]; then \
	  echo "ERROR: Subject file $< missing"; exit 1; \
	fi
	$(call emit_skos_concept_scheme,$(VOCAB_URI)/subject/$*,$<) > $@

.SECONDARY:

$(ROOT_DIR)/wikicore-$(RUN_DATE)-%-$(LOCALE).nt: \
	$(SKOS_DIR)/skos_concepts_%_$(LOCALE).nt \
	$(SKOS_DIR)/skos_concept_scheme_%_$(LOCALE).nt \
	$(SKOS_DIR)/skos_labels_%_$(LOCALE).nt
	@echo "=====> Combining SKOS for subject $*…"
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