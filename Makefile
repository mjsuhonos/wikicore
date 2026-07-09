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

ANNIF_DIR        := $(OUT_DIR)/annif
FULLTEXT_DIR     := $(OUT_DIR)/fulltext

$(WORK_DIR) $(OUT_DIR) $(WORK_DIR)/occupation $(OUT_DIR)/occupation $(WORK_DIR)/class $(OUT_DIR)/class:
	mkdir -p $@

$(FULLTEXT_DIR) $(ANNIF_DIR) $(FULLTEXT_DIR)/class $(FULLTEXT_DIR)/occupation  $(FULLTEXT_DIR)/splits $(FULLTEXT_DIR)/splits/class $(FULLTEXT_DIR)/splits/occupation:
	mkdir -p $@

# Inputs
CLEANED_GZ       := $(SOURCE_DIR)/wikidata-20251229-cleaned.gz
SITELINKS_GZ     := $(SOURCE_DIR)/sitelinks_en.tsv.gz
FULLTEXT_GZ      := $(SOURCE_DIR)/wikidata5m_text.txt.gz

# Extracted gzip files
SITELINKS_FILE   := $(WORK_DIR)/sitelinks_en_uris.tsv
SITELINKS_NT     := $(WORK_DIR)/wikidata-sitelinks.nt
SITELINKS_WD5M   := $(WORK_DIR)/sitelinks_wd5m.tsv

# 1. Extract URIs with Wikipedia sitelinks (~11M filter)
$(SITELINKS_FILE): $(SITELINKS_GZ) | $(WORK_DIR) $(OUT_DIR)
	pigz -dc $< | awk '{print $$1}' | LC_ALL=C sort -u > $@

# 2. Extract N-triples with subject URIs having sitelinks (~28M total)
# FIXME: slow! perhaps chunk and parallelize?
$(SITELINKS_NT): $(CLEANED_GZ) $(SITELINKS_FILE)
	pigz -dc $< \
		| rg -e '/prop/direct/P31>' -e '/prop/direct/P279>' -e '/prop/direct/P361>' -e '/prop/direct/P106>' -e 'skos/core#.*"@$(LOCALE) \.' \
		| rg -F -v '_:' \
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
	rg 'skos/core#.*"@$(LOCALE) \.' $< | LC_ALL=C sort -u > $@

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
	LC_ALL=C join $1 $(PROPS_P361_NT) | sed 's|<http://www.wikidata.org/prop/direct/P361>|<http://www.w3.org/2004/02/skos/core#broader>|g' >> $2
	LC_ALL=C join $1 $(PROPS_P279_NT) | sed 's|<http://www.wikidata.org/prop/direct/P279>|<http://www.w3.org/2004/02/skos/core#broader>|g' >> $2
endef

# Generate URI lists for each concept (non-instance)
$(WORK_DIR)/core.tsv: $(SKOS_LABELS_NT) $(PROPS_P279_NT) $(PROPS_P361_NT)
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
$(FULLTEXT_DIR)/class/%.tsv: $(WORK_DIR)/class/%.tsv | $(SITELINKS_WD5M) $(FULLTEXT_DIR)/class
	LC_ALL=C join $< $(SITELINKS_WD5M) | sed -E 's/<([^>]+)> (.*)/\2\t<\1>/' > $@

# Make fulltext output for each occupation
$(FULLTEXT_DIR)/occupation/%.tsv: $(WORK_DIR)/occupation/%.tsv | $(SITELINKS_WD5M) $(FULLTEXT_DIR)/occupation
	LC_ALL=C join $< $(SITELINKS_WD5M) | sed -E 's/<([^>]+)> (.*)/\2\t<\1>/' > $@

# Generate fulltext for concept URI lists
$(FULLTEXT_DIR)/core.tsv: $(WORK_DIR)/core.tsv | $(SITELINKS_WD5M) $(FULLTEXT_DIR)
	LC_ALL=C join $< $(SITELINKS_WD5M) | sed -E 's/<([^>]+)> (.*)/\2\t<\1>/' > $@

# Generate test/train/eval splits for fulltext
$(FULLTEXT_DIR)/splits/core.tsv: $(FULLTEXT_DIR)/core.tsv | $(FULLTEXT_DIR)/splits
	$(call split_file,$<,$@)

$(FULLTEXT_DIR)/splits/class/%.tsv: $(FULLTEXT_DIR)/class/%.tsv | $(FULLTEXT_DIR)/splits/class
	$(call split_file,$<,$@)

$(FULLTEXT_DIR)/splits/occupation/%.tsv: $(FULLTEXT_DIR)/occupation/%.tsv | $(FULLTEXT_DIR)/splits/occupation
	$(call split_file,$<,$@)

# GZip files so they're small enough to commit to GitHub
compress:
	find $(OUT_DIR) -maxdepth 2 -type f -name "*.nt" -exec pigz -k -f {} \;
	find $(FULLTEXT_DIR) -maxdepth 2 -type f -name "*.tsv" -exec pigz -k -f {} \;

# -----------------------
# Reusable Annif project generator
# -----------------------
BACKEND   := yake
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

# -----------------------
# Main targets
# -----------------------
core:       $(OUT_DIR)/core.nt
class:      $(OUT_DIR)/class.nt
occupation: $(OUT_DIR)/occupation.nt

fulltext:   $(patsubst $(ROOT_DIR)/class/%.tsv,$(FULLTEXT_DIR)/class/%.tsv,$(CLASS_FILES)) \
			$(patsubst $(ROOT_DIR)/occupation/%.tsv,$(FULLTEXT_DIR)/occupation/%.tsv,$(OCCUPATION_FILES)) \
			$(FULLTEXT_DIR)/core.tsv \

splits: 	$(patsubst $(ROOT_DIR)/class/%.tsv,$(FULLTEXT_DIR)/splits/class/%.tsv,$(CLASS_FILES)) \
			$(patsubst $(ROOT_DIR)/occupation/%.tsv,$(FULLTEXT_DIR)/splits/occupation/%.tsv,$(OCCUPATION_FILES)) \
			$(FULLTEXT_DIR)/splits/core.tsv \

annif:		$(ANNIF_DIR)/projects_class.cfg \
			$(ANNIF_DIR)/projects_occupation.cfg \
			$(ANNIF_DIR)/projects_core.cfg \

all: core class occupation fulltext splits annif
	@echo "  LOCALE=$(LOCALE)"
	@echo "  RUN_DATE=$(RUN_DATE)"
