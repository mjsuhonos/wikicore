SHELL := /bin/bash
.SHELLFLAGS := -euo pipefail -c
.PHONY: default data vocab fulltext annif config load train eval optimize compress decompress stats sankey

# Options
LOCALE    ?= en
BACKEND   ?= mllm
RUN_DATE  ?= $(shell date +%Y%m%d)
VOCAB_URI := https://wikicore.ca/$(RUN_DATE)

# Paths
ROOT_DIR         := $(PWD)
ANNIF            ?= $(ROOT_DIR)/../Annif.nosync/.venv/bin/annif
SOURCE_DIR       := $(ROOT_DIR)/source.nosync
WORK_DIR         := $(ROOT_DIR)/working.nosync
OUT_DIR          := $(ROOT_DIR)/wikicore-$(RUN_DATE)-$(LOCALE)
OCCUPATION_FILES := $(wildcard $(ROOT_DIR)/occupation/*.tsv)
CLASS_FILES      := $(wildcard $(ROOT_DIR)/class/*.tsv)

# Input dumps
# NB: very large! Wikidata is >1TB uncompressed, Wikipedia is 110GB uncompressed
WIKIDATA_GZ      := $(SOURCE_DIR)/wikidata-20260824-all-BETA.nt.gz
WIKIPEDIA_BZ     := $(SOURCE_DIR)/enwiki-20260801-pages-articles.xml.bz2

# Extracted files
SITELINKS_MAP    := $(WORK_DIR)/enwiki_sitelinks.tsv
WIKIDATA_NT      := $(WORK_DIR)/enwiki_wikidata.nt
WIKIPEDIA_TSV    := $(WORK_DIR)/enwiki_corpus.tsv

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
	@echo "	optimize	Optimize Annif projects (.tsv)"
	@echo "	eval		Evaluate Annif projects (.json)"
	@echo ""
	@echo "	compress	Compress files for Github (.gz)"
	@echo "	decompress	Extract files from Github"
	@echo ""
	@echo "Options:"
	@echo "	-j N		Number of parallel jobs ('-j' alone means all CPUs)"
	@echo "	RUN_DATE	Default '$(RUN_DATE)' (eg. YYYYMMDD)"
	@echo "	LOCALE	Default 'en'"
	@echo "	BACKEND	Default 'mllm'"
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
annif:		config load train eval optimize
			@echo "  LOCALE=$(LOCALE)"
			@echo "  RUN_DATE=$(RUN_DATE)"
			@echo "  BACKEND=$(BACKEND)"

config:		$(ANNIF_PROJECTS)/wikicore_$(LOCALE)_$(BACKEND)_core.cfg \
			$(patsubst $(ROOT_DIR)/class/%.tsv,$(ANNIF_PROJECTS)/wikicore_$(LOCALE)_$(BACKEND)_class_%.cfg,$(CLASS_FILES)) \
			$(patsubst $(ROOT_DIR)/occupation/%.tsv,$(ANNIF_PROJECTS)/wikicore_$(LOCALE)_$(BACKEND)_occupation_%.cfg,$(OCCUPATION_FILES)) \
			$(ANNIF_PROJECTS)/wikicore_$(LOCALE)_ensemble_class.cfg \
			$(ANNIF_PROJECTS)/wikicore_$(LOCALE)_ensemble_occupation.cfg \
			$(ANNIF_PROJECTS)/wikicore_$(LOCALE)_ensemble_all.cfg \

load:		$(ANNIF_VOCABS)/wikicore-$(RUN_DATE)-core-$(LOCALE)/subjects.ttl \
			$(patsubst $(ROOT_DIR)/class/%.tsv,$(ANNIF_VOCABS)/wikicore-$(RUN_DATE)-class-%-$(LOCALE)/subjects.ttl,$(CLASS_FILES)) \
			$(patsubst $(ROOT_DIR)/occupation/%.tsv,$(ANNIF_VOCABS)/wikicore-$(RUN_DATE)-occupation-%-$(LOCALE)/subjects.ttl,$(OCCUPATION_FILES)) \

train:		$(ANNIF_MODELS)/wikicore_$(LOCALE)_$(BACKEND)_core \
			$(patsubst $(ROOT_DIR)/class/%.tsv,$(ANNIF_MODELS)/wikicore_$(LOCALE)_$(BACKEND)_class_%,$(CLASS_FILES)) \
			$(patsubst $(ROOT_DIR)/occupation/%.tsv,$(ANNIF_MODELS)/wikicore_$(LOCALE)_$(BACKEND)_occupation_%,$(OCCUPATION_FILES))

eval:		$(ANNIF_EVAL)/wikicore_$(LOCALE)_$(BACKEND)_core.json \
			$(patsubst $(ROOT_DIR)/class/%.tsv,$(ANNIF_EVAL)/wikicore_$(LOCALE)_$(BACKEND)_class_%.json,$(CLASS_FILES)) \
			$(patsubst $(ROOT_DIR)/occupation/%.tsv,$(ANNIF_EVAL)/wikicore_$(LOCALE)_$(BACKEND)_occupation_%.json,$(OCCUPATION_FILES)) \

optimize:	$(ANNIF_EVAL)/wikicore_$(LOCALE)_$(BACKEND)_core.tsv \
			$(patsubst $(ROOT_DIR)/class/%.tsv,$(ANNIF_EVAL)/wikicore_$(LOCALE)_$(BACKEND)_class_%.tsv,$(CLASS_FILES)) \
			$(patsubst $(ROOT_DIR)/occupation/%.tsv,$(ANNIF_EVAL)/wikicore_$(LOCALE)_$(BACKEND)_occupation_%.tsv,$(OCCUPATION_FILES)) \

# GitHub GZip targets
compress: $(OUT_VOCAB) $(OUT_FULLTEXT)
	# Vocabularies
	find $(OUT_VOCAB) -maxdepth 2 -type f -name "*.nt" -exec pigz -k -f {} \;
	# Corpus
	find $(OUT_FULLTEXT) -maxdepth 2 -type f -name "*.jsonl" -exec pigz -k -f {} \;

decompress:
	find $(OUT_DIR) -maxdepth 3 -type f -name "*.gz" -exec pigz -dk -f {} \;

# 1. Extract URIs with Wikipedia sitelinks (10M unfiltered; 7.4M filtered)
#    This also filters out structural Wikidata statements
#    Time: 20 min on M4/10
$(SITELINKS_MAP): $(WIKIDATA_GZ) | $(WORK_DIR)
	pigz -dc $< \
		| rg "en.wikipedia.org.*?schema.org/about" \
		| rg -v 'wiki/(?:Category|Template|Portal|Wikipedia|Module):|List_of_.+' \
		| awk '{print $$3 "\t" $$1}' \
		> $@

# 2. Extract N-triples with subject URIs having sitelinks (25M)
#    Time: 23 min on M4/10
$(WIKIDATA_NT): $(WIKIDATA_GZ) | $(SITELINKS_MAP)
	pigz -dc $< \
		| rg -e '/prop/direct/(P31|P279|P361|P106)>|skos/core#.*"@(mul|$(LOCALE)) \.' \
		| awk -v sf=$(SITELINKS_MAP) 'BEGIN{while((getline<sf)>0)sl[$$1]=1}{if($$1 in sl)print}' \
		> $@

# 3. Build JSONL corpus for Wikipedia documents (7.1M)
#    Time: 1h 30min on M4/10
$(WIKIPEDIA_TSV): $(WIKIPEDIA_BZ) $(SITELINKS_MAP)
	lbunzip2 -dc $(WIKIPEDIA_BZ) | python3 wiki2jsonl.py $(SITELINKS_MAP)| LC_ALL=C sort -u > $@

# 4a. Extract localized labels (~14M English)
$(SKOS_LABELS_NT): $(WIKIDATA_NT)
	sed 's/@mul/@$(LOCALE)/g' $< | sed 's/altLabel/hidden/g' | LC_ALL=C sort -u > $@

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
$(WORK_DIR)/core.tsv: $(SKOS_LABELS_NT) $(PROPS_P279_NT) $(PROPS_P361_NT) $(PROPS_P31_NT)
	cat $(PROPS_P279_NT) $(PROPS_P361_NT) | awk '{print $$1}' | LC_ALL=C sort -u | LC_ALL=C join -v 1 - $(PROPS_P31_NT) > $@

# Generate URI lists for each class
$(WORK_DIR)/class/%.tsv: $(ROOT_DIR)/class/%.tsv $(WORK_DIR)/class | $(PROPS_P31_NT) $(WORK_DIR)/class
	awk '{print $$1}' "$<" | xargs -I{} rg -F "{}> ." $(PROPS_P31_NT) | awk '{print $$1}' | LC_ALL=C sort -u > $@

# Generate URI lists for each occupation
$(WORK_DIR)/occupation/%.tsv: $(ROOT_DIR)/occupation/%.tsv $(WORK_DIR)/occupation | $(PROPS_P106_NT) $(WORK_DIR)/occupation
	awk '{print $$1}' "$<" | xargs -I{} rg -F "{}> ." $(PROPS_P106_NT) | awk '{print $$1}' | LC_ALL=C sort -u > $@

# Make SKOS output for core concepts
$(OUT_VOCAB)/core.nt: $(WORK_DIR)/core.tsv | $(OUT_VOCAB)
	$(call generate_skos_nt,$<,$@)

# Make SKOS output for each class
$(OUT_VOCAB)/class/%.nt: $(WORK_DIR)/class/%.tsv $(OUT_VOCAB)/class | $(SKOS_LABELS_NT) $(PROPS_P279_NT) $(PROPS_P361_NT)
	$(call generate_skos_nt,$<,$@,class)

# Make SKOS output for each occupation
$(OUT_VOCAB)/occupation/%.nt: $(WORK_DIR)/occupation/%.tsv $(OUT_VOCAB)/occupation | $(SKOS_LABELS_NT) $(PROPS_P279_NT) $(PROPS_P361_NT)
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
	python3 stats.py $(OUT_DIR) $(SOURCE_DIR) > $@

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
		echo "analyzer = snowball(english)"; \
		echo "limit = 100"; \
		echo "threshold = 0"; \
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
		echo "limit = 100"; \
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
	$(ANNIF) train -p $(ANNIF_PROJECTS) -v DEBUG $(notdir $@) $(1)
	test -n "$$(ls -A $@)"
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
$(ANNIF_MODELS)/wikicore_$(LOCALE)_$(BACKEND)_core: $(ANNIF_VOCABS)/wikicore-$(RUN_DATE)-core-$(LOCALE)/subjects.ttl $(OUT_FULLTEXT)/core-train.jsonl | $(ANNIF_PROJECTS)
	$(call annif_train,$(OUT_FULLTEXT)/core-train.jsonl)

$(ANNIF_MODELS)/wikicore_$(LOCALE)_$(BACKEND)_class_%: $(ANNIF_VOCABS)/wikicore-$(RUN_DATE)-class-%-$(LOCALE)/subjects.ttl $(OUT_FULLTEXT)/class/%-train.jsonl | $(ANNIF_PROJECTS)
	$(call annif_train,$(OUT_FULLTEXT)/class/$*-train.jsonl)

$(ANNIF_MODELS)/wikicore_$(LOCALE)_$(BACKEND)_occupation_%: $(ANNIF_VOCABS)/wikicore-$(RUN_DATE)-occupation-%-$(LOCALE)/subjects.ttl $(OUT_FULLTEXT)/occupation/%-train.jsonl | $(ANNIF_PROJECTS)
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
$(WORK_FULLTEXT) $(WORK_FULLTEXT)/class $(WORK_FULLTEXT)/occupation \
$(OUT_VOCAB) $(OUT_VOCAB)/class $(OUT_VOCAB)/occupation \
$(OUT_FULLTEXT) $(OUT_FULLTEXT)/class $(OUT_FULLTEXT)/occupation \
$(ANNIF_PROJECTS) $(ANNIF_EVAL):
	mkdir -p $@
