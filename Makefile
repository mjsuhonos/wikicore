SHELL := /bin/bash
.SHELLFLAGS := -o pipefail -c

# Options
LOCALE    ?= en
BACKEND   ?= mllm
RUN_DATE  := $(shell date +%Y%m%d)
VOCAB_URI := https://wikicore.ca/$(RUN_DATE)

# Paths
ROOT_DIR         := $(PWD)
SOURCE_DIR       := $(ROOT_DIR)/source.nosync
WORK_DIR         := $(ROOT_DIR)/working.nosync
OUT_DIR          := $(ROOT_DIR)/wikicore-$(RUN_DATE)-$(LOCALE)
OCCUPATION_FILES := $(wildcard $(ROOT_DIR)/occupation/*.tsv)
CLASS_FILES      := $(wildcard $(ROOT_DIR)/class/*.tsv)

# Input dumps
WIKIDATA_GZ      := $(SOURCE_DIR)/wikidata-20260824-all-BETA.nt.gz
WIKIPEDIA_BZ     := $(SOURCE_DIR)/enwiki-20260801-pages-articles.xml.bz2
#FULLTEXT_GZ      := $(SOURCE_DIR)/wikidata5m_text.txt.gz

# Extracted files
SITELINKS_MAP    := $(WORK_DIR)/enwiki_sitelinks.tsv
WIKIDATA_NT      := $(WORK_DIR)/enwiki_linked_wikidata.nt
WIKIPEDIA_JSONL  := $(WORK_DIR)/enwiki_corpus.jsonl
#SITELINKS_WD5M   := $(WORK_DIR)/enwiki_linked_wikidata_wd5m.tsv

# SKOS files
SKOS_LABELS_NT   := $(WORK_DIR)/wikicore-skos-labels-$(LOCALE).nt
PROPS_P31_NT     := $(WORK_DIR)/wikicore-P31.nt
PROPS_P106_NT    := $(WORK_DIR)/wikicore-P106.nt
PROPS_P279_NT    := $(WORK_DIR)/wikicore-P279.nt
PROPS_P361_NT    := $(WORK_DIR)/wikicore-P361.nt

# Wikipedia corpus files
# TODO: document metadata for CSV format
WORK_CORPUS      := $(WORK_DIR)/corpus
OUT_CORPUS       := $(OUT_DIR)/corpus

# WD5M Fulltext files
# TODO: deprecate?
WORK_FULLTEXT    := $(WORK_DIR)/fulltext
OUT_FULLTEXT     := $(OUT_DIR)/fulltext

# Annif files
ANNIF_PROJECTS   := $(OUT_DIR)/projects.d
ANNIF_EVAL       := $(OUT_DIR)/data/eval

# Default (help) target
default:
	@echo "-----------------"
	@echo "Wiki Core toolkit"
	@echo "-----------------"
	@echo "Usage: make [TARGET] [-j N] [OPTIONS]"
	@echo "   eg. make annif -j 4 LOCALE=fr BACKEND=omikuji"
	@echo ""
	@echo "Targets:"
	@echo "data"
	@echo "  vocab		Generate Wikidata SKOS vocabs (.nt)"
	@echo "  corpus	Generate Wikipedia corpora (.jsonl)"
	@echo "  fulltext	Generate WD5M text splits (.tsv)"
	@echo ""
	@echo "annif"
	@echo "  config	Generate Annif project configs (.cfg)"
	@echo "  load		Load vocabs into Annif"
	@echo "  train		Train and evaluate Annif projects (.json)"
	@echo ""
	@echo "  compress	Compress files for Github (.gz)"
	@echo "  decompress	Extract files from Github"
	@echo ""
	@echo "Options:"
	@echo "  -j N		Number of parallel jobs ('-j' alone means all CPUs)"
	@echo "  RUN_DATE	Default '$(RUN_DATE)' (eg. YYYYMMDD)"
	@echo "  LOCALE	Default 'en'"
	@echo "  BACKEND	Default 'mllm'"

# Data targets
data:		vocab fulltext
			@echo "  LOCALE=$(LOCALE)"
			@echo "  RUN_DATE=$(RUN_DATE)"

vocab:		core class occupation
core:		$(OUT_DIR)/core.nt
class:		$(WORK_DIR)/class.nt
occupation:	$(WORK_DIR)/occupation.nt

corpus:		$(OUT_CORPUS)/core.csv
			# TODO: add classes, occupations

fulltext: 	$(OUT_FULLTEXT)/core.tsv \
			$(patsubst $(ROOT_DIR)/class/%.tsv,$(OUT_FULLTEXT)/class/%.tsv,$(CLASS_FILES)) \
			$(patsubst $(ROOT_DIR)/occupation/%.tsv,$(OUT_FULLTEXT)/occupation/%.tsv,$(OCCUPATION_FILES)) \

# Annif targets
annif:		config load train
			@echo "  LOCALE=$(LOCALE)"
			@echo "  RUN_DATE=$(RUN_DATE)"
			@echo "  BACKEND=$(BACKEND)"

config:		$(ANNIF_PROJECTS)/core.cfg \
			$(ANNIF_PROJECTS)/class.cfg \
			$(ANNIF_PROJECTS)/occupation.cfg \

load:		$(ANNIF_PROJECTS)/.loaded_core \
			$(ANNIF_PROJECTS)/.loaded_class \
			$(ANNIF_PROJECTS)/.loaded_occupation \
			$(patsubst $(ROOT_DIR)/class/%.tsv,$(ANNIF_PROJECTS)/.loaded_class_%,$(CLASS_FILES)) \
			$(patsubst $(ROOT_DIR)/occupation/%.tsv,$(ANNIF_PROJECTS)/.loaded_occupation_%,$(OCCUPATION_FILES)) \

train:		$(ANNIF_PROJECTS)/.trained_core \
			$(patsubst $(ROOT_DIR)/class/%.tsv,$(ANNIF_PROJECTS)/.trained_class_%,$(CLASS_FILES)) \
			$(patsubst $(ROOT_DIR)/occupation/%.tsv,$(ANNIF_PROJECTS)/.trained_occupation_%,$(OCCUPATION_FILES)) \

# GitHub GZip targets
compress: $(OUT_DIR) $(OUT_CORPUS)
	# Vocabularies
	find $(OUT_DIR) -maxdepth 2 -type f -name "*.nt" -exec pigz -k -f {} \;
	# Corpus
	find $(OUT_CORPUS) -maxdepth 2 -type f -name "*.csv" -exec pigz -k -f {} \;

decompress:
	find $(OUT_DIR) -maxdepth 3 -type f -name "*.gz" -exec pigz -dk -f {} \;
	#cat $(OUT_DIR)/class/*.nt | LC_ALL=C sort -u > $(OUT_DIR)/class.nt
	#cat $(OUT_DIR)/occupation/*.nt | LC_ALL=C sort -u > $(OUT_DIR)/occupation.nt

$(WORK_DIR) $(WORK_DIR)/occupation $(WORK_DIR)/class:
	mkdir -p $@

$(WORK_FULLTEXT) $(WORK_FULLTEXT)/class $(WORK_FULLTEXT)/occupation:
	mkdir -p $@

$(OUT_DIR) $(OUT_DIR)/occupation $(OUT_DIR)/class:
	mkdir -p $@

$(OUT_CORPUS) $(OUT_CORPUS)/class $(OUT_CORPUS)/occupation:
	mkdir -p $@

$(ANNIF_PROJECTS) $(ANNIF_EVAL):
	mkdir -p $@

# 1. Extract URIs with Wikipedia sitelinks (10M unfiltered; 7.4M filtered)
#    This also filters out structural Wikidata statements
#    Time: 20 min on M4/10
$(SITELINKS_MAP): $(WIKIDATA_GZ) | $(WORK_DIR) $(OUT_DIR)
	pigz -dc $< \
		| rg "en.wikipedia.org.*?schema.org/about" \
		| rg -v "wiki/(Category|Template|Portal|Wikipedia|Module|List_of_.+):" \
		| awk '{print $$3 "\t" $$1}' \
		> $@

# 2. Extract N-triples with subject URIs having sitelinks (25M)
#    Time: 23 min on M4/10
$(WIKIDATA_NT): $(WIKIDATA_GZ) | $(SITELINKS_MAP)
	pigz -dc $< \
		| rg -e '/prop/direct/(P31|P279|P361|P106)>|skos/core#.*"@(mul|$(LOCALE)) \.' \
		| awk -v sf=$(SITELINKS_MAP) 'BEGIN{while((getline<sf)>0)sl[$$1]=1}{if($$1 in sl)print}' \
		> $@

# 3. Build JSONL corpus for Wikipedia documents
# TODO: VERY SLOW!   split and parallelize?
jsontest: $(WIKIPEDIA_JSONL)
$(WIKIPEDIA_JSONL): $(WIKIPEDIA_BZ) $(SITELINKS_MAP)
	lbunzip2 -dc $(WIKIPEDIA_BZ) | python3 wiki2jsonl.py $(SITELINKS_MAP) > $@

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
	#$(MAKE) $(ROOT_DIR)/class_labels.tsv

# 4e. Extract occupation properties (~3.3M)
$(PROPS_P106_NT): $(WIKIDATA_NT)
	rg -F -e '/prop/direct/P106>' $< | LC_ALL=C sort -u > $@
	#$(MAKE) $(ROOT_DIR)/occupation_labels.tsv

#$(ROOT_DIR)/class_labels.tsv: $(PROPS_P31_NT) $(SKOS_LABELS_NT)
#	rg prefLabel $(SKOS_LABELS_NT) | awk 'NR==FNR {count[$$1]=$$2; next} ($$1 in count) {label=""; for(i=3; i<=NF-1; i++) label=label $$i " "; print $$1, count[$$1], label}' <(awk '{print $$3}' $< | sort | uniq -c | awk '{print $$2 "\t" $$1}' | sort -t$$'\t' -k2 -nr) - | sort -k2 -nr > $@

#$(ROOT_DIR)/occupation_labels.tsv: $(PROPS_P106_NT) $(SKOS_LABELS_NT)
#	rg prefLabel $(SKOS_LABELS_NT) | awk 'NR==FNR {count[$$1]=$$2; next} ($$1 in count) {label=""; for(i=3; i<=NF-1; i++) label=label $$i " "; print $$1, count[$$1], label}' <(awk '{print $$3}' $< | sort | uniq -c | awk '{print $$2 "\t" $$1}' | sort -t$$'\t' -k2 -nr) - | sort -k2 -nr > $@

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

# Make SKOS output for core concepts
$(OUT_DIR)/core.nt: $(WORK_DIR)/core.tsv
	$(call generate_skos_nt,$<,$@)

# Generate URI lists for each occupation
$(WORK_DIR)/occupation/%.tsv: $(ROOT_DIR)/occupation/%.tsv $(WORK_DIR)/occupation | $(PROPS_P106_NT) $(WORK_DIR)/occupation
	awk '{print $$1}' "$<" | xargs -I{} rg -F "{}> ." $(PROPS_P106_NT) | awk '{print $$1}' | LC_ALL=C sort -u > $@

$(WORK_DIR)/occupation.tsv: $(WORK_DIR)/occupation | $(patsubst $(ROOT_DIR)/occupation/%.tsv,$(WORK_DIR)/occupation/%.tsv,$(OCCUPATION_FILES))
	cat $</*.tsv | LC_ALL=C sort -u >> $@

# Make SKOS output for each occupation
$(OUT_DIR)/occupation/%.nt: $(WORK_DIR)/occupation/%.tsv $(OUT_DIR)/occupation | $(SKOS_LABELS_NT) $(PROPS_P279_NT) $(PROPS_P361_NT)
	$(call generate_skos_nt,$<,$@,occupation)

$(WORK_DIR)/occupation.nt: $(OUT_DIR)/occupation | $(patsubst $(ROOT_DIR)/occupation/%.tsv,$(OUT_DIR)/occupation/%.nt,$(OCCUPATION_FILES))
	cat $</*.nt | LC_ALL=C sort -u >> $@

# Generate URI lists for each class
$(WORK_DIR)/class/%.tsv: $(ROOT_DIR)/class/%.tsv $(WORK_DIR)/class | $(PROPS_P31_NT) $(WORK_DIR)/class
	awk '{print $$1}' "$<" | xargs -I{} rg -F "{}> ." $(PROPS_P31_NT) | awk '{print $$1}' | LC_ALL=C sort -u > $@

$(WORK_DIR)/class.tsv: $(WORK_DIR)/class | $(patsubst $(ROOT_DIR)/class/%.tsv,$(WORK_DIR)/class/%.tsv,$(CLASS_FILES))
	cat $</*.tsv | LC_ALL=C sort -u >> $@

# Make SKOS output for each class
$(OUT_DIR)/class/%.nt: $(WORK_DIR)/class/%.tsv $(OUT_DIR)/class | $(SKOS_LABELS_NT) $(PROPS_P279_NT) $(PROPS_P361_NT)
	$(call generate_skos_nt,$<,$@,class)

$(WORK_DIR)/class.nt: $(OUT_DIR)/class | $(patsubst $(ROOT_DIR)/class/%.tsv,$(OUT_DIR)/class/%.nt,$(CLASS_FILES))
	cat $</*.nt | LC_ALL=C sort -u >> $@

# Reusable training split generator
define split_file
	input="$(2)"; \
	dir=$$(dirname "$$input"); \
	base=$$(basename "$$input" .tsv); \
	total_lines=$$(wc -l < "$(1)"); \
	test_lines=$$((total_lines * 10 / 100)); \
	eval_lines=$$((total_lines * 10 / 100)); \
	shuf "$(1)" | awk -v test_lines="$$test_lines" -v eval_lines="$$eval_lines" -v dir="$$dir" -v base="$$base" '{if (NR<=test_lines) print > (dir "/" base "-test.tsv"); else if (NR<=test_lines+eval_lines) print > (dir "/" base "-eval.tsv"); else print > (dir "/" base "-train.tsv")}'
endef

# Make fulltext output for each class
$(WORK_FULLTEXT)/class/%.tsv: $(WORK_DIR)/class/%.tsv | $(SITELINKS_WD5M) $(WORK_FULLTEXT)/class
	LC_ALL=C join $< $(SITELINKS_WD5M) | sed -E 's/<([^>]+)> (.*)/\2\t<\1>/' > $@

# Make fulltext output for each occupation
$(WORK_FULLTEXT)/occupation/%.tsv: $(WORK_DIR)/occupation/%.tsv | $(SITELINKS_WD5M) $(WORK_FULLTEXT)/occupation
	LC_ALL=C join $< $(SITELINKS_WD5M) | sed -E 's/<([^>]+)> (.*)/\2\t<\1>/' > $@

# Generate fulltext for concept URI lists
$(WORK_FULLTEXT)/core.tsv: $(WORK_DIR)/core.tsv | $(SITELINKS_WD5M) $(WORK_FULLTEXT)
	LC_ALL=C join $< $(SITELINKS_WD5M) | sed -E 's/<([^>]+)> (.*)/\2\t<\1>/' > $@

# Generate test/train/eval splits for fulltext
$(OUT_FULLTEXT)/core.tsv: $(WORK_FULLTEXT)/core.tsv | $(OUT_FULLTEXT)
	$(call split_file,$<,$@)

$(OUT_FULLTEXT)/class/%.tsv: $(WORK_FULLTEXT)/class/%.tsv | $(OUT_FULLTEXT)/class
	$(call split_file,$<,$@)

$(OUT_FULLTEXT)/occupation/%.tsv: $(WORK_FULLTEXT)/occupation/%.tsv | $(OUT_FULLTEXT)/occupation
	$(call split_file,$<,$@)

# Reusable Annif project generator
# FIXME: fails to generate core vocab name correctly (prefix behaviour)
define generate_project
	subdir=$$(basename $(1) .tsv); \
	echo "" >> $@; \
	echo "[wikicore_$(LOCALE)_$(BACKEND)_$(2)_$$subdir]" >> $@; \
	echo "name = WikiCore $(BACKEND) $(2) $$subdir ($(LOCALE))" >> $@; \
	echo "backend = $(BACKEND)" >> $@; \
	echo "language = $(LOCALE)" >> $@; \
	echo "analyzer = snowball(english)" >> $@; \
	echo "limit = 100" >> $@; \
	echo "vocab = wikicore-$(RUN_DATE)-$(2)-$$subdir-$(LOCALE)" >> $@; \
	echo "" >> $@; \
	echo "[wikicore_$(LOCALE)_filter_$(2)_$$subdir]" >> $@; \
	echo "name = WikiCore Filter $(2) $$subdir ($(LOCALE))" >> $@; \
	echo "backend = threshold_ensemble" >> $@; \
	echo "threshold = 0" >> $@; \
	echo "language = $(LOCALE)" >> $@; \
	echo "sources = wikicore_$(LOCALE)_$(BACKEND)_$(2)_$$subdir" >> $@; \
	echo "vocab = wikicore-$(RUN_DATE)-$(2)-$(LOCALE)(exclude=*,include_scheme=$(VOCAB_URI)/$(2)/$$subdir)" >> $@; \
	echo "# Vocab size: $$(wc -l < $(1))" >> $@
endef

define generate_ensemble
	group=$(1); \
	sources=$$(echo "$$group" | awk -F'\t' -v prefix="wikicore_$(LOCALE)_filter_$(2)_" '{for(i=1;i<=NF;i++){if($$i != ""){printf "%s%s", prefix $$i, (i<NF && $$(i+1) != ""?",":"")}}}'); \
	echo "" >> $@; \
	echo "[wikicore_$(LOCALE)_ensemble_$(2)]" >> $@; \
	echo "name = WikiCore Ensemble $(2) ($(LOCALE))" >> $@; \
	echo "backend = ensemble" >> $@; \
	echo "language = $(LOCALE)" >> $@; \
	echo "limit = 100" >> $@; \
	echo "sources = $$sources" >> $@; \
	echo "vocab = wikicore-$(RUN_DATE)-$(2)-$(LOCALE)" >> $@
endef

$(ANNIF_PROJECTS)/projects_class.cfg: $(WORK_DIR)/class | $(ANNIF_PROJECTS)
	@classes=''; \
	for a in $</*; do \
		classes="$$classes$$(basename "$$a" .tsv)	"; \
		$(call generate_project,$$a,class); \
	done; \
	$(call generate_ensemble,$$classes,class);

$(ANNIF_PROJECTS)/projects_occupation.cfg: $(WORK_DIR)/occupation | $(ANNIF_PROJECTS)
	@occupations=''; \
	for a in $</*; do \
		occupations="$$occupations$$(basename "$$a" .tsv)	"; \
		$(call generate_project,$$a,occupation); \
	done; \
	$(call generate_ensemble,$$occupations,occupation);

$(ANNIF_PROJECTS)/projects_core.cfg: $(WORK_DIR)/core.tsv | $(ANNIF_PROJECTS)
	$(call generate_project,$<,core)

extract_vars_2 = $(shell echo $(1) | sed -E 's|.*/([^/]*)/([^-]*).nt|\1 \2|')

define annif_load
	$(eval extracted = $(call extract_vars_2,$(1)))
	$(eval prefix = $(word 1,$(extracted)))
	$(eval class = $(word 2,$(extracted)))

	$(if $(filter-out $(shell basename $(OUT_DIR)),$(prefix)),\
		$(eval vocab = wikicore-$(RUN_DATE)-$(prefix)-$(class)-$(LOCALE)),\
		$(eval vocab = wikicore-$(RUN_DATE)-$(class)-$(LOCALE))\
	)

	annif load-vocab -p $(ANNIF_PROJECTS) -f -v DEBUG -L $(LOCALE) $(vocab) $<
endef

extract_vars = $(shell echo $(1) | sed -E 's|.*/([^/]*)/([^-]*)-train.tsv|\1 \2|')

define annif_train
	$(eval extracted = $(call extract_vars,$(1)))
	$(eval prefix = $(word 1,$(extracted)))
	$(eval class = $(word 2,$(extracted)))

	$(if $(filter-out fulltext,$(prefix)),\
		$(eval project = wikicore_$(LOCALE)_$(BACKEND)_$(prefix)_$(class)),\
		$(eval project = wikicore_$(LOCALE)_$(BACKEND)_$(class))\
	)

	annif train -p $(ANNIF_PROJECTS) -v DEBUG $(project) $<
	annif eval  -p $(ANNIF_PROJECTS) -v DEBUG $(project) `echo $< | sed 's/train/eval/g'` -M $(ANNIF_EVAL)/$(project).json
endef

$(ANNIF_PROJECTS)/.loaded_%: $(OUT_DIR)/%.nt | $(ANNIF_PROJECTS)
	$(call annif_load,$<)
	touch $@

$(ANNIF_PROJECTS)/.loaded_class_%: $(OUT_DIR)/class/%.nt | $(ANNIF_PROJECTS)
	$(call annif_load,$<)
	touch $@

$(ANNIF_PROJECTS)/.loaded_occupation_%: $(OUT_DIR)/occupation/%.nt | $(ANNIF_PROJECTS)
	$(call annif_load,$<)
	touch $@

$(ANNIF_PROJECTS)/.trained_%: $(OUT_FULLTEXT)/%-train.tsv | $(OUT_FULLTEXT)
	$(call annif_train,$<)
	touch $@

$(ANNIF_PROJECTS)/.trained_class_%: $(OUT_FULLTEXT)/class/%-train.tsv | $(OUT_FULLTEXT)/class
	$(call annif_train,$<)
	touch $@

$(ANNIF_PROJECTS)/.trained_occupation_%: $(OUT_FULLTEXT)/occupation/%-train.tsv | $(OUT_FULLTEXT)/occupation
	$(call annif_train,$<)
	touch $@