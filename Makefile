# -----------------------
# Wiki Core processing pipeline
# -----------------------

SHELL := /bin/bash
.PHONY: all clean skos_subjects verify

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
BUCKETS_DIR      := $(WORK_DIR)/buckets_qid

# -----------------------
# Inputs
# -----------------------
PROP_DIRECT_GZ   := $(SOURCE_DIR)/wikidata-20251229-propdirect.nt.gz
SKOS_LABELS_GZ   := $(SOURCE_DIR)/wikidata-20251229-skos-labels-$(LOCALE).nt.gz
SITELINKS_FILE   := $(SOURCE_DIR)/sitelinks_$(LOCALE)_qids.tsv

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
CONCEPT_BACKBONE    := $(WORK_DIR)/concept_backbone.nt
CORE_CONCEPTS_QIDS  := $(WORK_DIR)/core_concepts_qids.tsv
CORE_NOSUBJECT_QIDS := $(WORK_DIR)/core_nosubject_qids.tsv
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
$(WORK_DIR) $(SPLIT_DIR) $(JENA_DIR) $(SUBJECTS_DIR) $(SKOS_DIR) $(BUCKETS_DIR):
	mkdir -p $@

# -----------------------
# 1. Extract core properties
# -----------------------
$(CORE_PROPS_NT): $(PROP_DIRECT_GZ) | $(WORK_DIR)
	@echo "========================================"
	@echo "Step 1: Extracting core properties (P31, P279, P361)..."
	@echo "========================================"
	pigz -dc $(PROP_DIRECT_GZ) \
	  | rg -F -e '/prop/direct/P31>' -e '/prop/direct/P279>' -e '/prop/direct/P361>' \
	  | rg -F -v '_:' \
	  > $@
	@echo "✓ Done: $@"
	@wc -l $@

# -----------------------
# 2. Split core properties into chunks
# -----------------------
SPLIT_DONE := $(SPLIT_DIR)/.split_done

$(SPLIT_DONE): $(CORE_PROPS_NT) | $(SPLIT_DIR)
	@echo "========================================"
	@echo "Step 2: Splitting into $(JOBS) chunks..."
	@echo "========================================"
	gsplit -n l/$(JOBS) $(CORE_PROPS_NT) $(SPLIT_DIR)/chunk_
	@touch $@
	@echo "✓ Done: $(SPLIT_DIR)/chunk_*"
	@ls -lh $(SPLIT_DIR)/chunk_* | head -5
	@echo "... (showing first 5 of $(JOBS) chunks)"

# -----------------------
# 3. Extract backbone (P279/P361 only)
# -----------------------
# Extract ONLY the backbone (subclass and part-of relationships)
# We don't partition instances yet - that happens after bucket generation

$(CONCEPT_BACKBONE): $(SPLIT_DONE) | $(WORK_DIR)
	@echo "========================================"
	@echo "Step 3: Extracting backbone (P279/P361 only)..."
	@echo "========================================"
	python3 $(ROOT_DIR)/extract_backbone.py \
	    $(SPLIT_DIR) \
	    $@
	@echo "✓ Done: $@"
	@wc -l $@

# -----------------------
# 4. Load backbone into Jena
# -----------------------
$(JENA_DIR)/tdb2_loaded: $(CONCEPT_BACKBONE) | $(JENA_DIR)
	@echo "========================================"
	@echo "Step 4: Loading backbone into Jena TDB2..."
	@echo "========================================"
	@echo "This may take several minutes for large datasets..."
	tdb2.tdbloader --loc $(JENA_DIR) $(CONCEPT_BACKBONE)
	@touch $@
	@echo "✓ Done: Jena TDB2 database at $(JENA_DIR)"

# -----------------------
# 5. Materialize + export core concepts
# -----------------------
$(CORE_CONCEPTS_QIDS): $(JENA_DIR)/tdb2_loaded
	@echo "========================================"
	@echo "Step 5: Materializing graph and exporting core concepts..."
	@echo "========================================"
	@echo "5a. Materializing ancestors (transitive closure)..."
	tdb2.tdbupdate --loc $(JENA_DIR) --update="$(QUERIES_DIR)/materialize_ancestors.rq"
	@echo "5b. Materializing child counts..."
	tdb2.tdbupdate --loc $(JENA_DIR) --update="$(QUERIES_DIR)/materialize_child_counts.rq"
	@echo "5c. Exporting core concepts..."
	tdb2.tdbquery  --loc $(JENA_DIR) --query="$(QUERIES_DIR)/export.rq" --results=TSV \
	  | grep -F '<http://www.wikidata.org/entity/' \
	  | LC_ALL=C sort -u \
	  > $@
	@echo "✓ Done: $@"
	@wc -l $@

# -----------------------
# 6. Generate buckets from backbone
# -----------------------
# This discovers top-level buckets and generates bucket files
# Root entity can be customized with ROOT_QID variable

ROOT_QID ?= Q35120
BUCKETS_DONE := $(BUCKETS_DIR)/.buckets_done

$(BUCKETS_DONE): $(JENA_DIR)/tdb2_loaded | $(BUCKETS_DIR)
	@echo "========================================"
	@echo "Step 6: Generating buckets from backbone..."
	@echo "        Root entity: $(ROOT_QID)"
	@echo "========================================"
	python3 $(ROOT_DIR)/generate_buckets.py \
	    $(JENA_DIR) \
	    $(QUERIES_DIR) \
	    $(BUCKETS_DIR) \
	    $(ROOT_QID)
	@touch $@
	@echo "✓ Done: Bucket files in $(BUCKETS_DIR)"
	@ls -lh $(BUCKETS_DIR)/*.tsv | wc -l | xargs echo "Bucket files created:"

# Claim bucket files as products of bucket generation
$(BUCKETS_DIR)/%.tsv: $(BUCKETS_DONE) ;

# -----------------------
# 7. Partition instances into buckets
# -----------------------
# Now that we have buckets, partition P31 instances
# (with early sitelinks filtering)

$(SUBJECTS_DIR)/.partition_done: $(SPLIT_DONE) $(BUCKETS_DONE) $(SITELINKS_FILE) | $(SUBJECTS_DIR)
	@echo "========================================"
	@echo "Step 7: Partitioning instances into buckets..."
	@echo "        (filtering by sitelinks)"
	@echo "========================================"
	@echo "Using buckets from: $(BUCKETS_DIR)"
	@ls $(BUCKETS_DIR)/*.tsv | wc -l | xargs echo "Bucket files found:"
	python3 $(ROOT_DIR)/partition_instances.py \
	    $(SPLIT_DIR) \
	    $(BUCKETS_DIR) \
	    $(SITELINKS_FILE) \
	    $(SUBJECTS_DIR)
	@touch $@
	@echo "✓ Done: $(SUBJECTS_DIR)/*_subjects.tsv"
	@ls -lh $(SUBJECTS_DIR)/*_subjects.tsv | wc -l | xargs echo "Subject files created:"

# Claim subject files as products of partitioning
$(SUBJECTS_DIR)/%_subjects.tsv: $(SUBJECTS_DIR)/.partition_done ;

# -----------------------
# 8. Prepare subject vocabularies
# -----------------------
SUBJECTS_SORTED := $(SUBJECTS_DIR)/subjects_sorted.tsv
SUBJECTS_DONE   := $(SUBJECTS_DIR)/.subjects_individually_sorted

# Sort and deduplicate each per-subject TSV
$(SUBJECTS_DONE): $(SUBJECTS_DIR)/.partition_done
	@echo "========================================"
	@echo "Step 8: Sorting and deduplicating subject files..."
	@echo "========================================"
	parallel -j $(JOBS) --bar --halt now,fail=1 'LC_ALL=C sort -u -o {1} {1}' ::: $(SUBJECTS_DIR)/*_subjects.tsv
	@touch $@
	@echo "✓ Done: All subject files sorted and deduplicated"

# Claim per-subject TSVs as outputs of SUBJECTS_DONE
$(SUBJECTS_DIR)/%_subjects.tsv: $(SUBJECTS_DONE) ;

# Merge all per-subject files into a single sorted, deduplicated file
#
# NB: to exclude P31_other,          use "$(SUBJECTS_DIR)/Q*_subjects.tsv"
#     to include P31_other.tsv,      use "$(SUBJECTS_DIR)/*_subjects.tsv"
$(SUBJECTS_SORTED): $(SUBJECTS_DONE)
	@echo "========================================"
	@echo "Step 8b: Merging all subject files..."
	@echo "========================================"
	LC_ALL=C sort -m -u $(SUBJECTS_DIR)/*_subjects.tsv > $@
	@echo "✓ Done: $@"
	@wc -l $@

# Filter out subjects from core concepts
# (Concepts that appear as subjects/instances are removed from the vocabulary)
$(CORE_NOSUBJECT_QIDS): $(CORE_CONCEPTS_QIDS) $(SUBJECTS_SORTED) | $(WORK_DIR)
	@echo "========================================"
	@echo "Step 8c: Filtering concepts (removing subjects)..."
	@echo "========================================"
	@echo "Before filtering:" $$(wc -l < $(CORE_CONCEPTS_QIDS)) "concepts"
	LC_ALL=C join -v 1 $< $(SUBJECTS_SORTED) > $@
	@echo "After filtering: " $$(wc -l < $@) "concepts"
	@echo "✓ Done: $@"

# -----------------------
# 9. Generate SKOS triples
# -----------------------

# Extract localized labels (for re-use)
$(SKOS_LABELS_NT): $(SKOS_LABELS_GZ) | $(WORK_DIR)
	@echo "========================================"
	@echo "Step 9: Extracting SKOS labels..."
	@echo "========================================"
	pigz -dc $(SKOS_LABELS_GZ) > $@
	@echo "✓ Done: $@"
	@wc -l $@

# Join labels with core QIDs
$(SKOS_LABELS): $(SKOS_LABELS_NT) $(CORE_NOSUBJECT_QIDS) | $(SKOS_DIR)
	@echo "========================================"
	@echo "Step 9a: Filtering labels for core concepts..."
	@echo "========================================"
	awk 'NR==FNR { core[$$1]; next } $$1 in core && !seen[$$0]++ { print }' \
	  $(CORE_NOSUBJECT_QIDS) $(SKOS_LABELS_NT) > $@
	@echo "✓ Done: $@"
	@wc -l $@

# Concept statements (one per core QID)
$(SKOS_CONCEPTS): $(CORE_NOSUBJECT_QIDS) | $(SKOS_DIR)
	@echo "========================================"
	@echo "Step 9b: Generating SKOS concept statements..."
	@echo "========================================"
	awk -v type="$(RDF_TYPE_URI)" -v concept="$(SKOS_CONCEPT_URI)" \
	  '!seen[$$1]++ { print $$1, "<" type ">", "<" concept ">", "." }' $< > $@
	@echo "✓ Done: $@"
	@wc -l $@

# Concept Scheme aggregation
$(SKOS_CONCEPT_SCHEME): $(CORE_NOSUBJECT_QIDS) | $(SKOS_DIR)
	@echo "========================================"
	@echo "Step 9c: Generating SKOS concept scheme..."
	@echo "========================================"
	@echo "<$(VOCAB_URI)> <$(RDF_TYPE_URI)> <$(SKOS_CONCEPT_SCHEME_URI)> ." > $@
	awk -v inscheme="$(SKOS_INSCHEME_URI)" -v vocab="$(VOCAB_URI)" \
	  '!seen[$$1]++ { print $$1, "<" inscheme ">", "<" vocab ">", "." }' $< >> $@
	@echo "✓ Done: $@"
	@wc -l $@

# Broader statements
$(SKOS_BROADER): $(CORE_NOSUBJECT_QIDS) | $(SKOS_DIR)
	@echo "========================================"
	@echo "Step 9d: Generating SKOS broader statements..."
	@echo "========================================"
	LC_ALL=C sort -u $(CONCEPT_BACKBONE) \
	  | LC_ALL=C join $(CORE_NOSUBJECT_QIDS) - \
	  | awk -v broader="$(SKOS_BROADER_URI)" '{ print $$1 " <" broader "> " $$3 " ." }' \
	  > $@
	@echo "✓ Done: $@"
	@wc -l $@

# -----------------------
# 10. Merge SKOS to output NT
# -----------------------
$(FINAL_NT): $(SKOS_CONCEPTS) $(SKOS_CONCEPT_SCHEME) $(SKOS_LABELS) $(SKOS_BROADER)
	@echo "========================================"
	@echo "Step 10: Merging SKOS outputs into final vocabulary..."
	@echo "========================================"
	cat $^ > $@
	@echo "✓ Done: $@"
	@echo ""
	@echo "========================================"
	@echo "FINAL VOCABULARY STATISTICS"
	@echo "========================================"
	@wc -l $@
	@echo "Concepts:      " $$(wc -l < $(SKOS_CONCEPTS))
	@echo "Labels:        " $$(wc -l < $(SKOS_LABELS))
	@echo "Broader:       " $$(wc -l < $(SKOS_BROADER))
	@echo "ConceptScheme: " $$(wc -l < $(SKOS_CONCEPT_SCHEME))
	@echo "========================================"

# -----------------------
# Verification target
# -----------------------
verify:
	@echo "========================================"
	@echo "VERIFICATION CHECKS"
	@echo "========================================"
	@if [ -f "$(FINAL_NT)" ]; then \
		echo "✓ Final vocabulary exists: $(FINAL_NT)"; \
		echo "  Size: $$(du -h $(FINAL_NT) | cut -f1)"; \
		echo "  Lines: $$(wc -l < $(FINAL_NT))"; \
	else \
		echo "✗ Final vocabulary not found: $(FINAL_NT)"; \
	fi
	@echo ""
	@if [ -d "$(SUBJECTS_DIR)" ]; then \
		echo "✓ Subject files:"; \
		echo "  Count: $$(ls $(SUBJECTS_DIR)/*_subjects.tsv 2>/dev/null | wc -l)"; \
		echo "  Total instances: $$(cat $(SUBJECTS_DIR)/*_subjects.tsv 2>/dev/null | sort -u | wc -l)"; \
	fi
	@echo ""
	@if [ -f "$(CONCEPT_BACKBONE)" ]; then \
		echo "✓ Backbone exists:"; \
		echo "  P279 triples: $$(grep -c 'P279>' $(CONCEPT_BACKBONE))"; \
		echo "  P361 triples: $$(grep -c 'P361>' $(CONCEPT_BACKBONE))"; \
	fi
	@echo "========================================"

# -----------------------
# Clean
# -----------------------
clean:
	@echo "Cleaning working directory..."
	rm -rf $(WORK_DIR)
	@echo "✓ Done"

clean-all: clean
	@echo "Cleaning output files..."
	rm -f $(ROOT_DIR)/wikicore-*-$(LOCALE).nt
	@echo "✓ Done"

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

# Note: We don't need to filter by sitelinks here because the subjects
# were already filtered during partitioning in step 3
$(WORK_DIR)/%_filtered.tsv: $(SUBJECTS_DIR)/%_subjects.tsv | $(WORK_DIR)
	@echo "Preparing filtered subjects for $*..."
	@# Subjects are already filtered by sitelinks, just copy
	cp $< $@

$(SKOS_DIR)/skos_%_concepts.nt: $(WORK_DIR)/%_filtered.tsv | $(SKOS_DIR)
	@echo "Generating SKOS concepts for $*..."
	awk -v type="$(RDF_TYPE_URI)" -v concept="$(SKOS_CONCEPT_URI)" \
	  '!seen[$$1]++ { print $$1, "<" type ">", "<" concept ">", "." }' $< > $@

$(SKOS_DIR)/skos_%_concept_scheme.nt: $(WORK_DIR)/%_filtered.tsv | $(SKOS_DIR)
	@echo "Generating SKOS concept scheme for $*..."
	@echo "<$(VOCAB_URI)> <$(RDF_TYPE_URI)> <$(SKOS_CONCEPT_SCHEME_URI)> ." > $@
	awk -v inscheme="$(SKOS_INSCHEME_URI)" -v vocab="$(VOCAB_URI)" \
	  '!seen[$$1]++ { print $$1, "<" inscheme ">", "<" vocab ">", "." }' $< >> $@

$(SKOS_DIR)/skos_%_labels_$(LOCALE).nt: \
	$(SKOS_LABELS_NT) $(WORK_DIR)/%_filtered.tsv | $(SKOS_DIR)
	@echo "Generating SKOS labels for $*..."
	awk 'NR==FNR { core[$$1]; next } $$1 in core && !seen[$$0]++ { print }' \
	  $(WORK_DIR)/$*_filtered.tsv $(SKOS_LABELS_NT) > $@

$(ROOT_DIR)/wikicore-$(RUN_DATE)-%-$(LOCALE).nt: \
	$(SKOS_DIR)/skos_%_concepts.nt \
	$(SKOS_DIR)/skos_%_concept_scheme.nt \
	$(SKOS_DIR)/skos_%_labels_$(LOCALE).nt
	@echo "Merging SKOS outputs for $*..."
	cat $^ > $@
	@echo "✓ Done: $@"
	@wc -l $@

# -----------------------
# Help target
# -----------------------
help:
	@echo "Wiki Core Makefile"
	@echo ""
	@echo "Available targets:"
	@echo "  make all            - Build complete Wiki Core vocabulary"
	@echo "  make verify         - Verify output and show statistics"
	@echo "  make clean          - Remove working files"
	@echo "  make clean-all      - Remove working files and outputs"
	@echo "  make skos_subjects  - Generate subject-specific vocabularies"
	@echo "  make help           - Show this help message"
	@echo ""
	@echo "Options:"
	@echo "  LOCALE=<lang>       - Language for labels (default: en)"
	@echo "  JOBS=<n>            - Number of parallel jobs (default: nproc)"
	@echo "  SUBJECTS=<QID>      - Subject QID for skos_subjects (default: Q5)"
	@echo "  ROOT_QID=<QID>      - Root entity for bucket discovery (default: Q35120)"
	@echo ""
	@echo "Pipeline stages:"
	@echo "  1. Extract core properties (P31/P279/P361)"
	@echo "  2. Split into chunks for parallel processing"
	@echo "  3. Extract backbone (P279/P361 only)"
	@echo "  4. Load backbone into Jena TDB2"
	@echo "  5. Materialize ancestors and export concepts"
	@echo "  6. Generate buckets from backbone (discovers top-level classes)"
	@echo "  7. Partition instances into buckets (with sitelinks filter)"
	@echo "  8. Sort and merge subject files"
	@echo "  9. Generate SKOS triples"
	@echo "  10. Merge into final vocabulary"
	@echo ""
	@echo "Examples:"
	@echo "  make all LOCALE=en JOBS=16"
	@echo "  make all ROOT_QID=Q16521"
	@echo "  make skos_subjects SUBJECTS='Q5 Q215627'"
	@echo "  make verify"

