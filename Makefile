# -----------------------
# Wiki Core processing pipeline
# -----------------------

SHELL := /bin/bash
.SHELLFLAGS := -o pipefail -c

# -----------------------
# Options
# -----------------------
LOCALE    ?= en
RUN_DATE  := $(shell date +%Y%m%d)
VOCAB_URI := https://wikicore.ca/$(RUN_DATE)

# Paths
ROOT_DIR         := $(PWD)
SOURCE_DIR       := $(ROOT_DIR)/source.nosync
WORK_DIR         := $(ROOT_DIR)/working.nosync
OUT_DIR          := $(ROOT_DIR)/wikicore-$(RUN_DATE)-$(LOCALE)

WORK_FULLTEXT    := $(WORK_DIR)/fulltext
OUT_FULLTEXT     := $(OUT_DIR)/fulltext
ANNIF_DIR        := $(OUT_DIR)/annif
EVAL_DIR         := $(OUT_DIR)/data/eval

$(WORK_DIR) $(WORK_DIR)/occupation $(WORK_DIR)/class $(WORK_FULLTEXT) $(WORK_FULLTEXT)/class $(WORK_FULLTEXT)/occupation:
	mkdir -p $@

$(OUT_DIR) $(OUT_DIR)/occupation $(OUT_DIR)/class $(OUT_FULLTEXT) $(OUT_FULLTEXT)/class $(OUT_FULLTEXT)/occupation:
	mkdir -p $@

$(ANNIF_DIR):
	mkdir -p $@

# Inputs
WIKIDATA_GZ      := $(SOURCE_DIR)/sitelinks_wikidata.nt.gz # eg. wikidata-20260706-all.nt.gz
SITELINKS_GZ     := $(SOURCE_DIR)/sitelinks_en.tsv.gz
FULLTEXT_GZ      := $(SOURCE_DIR)/wikidata5m_text.txt.gz

# Extracted gzip files
SITELINKS_FILE   := $(WORK_DIR)/sitelinks_en_uris.tsv
SITELINKS_NT     := $(WORK_DIR)/sitelinks_wikidata.nt
SITELINKS_WD5M   := $(WORK_DIR)/sitelinks_wd5m.tsv

# 1. Extract URIs with Wikipedia sitelinks (~11M filter)
$(SITELINKS_FILE): $(SITELINKS_GZ) | $(WORK_DIR) $(OUT_DIR)
	pigz -dc $< | awk '{print $$1}' | LC_ALL=C sort -u > $@

# 2. Extract N-triples with subject URIs having sitelinks (~28M total)
# FIXME: slow! perhaps chunk and parallelize?
$(SITELINKS_NT): $(WIKIDATA_GZ) $(SITELINKS_FILE)
	pigz -dc $< \
		| rg -e '/prop/direct/(P31|P279|P361|P106)>|skos/core#.*"@(mul|$(LOCALE)) \.' \
		| awk -v sf=$(SITELINKS_FILE) 'BEGIN{while((getline<sf)>0)sl[$$1]=1}{if($$1 in sl)print}' \
		> $@

# Extract URIs with (EN) Wikipedia fulltext (~5M filter)
$(SITELINKS_WD5M): $(FULLTEXT_GZ)
	pigz -dc $< | sed -E 's/^([^\t]+)\t(.*)/<http:\/\/www.wikidata.org\/entity\/\1>\t\2/' \
		| awk -v sf=$(SITELINKS_FILE) 'BEGIN{while((getline<sf)>0)sl[$$1]=1}{if($$1 in sl)print}' \
		| LC_ALL=C sort -u \
		> $@

# -----------------------
# Wikidata files
# -----------------------
SKOS_LABELS_NT   := $(WORK_DIR)/wikicore-skos-labels-$(LOCALE).nt
PROPS_P31_NT     := $(WORK_DIR)/wikicore-P31.nt
PROPS_P106_NT    := $(WORK_DIR)/wikicore-P106.nt
PROPS_P279_NT    := $(WORK_DIR)/wikicore-P279.nt
PROPS_P361_NT    := $(WORK_DIR)/wikicore-P361.nt

# 3. Extract localized labels (~14M English)
$(SKOS_LABELS_NT): $(SITELINKS_NT)
	rg 'skos/core#.*"@(mul|$(LOCALE)) \.' $< | sed 's/@mul/@$(LOCALE)/g' | LC_ALL=C sort -u > $@

# 4. Extract subclass_of (core) properties (~428K)
$(PROPS_P279_NT): $(SITELINKS_NT)
	rg -F -e '/prop/direct/P279>' $< | LC_ALL=C sort -u > $@

# 4. Extract part_of (core) properties (~475K)
$(PROPS_P361_NT): $(SITELINKS_NT)
	rg -F -e '/prop/direct/P361>' $< | LC_ALL=C sort -u > $@

# 4. Extract instance_of (class) properties (~10M)
$(PROPS_P31_NT): $(SITELINKS_NT)
	rg -F -e '/prop/direct/P31>' $< | LC_ALL=C sort -u > $@

# 4. Extract occupation properties (~3.3M)
$(PROPS_P106_NT): $(SITELINKS_NT)
	rg -F -e '/prop/direct/P106>' $< | LC_ALL=C sort -u > $@

# -----------------------
# Reusable SKOS generator
# -----------------------
define generate_skos_nt
	BASE="$$(basename $1 .tsv)" ; \
	if [ -n "$3" ]; then SUBJECT_URI="$(VOCAB_URI)/$3"; else SUBJECT_URI="$(VOCAB_URI)"; fi ; \
	echo "<$$SUBJECT_URI/$$BASE> <http://www.w3.org/1999/02/22-rdf-syntax-ns#type> <http://www.w3.org/2004/02/skos/core#ConceptScheme> ." > $2 ; \
	sed "s|.*|& <http://www.w3.org/1999/02/22-rdf-syntax-ns#type> <http://www.w3.org/2004/02/skos/core#Concept> .\n& <http://www.w3.org/2004/02/skos/core#inScheme> <$$SUBJECT_URI/$$BASE> .|" $1 >> $2
	LC_ALL=C join $1 $(SKOS_LABELS_NT) >> $2
	if [ -z "$3" ]; then \
		LC_ALL=C join $1 $(PROPS_P361_NT) | sed 's|<http://www.wikidata.org/prop/direct/P361>|<http://www.w3.org/2004/02/skos/core#broader>|g' >> $2 ; \
		LC_ALL=C join $1 $(PROPS_P279_NT) | sed 's|<http://www.wikidata.org/prop/direct/P279>|<http://www.w3.org/2004/02/skos/core#broader>|g' >> $2 ; \
	fi
endef

# Generate URI lists for each concept (non-instance)
$(WORK_DIR)/core.tsv: $(SKOS_LABELS_NT) $(PROPS_P279_NT) $(PROPS_P361_NT) $(PROPS_P31_NT)
	cat $(PROPS_P279_NT) $(PROPS_P361_NT) | awk '{print $$1}' | LC_ALL=C sort -u | LC_ALL=C join -v 1 - $(PROPS_P31_NT) > $@

# Make SKOS output for core concepts
$(OUT_DIR)/core.nt: $(WORK_DIR)/core.tsv
	$(call generate_skos_nt,$<,$@)

# -----------------------
OCCUPATION_FILES := $(wildcard $(ROOT_DIR)/occupation/*.tsv)
# -----------------------
# Generate URI lists for each occupation
$(WORK_DIR)/occupation/%.tsv: $(ROOT_DIR)/occupation/%.tsv $(WORK_DIR)/occupation | $(PROPS_P106_NT) $(WORK_DIR)/occupation
	awk '{print $$1}' "$<" | xargs -I{} rg -F "{}> ." $(PROPS_P106_NT) | awk '{print $$1}' | LC_ALL=C sort -u > $@

$(WORK_DIR)/occupation.tsv: $(WORK_DIR)/occupation | $(patsubst $(ROOT_DIR)/occupation/%.tsv,$(WORK_DIR)/occupation/%.tsv,$(OCCUPATION_FILES))
	cat $</* | LC_ALL=C sort -u >> $@

# Make SKOS output for each occupation
$(OUT_DIR)/occupation/%.nt: $(WORK_DIR)/occupation/%.tsv $(OUT_DIR)/occupation | $(SKOS_LABELS_NT) $(PROPS_P279_NT) $(PROPS_P361_NT)
	$(call generate_skos_nt,$<,$@,occupation)

$(OUT_DIR)/occupation.nt: $(OUT_DIR)/occupation | $(patsubst $(ROOT_DIR)/occupation/%.tsv,$(OUT_DIR)/occupation/%.nt,$(OCCUPATION_FILES))
	cat $</* | LC_ALL=C sort -u >> $@

# -----------------------
CLASS_FILES := $(wildcard $(ROOT_DIR)/class/*.tsv)
# -----------------------
# Generate URI lists for each class
$(WORK_DIR)/class/%.tsv: $(ROOT_DIR)/class/%.tsv $(WORK_DIR)/class | $(PROPS_P31_NT) $(WORK_DIR)/class
	awk '{print $$1}' "$<" | xargs -I{} rg -F "{}> ." $(PROPS_P31_NT) | awk '{print $$1}' | LC_ALL=C sort -u > $@

$(WORK_DIR)/class.tsv: $(WORK_DIR)/class | $(patsubst $(ROOT_DIR)/class/%.tsv,$(WORK_DIR)/class/%.tsv,$(CLASS_FILES))
	cat $</* | LC_ALL=C sort -u >> $@

# Make SKOS output for each class
$(OUT_DIR)/class/%.nt: $(WORK_DIR)/class/%.tsv $(OUT_DIR)/class | $(SKOS_LABELS_NT) $(PROPS_P279_NT) $(PROPS_P361_NT)
	$(call generate_skos_nt,$<,$@,class)

$(OUT_DIR)/class.nt: $(OUT_DIR)/class | $(patsubst $(ROOT_DIR)/class/%.tsv,$(OUT_DIR)/class/%.nt,$(CLASS_FILES))
	cat $</* | LC_ALL=C sort -u >> $@

# -----------------------
# Reusable training split generator
# -----------------------
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

# -----------------------
# Reusable Annif project generator
# -----------------------
BACKEND   := dummy
define generate_project
	a=$(1); \
	prefix=$(2); \
	subdir=$$(basename "$$a" .tsv); \
	lines=$$(wc -l < "$$a"); \
	echo "" >> $@; \
	echo "[wikicore_$(LOCALE)_$(BACKEND)_$$prefix$${prefix:+_}$$subdir]" >> $@; \
	echo "name = WikiCore $(BACKEND) $$prefix$${prefix:+ }$$subdir ($(LOCALE))" >> $@; \
	echo "backend = $(BACKEND)" >> $@; \
	echo "language = $(LOCALE)" >> $@; \
	echo "analyzer = snowball(english)" >> $@; \
	echo "limit = 100" >> $@; \
	echo "vocab = wikicore-$(RUN_DATE)$${prefix:+-}$$prefix-$(LOCALE)(exclude=*,include_scheme=$(VOCAB_URI)$${prefix:+/}$${prefix}/$$subdir)" >> $@; \
	echo "# Vocab size: $$lines" >> $@
endef

define generate_ensemble
	group=$(1); \
	prefix=$(2); \
	sources=$$(echo "$$group" | awk -F'\t' -v prefix="wikicore_$(LOCALE)_$(BACKEND)_$(2)_" '{for(i=1;i<=NF;i++){if($$i != ""){printf "%s%s", prefix $$i, (i<NF && $$(i+1) != ""?",":"")}}}'); \
	vocab=$$(echo "$$group" | awk -F'\t' -v prefix="https://wikicore.ca/$(RUN_DATE)/$$prefix/" '{for(i=1;i<=NF;i++){if($$i != ""){printf "%s%s", prefix $$i, (i<NF && $$(i+1) != ""?"|":"")}}}'); \
	echo "" >> $@; \
	echo "[wikicore_$(LOCALE)_ensemble_$$prefix]" >> $@; \
	echo "name = WikiCore Ensemble $$prefix ($(LOCALE))" >> $@; \
	echo "backend = ensemble" >> $@; \
	echo "language = $(LOCALE)" >> $@; \
	echo "limit = 100" >> $@; \
	echo "sources = $$sources" >> $@; \
	echo "vocab = wikicore-$(RUN_DATE)-$$prefix-$(LOCALE)(exclude=*,include_scheme=$$vocab)" >> $@
endef

$(ANNIF_DIR)/projects_class.cfg: $(WORK_DIR)/class | $(ANNIF_DIR)
	@classes=''; \
	for a in $</*; do \
		classes="$$classes$$(basename "$$a" .tsv)	"; \
		$(call generate_project,$$a,class); \
	done; \
	$(call generate_ensemble,$$classes,class);

$(ANNIF_DIR)/projects_occupation.cfg: $(WORK_DIR)/occupation | $(ANNIF_DIR)
	@occupations=''; \
	for a in $</*; do \
		occupations="$$occupations$$(basename "$$a" .tsv)	"; \
		$(call generate_project,$$a,occupation); \
	done; \
	$(call generate_ensemble,$$occupations,occupation);

$(ANNIF_DIR)/projects_core.cfg: $(WORK_DIR)/core.tsv | $(ANNIF_DIR)
	$(call generate_project,$<)

$(ANNIF_DIR)/.annif_loaded: $(ROOT_DIR)
	#ln -s $(ANNIF_DIR) projects.d
	#python3 -m venv annif-venv
	#source annif-venv/bin/activate; \
	for a in $</*.nt; do \
		vocab=wikicore-$(RUN_DATE)-$$(basename "$$a" .nt)-$(LOCALE); \
		annif load-vocab -f -v DEBUG -L $(LOCALE) $$vocab $$a; \
	done
	touch $@

$(ANNIF_DIR)/.trained_%: $(OUT_FULLTEXT)/%-train.tsv | $(OUT_FULLTEXT)
	echo annif train "wikicore_$(LOCALE)_$(BACKEND)_$$(basename $< -train.tsv)" $<; \
	echo annif eval $$project $$(echo $< | sed 's/train/eval/g') -M $(EVAL_DIR)/$(RUN_DATE)_$$project.json

$(ANNIF_DIR)/.trained_class_%: $(OUT_FULLTEXT)/class/%-train.tsv | $(OUT_FULLTEXT)/class
	echo annif train "wikicore_$(LOCALE)_$(BACKEND)_class_$$(basename $< -train.tsv)" $<; \
	echo annif eval $$project $$(echo $< | sed 's/train/eval/g') -M $(EVAL_DIR)/$(RUN_DATE)_$$project.json

$(ANNIF_DIR)/.trained_occupation_%: $(OUT_FULLTEXT)/occupation/%-train.tsv | $(OUT_FULLTEXT)/occupation
	echo annif train "wikicore_$(LOCALE)_$(BACKEND)_occupation_$$(basename $< -train.tsv)" $<; \
	echo annif eval $$project $$(echo $< | sed 's/train/eval/g') -M $(EVAL_DIR)/$(RUN_DATE)_$$project.json

# -----------------------
# Main targets
# -----------------------
all: skos fulltext
	@echo "  LOCALE=$(LOCALE)"
	@echo "  RUN_DATE=$(RUN_DATE)"

core:		$(OUT_DIR)/core.nt
class:		$(OUT_DIR)/class.nt
occupation:	$(OUT_DIR)/occupation.nt
skos:		core class occupation

fulltext: 	$(OUT_FULLTEXT)/core.tsv \
			$(patsubst $(ROOT_DIR)/class/%.tsv,$(OUT_FULLTEXT)/class/%.tsv,$(CLASS_FILES)) \
			$(patsubst $(ROOT_DIR)/occupation/%.tsv,$(OUT_FULLTEXT)/occupation/%.tsv,$(OCCUPATION_FILES)) \

annif:		$(ANNIF_DIR)/projects_core.cfg \
			$(ANNIF_DIR)/projects_class.cfg \
			$(ANNIF_DIR)/projects_occupation.cfg \

load:		$(ANNIF_DIR)/.annif_loaded

train:		$(ANNIF_DIR)/.trained_core \
			$(patsubst $(ROOT_DIR)/class/%.tsv,$(ANNIF_DIR)/.trained_class_%,$(CLASS_FILES)) \
			$(patsubst $(ROOT_DIR)/occupation/%.tsv,$(ANNIF_DIR)/.trained_occupation_%,$(OCCUPATION_FILES)) \

# GZip files so they're small enough to commit to GitHub
compress: $(OUT_DIR) $(OUT_FULLTEXT)
	find $(OUT_DIR) -maxdepth 2 -type f -name "*.nt" -exec pigz -k -f {} \;
	find $(OUT_FULLTEXT) -maxdepth 2 -type f -name "*.tsv" -exec pigz -k -f {} \;

# Recreate working environment for Annif
decompress:
	find $(OUT_DIR) -maxdepth 3 -type f -name "*.gz" -exec pigz -dk -f {} \;
	cat $(OUT_DIR)/class/*.nt | LC_ALL=C sort -u > $(OUT_DIR)/class.nt \;
	cat $(OUT_DIR)/occupation/*.nt | LC_ALL=C sort -u > $(OUT_DIR)/occupation.nt \;