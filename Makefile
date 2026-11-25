SHELL := /bin/bash
.SHELLFLAGS := -euo pipefail -c
.PHONY: default data download vocab fulltext annif config load train eval optimize compress decompress stats sankey

# Options
LOCALE    ?= en
# Cross-lingual vocab fallback: concepts present in the FALLBACK_LOCALE corpus
# (default en) are kept in the $(LOCALE) vocabulary with their fr/mul labels even
# when no $(LOCALE) document exists (they stay untrained). Set to empty to disable:
#   make data LOCALE=fr FALLBACK_LOCALE=
FALLBACK_LOCALE ?= en
BACKEND   ?= mllm
RUN_DATE  ?= $(shell date +%Y%m%d)
VOCAB_URI := https://wikicore.ca/$(RUN_DATE)
# Union of locales to scan for sitelinks; sort dedupes when FALLBACK == LOCALE
SITE_LOCALES := $(if $(FALLBACK_LOCALE),$(sort $(FALLBACK_LOCALE) $(LOCALE)),$(LOCALE))
# Published Content File Export to use: the 1st of the RUN_DATE month, so a
# RUN_DATE mid-month points at an export that may not be published yet
# (published ~7 days after the 1st). Override to pin one, eg.:
#   make download EXPORT_DATE=2026-11-01
EXPORT_DATE ?= $(shell echo $(RUN_DATE) | awk '{print substr($$0,1,4)"-"substr($$0,5,2)"-01"}')

# Paths
ROOT_DIR         := $(PWD)
ANNIF            ?= $(ROOT_DIR)/../Annif.nosync/.venv/bin/annif
SOURCE_DIR       := $(ROOT_DIR)/source.nosync
WORK_DIR         := $(ROOT_DIR)/working.nosync
OUT_DIR          := $(ROOT_DIR)/wikicore-$(RUN_DATE)-$(LOCALE)
OCCUPATION_FILES := $(wildcard $(ROOT_DIR)/occupation/*.tsv)
CLASS_FILES      := $(wildcard $(ROOT_DIR)/class/*.tsv)

# Input dumps
# NB: very large! A full Wikidata RDF dump (latest-all.nt.gz) is >1TB uncompressed
# and must be downloaded & placed in $(SOURCE_DIR) manually; override the path here:
#   make data LOCALE=fr WIKIDATA_GZ=$(SOURCE_DIR)/wikidata-<date>-all.nt.gz
# NB: truthy dumps (wikidata-<date>-truthy-BETA.nt.gz) contain NO Wikipedia
# sitelinks and will yield an empty sitelinks map / corpus.
WIKIDATA_GZ      ?= $(SOURCE_DIR)/wikidata-20260824-all-BETA.nt.gz

# Wikipedia dumps: new-style MediaWiki Content File Exports, one *directory* of
# standalone part XML files per wiki & date (legacy single-file dumps sunset 2027-01):
#   https://dumps.wikimedia.org/other/mediawiki_content_current/<wiki_id>/<date>/xml/bzip2/
# The directory name (<wiki_id>-<date>, eg. frwiki-2026-11-01) resolves both the URI
# and the download target. 'make download' fetches SHA256SUMS, then all parts
# (resumable), then verifies; see the .complete stamp rule below. You can also wget
# the parts yourself and run 'make download' afterwards to verify the export.
# Exports now live one directory PER LANGUAGE ($(SOURCE_DIR)/<LOCALE>/, eg. fr/),
# with the export date inside as files; <wiki_id>-<date> names keep working while
# older in-flight exports exist.
WIKIPEDIA_HOST    := https://dumps.wikimedia.org
# Wikipedia wiki_id: <LOCALE>wiki (eg. frwiki); LOCALE stays separate from RUN_DATE
WIKIPEDIA_WIKI_ID ?= $(LOCALE)wiki
WIKIPEDIA_DATE    := $(EXPORT_DATE)
WIKIPEDIA_URI     := $(WIKIPEDIA_HOST)/other/mediawiki_content_current/$(WIKIPEDIA_WIKI_ID)/$(WIKIPEDIA_DATE)/xml/bzip2
WIKIPEDIA_DIR     := $(firstword $(wildcard $(SOURCE_DIR)/$(LOCALE) $(SOURCE_DIR)/$(WIKIPEDIA_WIKI_ID)-$(WIKIPEDIA_DATE)))
ifeq ($(WIKIPEDIA_DIR),)
WIKIPEDIA_DIR     := $(SOURCE_DIR)/$(LOCALE)
endif
WIKIPEDIA_PARTS   := $(wildcard $(WIKIPEDIA_DIR)/*.xml.bz2 $(WIKIPEDIA_DIR)/$(WIKIPEDIA_WIKI_ID)-$(WIKIPEDIA_DATE)-*.xml.bz2)
WIKIPEDIA_STAMP   := $(WIKIPEDIA_DIR)/.complete
SHASUM            := $(shell command -v sha256sum || command -v shasum)
# Apple's sha256sum has no -a option; perl's shasum defaults to SHA-1, so it needs -a 256
SHASUM_OPT        := $(if $(findstring shasum,$(notdir $(SHASUM))),-a 256,)

# Extracted files
# Union sitelinks map: $(FALLBACK_LOCALE) + $(LOCALE), scanned in one dump pass;
# $1 = QID URI, $2 = sitelink URL (angle brackets preserved)
UNION_SITELINKS  := $(WORK_DIR)/wikicore-sitelinks-union.tsv
SITELINKS_MAP    := $(WORK_DIR)/$(LOCALE)wiki_sitelinks.tsv
WIKIDATA_NT      := $(WORK_DIR)/$(LOCALE)wiki_wikidata.nt
WIKIPEDIA_TSV    := $(WORK_DIR)/$(LOCALE)wiki_corpus.tsv
WORK_CORPUS      := $(WORK_DIR)/$(LOCALE)wiki-parts
CORPUS_PARTS     := $(patsubst $(WIKIPEDIA_DIR)/%.xml.bz2,$(WORK_CORPUS)/%.tsv,$(WIKIPEDIA_PARTS))

# SKOS files
SKOS_LABELS_NT   := $(WORK_DIR)/wikicore-skos-labels-$(LOCALE).nt
PROPS_P31_NT     := $(WORK_DIR)/wikicore-P31.nt
PROPS_P106_NT    := $(WORK_DIR)/wikicore-P106.nt
PROPS_P279_NT    := $(WORK_DIR)/wikicore-P279.nt
PROPS_P361_NT    := $(WORK_DIR)/wikicore-P361.nt
OUT_VOCAB        := $(OUT_DIR)/vocab

# JSONL Fulltext files
WORK_FULLTEXT    := $(WORK_DIR)/fulltext
OUT_FULLTEXT     := $(OUT_DIR)/fulltext

# Annif files
ANNIF_DATADIR    := $(OUT_DIR)/data
ANNIF_PROJECTS   := $(OUT_DIR)/projects.d
ANNIF_VOCABS     := $(ANNIF_DATADIR)/vocabs
ANNIF_MODELS     := $(ANNIF_DATADIR)/projects
ANNIF_EVAL       := $(ANNIF_DATADIR)/eval
ANNIF_STAMP      := .trained
export ANNIF_DATADIR

# Default (help) target
default:
	@echo "-----------------"
	@echo "Wiki Core toolkit"
	@echo "-----------------"
	@echo "Usage: make [TARGET] [-j N] [OPTIONS]"
	@echo "	eg. make annif -j 4 LOCALE=fr BACKEND=omikuji"
	@echo ""
	@echo "Targets:"
	@echo "data"
	@echo "	vocab		Generate Wikidata SKOS vocabs (.nt)"
	@echo "	fulltext	Generate JSONL text splits (.jsonl)"
	@echo "	stats		Generate statistics (.tsv)"
	@echo "	sankey		Generate Sankey diagram data (.txt)"
	@echo ""
	@echo "annif"
	@echo "	config		Generate Annif project configs (.cfg)"
	@echo "	load		Load vocabs into Annif"
	@echo "	train		Train Annif projects"
	@echo "optimize		Optimize Annif projects (.tsv)"
	@echo "eval			Evaluate Annif projects (.json)"
	@echo ""
	@echo "download		Fetch & verify the $(LOCALE)wiki export ($(WIKIPEDIA_DATE))"
	@echo "compress		Compress files for Github (.gz)"
	@echo "decompress		Extract files from Github"
	@echo ""
	@echo "Options:"
	@echo "	-j N		Number of parallel jobs ('-j' alone means all CPUs)"
	@echo "	RUN_DATE	Default '$(RUN_DATE)' (eg. YYYYMMDD)"
	@echo "	LOCALE		Default '$(LOCALE)'"
	@echo "	EXPORT_DATE	Default '$(WIKIPEDIA_DATE)'"
	@echo "	FALLBACK_LOCALE	Default '$(FALLBACK_LOCALE)' (empty disables union vocab)"
	@echo "	BACKEND		Default 'mllm'"
	@echo "	ANNIF		Default '$(ANNIF)'"
	@echo ""

# Data targets
#    Time: 2h on M4/10
data:		vocab fulltext stats sankey
			@echo "  LOCALE=$(LOCALE)"
			@echo "  RUN_DATE=$(RUN_DATE)"

vocab:		$(OUT_VOCAB)/core.nt \
			$(patsubst $(ROOT_DIR)/class/%.tsv,$(OUT_VOCAB)/class/%.nt,$(CLASS_FILES)) \
			$(patsubst $(ROOT_DIR)/occupation/%.tsv,$(OUT_VOCAB)/occupation/%.nt,$(OCCUPATION_FILES))

fulltext: 	$(OUT_FULLTEXT)/core.jsonl \
			$(patsubst $(ROOT_DIR)/class/%.tsv,$(OUT_FULLTEXT)/class/%.jsonl,$(CLASS_FILES)) \
			$(patsubst $(ROOT_DIR)/occupation/%.tsv,$(OUT_FULLTEXT)/occupation/%.jsonl,$(OCCUPATION_FILES)) \

stats:		$(OUT_DIR)/stats.tsv

sankey:		$(OUT_DIR)/sankey.txt

# Annif targets
annif:		config load train
			@echo "  LOCALE=$(LOCALE)"
			@echo "  RUN_DATE=$(RUN_DATE)"
			@echo "  BACKEND=$(BACKEND)"

config:		$(ANNIF_PROJECTS)/wikicore_$(LOCALE)_$(BACKEND)_core.cfg \
			$(patsubst $(ROOT_DIR)/class/%.tsv,$(ANNIF_PROJECTS)/wikicore_$(LOCALE)_$(BACKEND)_class_%.cfg,$(CLASS_FILES)) \
			$(patsubst $(ROOT_DIR)/occupation/%.tsv,$(ANNIF_PROJECTS)/wikicore_$(LOCALE)_$(BACKEND)_occupation_%.cfg,$(OCCUPATION_FILES)) \
			$(ANNIF_PROJECTS)/wikicore_$(LOCALE)_ensemble_class.cfg \
			$(ANNIF_PROJECTS)/wikicore_$(LOCALE)_ensemble_occupation.cfg \
			$(ANNIF_PROJECTS)/wikicore_$(LOCALE)_ensemble_all.cfg \

# TODO: load does not include occupation / class / all
# NB: "annif load" uses > 30GB of RAM for parsing the full RDF of 'all'
# this is required (eg. as opposed to combining CSV) to maintain skos:inScheme triples
load:		$(ANNIF_VOCABS)/wikicore-$(RUN_DATE)-core-$(LOCALE)/subjects.ttl \
			$(patsubst $(ROOT_DIR)/class/%.tsv,$(ANNIF_VOCABS)/wikicore-$(RUN_DATE)-class-%-$(LOCALE)/subjects.ttl,$(CLASS_FILES)) \
			$(patsubst $(ROOT_DIR)/occupation/%.tsv,$(ANNIF_VOCABS)/wikicore-$(RUN_DATE)-occupation-%-$(LOCALE)/subjects.ttl,$(OCCUPATION_FILES)) \

train:		$(ANNIF_MODELS)/wikicore_$(LOCALE)_$(BACKEND)_core/$(ANNIF_STAMP) \
			$(patsubst $(ROOT_DIR)/class/%.tsv,$(ANNIF_MODELS)/wikicore_$(LOCALE)_$(BACKEND)_class_%/$(ANNIF_STAMP),$(CLASS_FILES)) \
			$(patsubst $(ROOT_DIR)/occupation/%.tsv,$(ANNIF_MODELS)/wikicore_$(LOCALE)_$(BACKEND)_occupation_%/$(ANNIF_STAMP),$(OCCUPATION_FILES))

eval:		$(ANNIF_EVAL)/wikicore_$(LOCALE)_$(BACKEND)_core.json \
			$(patsubst $(ROOT_DIR)/class/%.tsv,$(ANNIF_EVAL)/wikicore_$(LOCALE)_$(BACKEND)_class_%.json,$(CLASS_FILES)) \
			$(patsubst $(ROOT_DIR)/occupation/%.tsv,$(ANNIF_EVAL)/wikicore_$(LOCALE)_$(BACKEND)_occupation_%.json,$(OCCUPATION_FILES)) \

optimize:	$(ANNIF_EVAL)/wikicore_$(LOCALE)_$(BACKEND)_core.tsv \
			$(patsubst $(ROOT_DIR)/class/%.tsv,$(ANNIF_EVAL)/wikicore_$(LOCALE)_$(BACKEND)_class_%.tsv,$(CLASS_FILES)) \
			$(patsubst $(ROOT_DIR)/occupation/%.tsv,$(ANNIF_EVAL)/wikicore_$(LOCALE)_$(BACKEND)_occupation_%.tsv,$(OCCUPATION_FILES)) \

# Github GZip targets / Dump downloads
download:
	@if [ -f $(WIKIPEDIA_STAMP) ]; then \
		echo "  Export: already verified ($(WIKIPEDIA_STAMP) present); skipping wget"; \
	else \
		echo "  Export: $(WIKIPEDIA_URI)"; \
		mkdir -p $(WIKIPEDIA_DIR); \
		wget -q -O $(WIKIPEDIA_DIR)/SHA256SUMS $(WIKIPEDIA_URI)/SHA256SUMS; \
	fi
	cd $(WIKIPEDIA_DIR) && $(SHASUM) $(SHASUM_OPT) --check SHA256SUMS
	@if [ -f $(WIKIPEDIA_DIR)/SHA256SUMS ] || [ -f $@ ]; then touch $(WIKIPEDIA_STAMP); fi

compress: $(OUT_VOCAB) $(OUT_FULLTEXT)
	# Vocabularies
	find $(OUT_VOCAB) -maxdepth 2 -type f -name "*.nt" -exec pigz -k -f {} \;
	# Corpus
	find $(OUT_FULLTEXT) -maxdepth 2 -type f -name "*.jsonl" -exec pigz -k -f {} \;

decompress:
	find $(OUT_DIR) -maxdepth 3 -type f -name "*.gz" -exec pigz -dk -f {} \;

# 1. Extract URIs with Wikipedia sitelinks (10M unfiltered; 7.4M filtered)
#    Scan once for the union of $(FALLBACK_LOCALE) + $(LOCALE); the union feeds
#    step 2 (vocab completeness fallback), the $(LOCALE)-only map feeds step 3
#    (corpus) so document extraction keeps its original semantics
#    This also filters out structural Wikidata statements
#    Time: 20 min on M4/10
$(UNION_SITELINKS): $(WIKIDATA_GZ) | $(WORK_DIR)
	pigz -dc $< \
		| rg "($(SITE_LOCALES)).wikipedia.org.*?schema.org/about" \
		| rg -v 'wiki/(?:Category|Template|Portal|Wikipedia|Module):|List_of_.+' \
		| awk '{print $$3 "\t" $$1}' \
		> $@

$(SITELINKS_MAP): $(UNION_SITELINKS)
	awk -F'\t' '$$2 ~ /^<https:\/\/$(LOCALE)\.wikipedia\.org\//' $< > $@

# 2. Extract N-triples with subject URIs having en|fr sitelinks (25M)
#    Time: 23 min on M4/10
$(WIKIDATA_NT): $(WIKIDATA_GZ) | $(UNION_SITELINKS)
	pigz -dc $< \
		| rg -e '/prop/direct/(P31|P279|P361|P106)>|skos/core#.*"@(mul|$(LOCALE)) \.' \
		| awk -v sf=$(UNION_SITELINKS) 'BEGIN{while((getline<sf)>0)sl[$$1]=1}{if($$1 in sl)print}' \
		> $@

# 3. Build JSONL corpus for Wikipedia documents (~7.1M pages for en)
#    New-style part files are self-contained XML exports: process each in parallel,
#    then merge with a single sorted pass (sort -u) and dedupe by document URI
#    Time: 1h 30min on M4/10 for full enwiki
$(WORK_CORPUS)/%.tsv: $(WIKIPEDIA_DIR)/%.xml.bz2 $(SITELINKS_MAP) | $(WORK_CORPUS)
	lbzip2 -dc $< | python3 wiki2jsonl.py $(SITELINKS_MAP) $(LOCALE) $(WORK_CORPUS)/$*-unmapped.jsonl > $@

$(WIKIPEDIA_TSV): $(WIKIPEDIA_STAMP) $(CORPUS_PARTS)
	@test -n "$(CORPUS_PARTS)" \
		|| { echo "No $(LOCALE)wiki part files in $(WIKIPEDIA_DIR); run 'make download'" >&2; exit 1; }
	@for f in $(notdir $(CORPUS_PARTS)); do \
		rg -qF "$$f" $(WIKIPEDIA_DIR)/SHA256SUMS \
			|| { echo "Stray part not in SHA256SUMS: $$f" >&2; exit 1; }; \
	done
	cat $(CORPUS_PARTS) | LC_ALL=C sort -u | awk -F'\t' '!seen[$$1]++' > $@
	@cat $(WORK_CORPUS)/*-unmapped.jsonl 2>/dev/null \
		> $(WORK_DIR)/$(LOCALE)wiki_unmapped.jsonl \
		|| touch $(WORK_DIR)/$(LOCALE)wiki_unmapped.jsonl

# Completeness check: every manifest entry must exist and hash-match
$(WIKIPEDIA_STAMP): $(WIKIPEDIA_DIR)/SHA256SUMS
	cd $(WIKIPEDIA_DIR) && $(SHASUM) $(SHASUM_OPT) --check SHA256SUMS && touch $@

# 4a. Extract localized SKOS labels (~11M English)
$(SKOS_LABELS_NT): $(WIKIDATA_NT)
	rg -F -e 'skos/core#' $< | sed 's/@mul/@$(LOCALE)/g' | sed 's/altLabel/hiddenLabel/g' | LC_ALL=C sort -u > $@

# 4b. Extract subclass_of (core) properties (~428K)
$(PROPS_P279_NT): $(WIKIDATA_NT)
	rg -F -e '/prop/direct/P279>' $< | LC_ALL=C sort -u > $@

# 4c. Extract part_of (core) properties (~475K)
$(PROPS_P361_NT): $(WIKIDATA_NT)
	rg -F -e '/prop/direct/P361>' $< | LC_ALL=C sort -u > $@

# 4d. Extract instance_of (class) properties (~10M)
$(PROPS_P31_NT): $(WIKIDATA_NT)
	rg -F -e '/prop/direct/P31>' $< | LC_ALL=C sort -u > $@

# 4e. Extract occupation properties (~3.3M)
$(PROPS_P106_NT): $(WIKIDATA_NT)
	rg -F -e '/prop/direct/P106>' $< | LC_ALL=C sort -u > $@

# Reusable SKOS generator
define generate_skos_nt
	BASE="$$(basename $1 .tsv)" ; \
	if [ -n "$3" ]; then SUBJECT_URI="$(VOCAB_URI)/$3"; else SUBJECT_URI="$(VOCAB_URI)"; fi ; \
	echo "<$$SUBJECT_URI/$$BASE> <http://www.w3.org/1999/02/22-rdf-syntax-ns#type> <http://www.w3.org/2004/02/skos/core#ConceptScheme> ." > $2 ; \
	sed "s|.*|& <http://www.w3.org/1999/02/22-rdf-syntax-ns#type> <http://www.w3.org/2004/02/skos/core#Concept> .\n& <http://www.w3.org/2004/02/skos/core#inScheme> <$$SUBJECT_URI/$$BASE> .|" $1 >> $2
	LC_ALL=C join $1 $(SKOS_LABELS_NT) >> $2
	if [ -z "$3" ]; then \
		LC_ALL=C join $1 $(PROPS_P361_NT) | sed 's|<http://www.wikidata.org/prop/direct/P361>|<http://www.w3.org/2004/02/skos/core#related>|g' >> $2 ; \
		LC_ALL=C join $1 $(PROPS_P279_NT) | sed 's|<http://www.wikidata.org/prop/direct/P279>|<http://www.w3.org/2004/02/skos/core#related>|g' >> $2 ; \
	fi
endef

# Generate URI lists for each concept (non-instance)
$(WORK_DIR)/core.tsv: $(SKOS_LABELS_NT) $(PROPS_P279_NT) $(PROPS_P361_NT) $(PROPS_P31_NT) $(PROPS_P106_NT)
	cat $(PROPS_P279_NT) $(PROPS_P361_NT) | awk '{print $$1}' | LC_ALL=C sort -u | LC_ALL=C join -v 1 - $(PROPS_P31_NT) | LC_ALL=C join -v 1 - $(PROPS_P106_NT) > $@

# Generate URI lists for each class
$(WORK_DIR)/class/%.tsv: $(ROOT_DIR)/class/%.tsv | $(PROPS_P31_NT) $(WORK_DIR)/class
	awk '{print $$1}' "$<" | xargs -I{} rg -F "{}> ." $(PROPS_P31_NT) | awk '{print $$1}' | LC_ALL=C sort -u > $@

# Generate URI lists for each occupation
$(WORK_DIR)/occupation/%.tsv: $(ROOT_DIR)/occupation/%.tsv | $(PROPS_P106_NT) $(WORK_DIR)/occupation
	awk '{print $$1}' "$<" | xargs -I{} rg -F "{}> ." $(PROPS_P106_NT) | awk '{print $$1}' | LC_ALL=C sort -u > $@

# Make SKOS output for core concepts
$(OUT_VOCAB)/core.nt: $(WORK_DIR)/core.tsv | $(OUT_VOCAB)
	$(call generate_skos_nt,$<,$@)

# Make SKOS output for each class
$(OUT_VOCAB)/class/%.nt: $(WORK_DIR)/class/%.tsv | $(OUT_VOCAB)/class $(SKOS_LABELS_NT) $(PROPS_P279_NT) $(PROPS_P361_NT)
	$(call generate_skos_nt,$<,$@,class)

# Make SKOS output for each occupation
$(OUT_VOCAB)/occupation/%.nt: $(WORK_DIR)/occupation/%.tsv | $(OUT_VOCAB)/occupation $(SKOS_LABELS_NT) $(PROPS_P279_NT) $(PROPS_P361_NT)
	$(call generate_skos_nt,$<,$@,occupation)

# Reusable JSONL split generator
define split_jsonl
	input="$(2)"; \
	dir=$$(dirname "$$input"); \
	base=$$(basename "$$input" .jsonl); \
	cat "$(1)" | awk -v seed="$(RUN_DATE)" -v dir="$$dir" -v base="$$base" 'BEGIN{srand(seed); test_pct=0.1; eval_pct=0.1} {if (rand() < test_pct) print > (dir "/" base "-test.jsonl"); else if (rand() < test_pct+eval_pct) print > (dir "/" base "-eval.jsonl"); else print > (dir "/" base "-train.jsonl")}'
endef

# Filter JSONL by concept using join with URI lists, then strip URI prefix
$(WORK_FULLTEXT)/core.jsonl: $(WORK_DIR)/core.tsv $(WIKIPEDIA_TSV) | $(WORK_FULLTEXT)
	LC_ALL=C join $< $(WIKIPEDIA_TSV) | cut -d' ' -f2- > $@

$(WORK_FULLTEXT)/class/%.jsonl: $(WORK_DIR)/class/%.tsv $(WIKIPEDIA_TSV) | $(WORK_FULLTEXT)/class
	LC_ALL=C join $< $(WIKIPEDIA_TSV) | cut -d' ' -f2- > $@

$(WORK_FULLTEXT)/occupation/%.jsonl: $(WORK_DIR)/occupation/%.tsv $(WIKIPEDIA_TSV) | $(WORK_FULLTEXT)/occupation
	LC_ALL=C join $< $(WIKIPEDIA_TSV) | cut -d' ' -f2- > $@

# Generate train/eval/test splits for JSONL
$(OUT_FULLTEXT)/core.jsonl: $(WORK_FULLTEXT)/core.jsonl | $(OUT_FULLTEXT)
	$(call split_jsonl,$<,$@)

$(OUT_FULLTEXT)/class/%.jsonl: $(WORK_FULLTEXT)/class/%.jsonl | $(OUT_FULLTEXT)/class
	$(call split_jsonl,$<,$@)

$(OUT_FULLTEXT)/occupation/%.jsonl: $(WORK_FULLTEXT)/occupation/%.jsonl | $(OUT_FULLTEXT)/occupation
	$(call split_jsonl,$<,$@)

$(OUT_DIR)/stats.tsv: $(OUT_FULLTEXT)/core.jsonl \
		$(patsubst $(ROOT_DIR)/class/%.tsv,$(OUT_FULLTEXT)/class/%.jsonl,$(CLASS_FILES)) \
		$(patsubst $(ROOT_DIR)/occupation/%.tsv,$(OUT_FULLTEXT)/occupation/%.jsonl,$(OCCUPATION_FILES)) | $(OUT_DIR)
	python3 stats.py $(OUT_DIR) $(SOURCE_DIR) $(WORK_DIR)/$(LOCALE)wiki_unmapped.jsonl > $@

$(OUT_DIR)/sankey.txt: $(OUT_DIR)/stats.tsv | $(OUT_DIR)
	python3 sankey.py $(OUT_DIR) $(SOURCE_DIR) > $@

# Reusable Annif project generator: $(1)=source tsv $(2)=group $(3)=output .cfg
define generate_project
	subdir=$$(basename $(1) .tsv); \
	if [ "$(2)" = "core" ]; then \
		proj=wikicore_$(LOCALE)_$(BACKEND)_core; \
		desc="WikiCore $(BACKEND) core"; \
		vocab=wikicore-$(RUN_DATE)-core-$(LOCALE); \
		alt="wikicore-$(RUN_DATE)-core-$(LOCALE)(exclude=*,include_scheme=$(VOCAB_URI)/core)"; \
	else \
		proj=wikicore_$(LOCALE)_$(BACKEND)_$(2)_$$subdir; \
		desc="WikiCore $(BACKEND) $(2) $$subdir"; \
		vocab=wikicore-$(RUN_DATE)-$(2)-$$subdir-$(LOCALE); \
		alt="wikicore-$(RUN_DATE)-$(2)-$(LOCALE)(exclude=*,include_scheme=$(VOCAB_URI)/$(2)/$$subdir)"; \
	fi; \
	{ \
		echo "[$$proj]"; \
		echo "name = $$desc ($(LOCALE))"; \
		echo "backend = $(BACKEND)"; \
		echo "language = $(LOCALE)"; \
		echo "analyzer = snowball($(LOCALE))"; \
		echo "limit = 20"; \
		echo "threshold = 0"; \
		echo "use_hidden_labels = true"; \
		echo "vocab = $$vocab"; \
		echo "# vocab = $$alt"; \
		echo "# Vocab size: $$(wc -l < $(1))"; \
	} > $(3)
endef

# Reusable Annif ensemble generator: $(1)=group $(2)=sources csv $(3)=output .cfg
define generate_ensemble
	{ \
		echo "[wikicore_$(LOCALE)_ensemble_$(1)]"; \
		echo "name = WikiCore Ensemble $(1) ($(LOCALE))"; \
		echo "backend = ensemble"; \
		echo "language = $(LOCALE)"; \
		echo "limit = 20"; \
		echo "sources = $$(printf '%s\n' $(2) | sed 's/^,//')"; \
		echo "vocab = wikicore-$(RUN_DATE)-$(1)-$(LOCALE)"; \
	} > $(3)
endef

# One config file per project: <project_id>.cfg
$(ANNIF_PROJECTS)/wikicore_$(LOCALE)_$(BACKEND)_core.cfg: $(WORK_DIR)/core.tsv | $(ANNIF_PROJECTS)
	$(call generate_project,$<,core,$@)

$(ANNIF_PROJECTS)/wikicore_$(LOCALE)_$(BACKEND)_class_%.cfg: $(WORK_DIR)/class/%.tsv | $(ANNIF_PROJECTS)
	$(call generate_project,$<,class,$@)

$(ANNIF_PROJECTS)/wikicore_$(LOCALE)_$(BACKEND)_occupation_%.cfg: $(WORK_DIR)/occupation/%.tsv | $(ANNIF_PROJECTS)
	$(call generate_project,$<,occupation,$@)

# One config file per ensemble: class, occupation, all
$(ANNIF_PROJECTS)/wikicore_$(LOCALE)_ensemble_class.cfg: $(WORK_DIR)/class | $(ANNIF_PROJECTS)
	@sources=''; \
	for a in $</*; do \
		sources="$$sources,wikicore_$(LOCALE)_$(BACKEND)_class_$$(basename "$$a" .tsv)"; \
	done; \
	$(call generate_ensemble,class,$$sources,$@)

$(ANNIF_PROJECTS)/wikicore_$(LOCALE)_ensemble_occupation.cfg: $(WORK_DIR)/occupation | $(ANNIF_PROJECTS)
	@sources=''; \
	for a in $</*; do \
		sources="$$sources,wikicore_$(LOCALE)_$(BACKEND)_occupation_$$(basename "$$a" .tsv)"; \
	done; \
	$(call generate_ensemble,occupation,$$sources,$@)

$(ANNIF_PROJECTS)/wikicore_$(LOCALE)_ensemble_all.cfg: $(WORK_DIR)/core.tsv $(WORK_DIR)/class $(WORK_DIR)/occupation | $(ANNIF_PROJECTS)
	@sources=wikicore_$(LOCALE)_$(BACKEND)_core; \
	for a in $(WORK_DIR)/class/*; do \
		sources="$$sources,wikicore_$(LOCALE)_$(BACKEND)_class_$$(basename "$$a" .tsv)"; \
	done; \
	for a in $(WORK_DIR)/occupation/*; do \
		sources="$$sources,wikicore_$(LOCALE)_$(BACKEND)_occupation_$$(basename "$$a" .tsv)"; \
	done; \
	$(call generate_ensemble,all,$$sources,$@)


# Reusable Annif actions: vocab/project ids are derived from the target path
define annif_load
	$(ANNIF) load-vocab -p $(ANNIF_PROJECTS) -f -v DEBUG -L $(LOCALE) $(notdir $(@D)) $<
endef

define annif_train
	$(ANNIF) train -p $(ANNIF_PROJECTS) -v DEBUG $(notdir $(@D)) $(1)
	test -n "$$(ls -A $(@D) | grep -v '^$(ANNIF_STAMP)')"
	touch $@
endef

define annif_eval
	$(ANNIF) eval -p $(ANNIF_PROJECTS) -v DEBUG $(basename $(notdir $@)) $< -M $@
endef

define annif_optimize
	$(ANNIF) optimize -p $(ANNIF_PROJECTS) -v DEBUG $(basename $(notdir $@)) $< -r $@
endef

# Loaded vocabs: $(ANNIF_VOCABS)/<vocab_id>/subjects.ttl
$(ANNIF_VOCABS)/wikicore-$(RUN_DATE)-core-$(LOCALE)/subjects.ttl: $(OUT_VOCAB)/core.nt | $(ANNIF_PROJECTS)
	$(call annif_load)

$(ANNIF_VOCABS)/wikicore-$(RUN_DATE)-class-%-$(LOCALE)/subjects.ttl: $(OUT_VOCAB)/class/%.nt | $(ANNIF_PROJECTS)
	$(call annif_load)

$(ANNIF_VOCABS)/wikicore-$(RUN_DATE)-occupation-%-$(LOCALE)/subjects.ttl: $(OUT_VOCAB)/occupation/%.nt | $(ANNIF_PROJECTS)
	$(call annif_load)

# Trained projects: $(ANNIF_MODELS)/<project_id>/ (model files written by Annif)
$(ANNIF_MODELS)/wikicore_$(LOCALE)_$(BACKEND)_core/$(ANNIF_STAMP): $(ANNIF_VOCABS)/wikicore-$(RUN_DATE)-core-$(LOCALE)/subjects.ttl $(OUT_FULLTEXT)/core-train.jsonl | $(ANNIF_PROJECTS)
	$(call annif_train,$(OUT_FULLTEXT)/core-train.jsonl)

$(ANNIF_MODELS)/wikicore_$(LOCALE)_$(BACKEND)_class_%/$(ANNIF_STAMP): $(ANNIF_VOCABS)/wikicore-$(RUN_DATE)-class-%-$(LOCALE)/subjects.ttl $(OUT_FULLTEXT)/class/%-train.jsonl | $(ANNIF_PROJECTS)
	$(call annif_train,$(OUT_FULLTEXT)/class/$*-train.jsonl)

$(ANNIF_MODELS)/wikicore_$(LOCALE)_$(BACKEND)_occupation_%/$(ANNIF_STAMP): $(ANNIF_VOCABS)/wikicore-$(RUN_DATE)-occupation-%-$(LOCALE)/subjects.ttl $(OUT_FULLTEXT)/occupation/%-train.jsonl | $(ANNIF_PROJECTS)
	$(call annif_train,$(OUT_FULLTEXT)/occupation/$*-train.jsonl)

# Evaluated projects: $(ANNIF_EVAL)/<project_id>.json
$(ANNIF_EVAL)/wikicore_$(LOCALE)_$(BACKEND)_core.json: $(OUT_FULLTEXT)/core-eval.jsonl | $(ANNIF_EVAL)
	$(call annif_eval)

$(ANNIF_EVAL)/wikicore_$(LOCALE)_$(BACKEND)_class_%.json: $(OUT_FULLTEXT)/class/%-eval.jsonl | $(ANNIF_EVAL)
	$(call annif_eval)

$(ANNIF_EVAL)/wikicore_$(LOCALE)_$(BACKEND)_occupation_%.json: $(OUT_FULLTEXT)/occupation/%-eval.jsonl | $(ANNIF_EVAL)
	$(call annif_eval)

# Optimized projects: $(ANNIF_EVAL)/<project_id>.tsv
$(ANNIF_EVAL)/wikicore_$(LOCALE)_$(BACKEND)_core.tsv: $(OUT_FULLTEXT)/core-test.jsonl | $(ANNIF_EVAL)
	$(call annif_optimize)

$(ANNIF_EVAL)/wikicore_$(LOCALE)_$(BACKEND)_class_%.tsv: $(OUT_FULLTEXT)/class/%-test.jsonl | $(ANNIF_EVAL)
	$(call annif_optimize)

$(ANNIF_EVAL)/wikicore_$(LOCALE)_$(BACKEND)_occupation_%.tsv: $(OUT_FULLTEXT)/occupation/%-test.jsonl | $(ANNIF_EVAL)
	$(call annif_optimize)

$(WORK_DIR) $(WORK_DIR)/class $(WORK_DIR)/occupation \
$(WORK_CORPUS) $(WORK_FULLTEXT) $(WORK_FULLTEXT)/class $(WORK_FULLTEXT)/occupation \
$(OUT_DIR) $(OUT_VOCAB) $(OUT_VOCAB)/class $(OUT_VOCAB)/occupation \
$(OUT_FULLTEXT) $(OUT_FULLTEXT)/class $(OUT_FULLTEXT)/occupation \
$(ANNIF_PROJECTS) $(ANNIF_VOCABS) $(ANNIF_EVAL):
	mkdir -p $@
