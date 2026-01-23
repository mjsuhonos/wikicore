#!/bin/zsh

# run in working directory

#mkdir jena
#mkdir nt
#mkdir subjects

# extract only the properties we're interested in
gzcat ../source/wikidata-20251229-propdirect.nt | rg '/prop/direct/(P31|P279|P361)>' > wikicore-stage1-P31_P279_P361.nt

# separate P31 statements out by type
cd nt
mawk -v OFS=' ' '
function trim(s){ gsub(/^[ \t]+|[ \t]+$/, "", s); return s }
BEGIN {
    # Load class names TSV
    while ((getline < "../../class_names.tsv") > 0)
        class_names[trim($1)] = trim($2)
    close("../../class_names.tsv")
}
{
    subj=$1; pred=$2; obj=$3
    gsub(/[<>]/,"",subj); gsub(/[<>]/,"",pred); gsub(/[<>]/,"",obj)

    if (pred ~ /prop\/direct\/P31$/) {
        # Extract QID quickly (everything after last /)
        qid = obj
        sub(".*/","",qid)

        f = (qid in class_names) ? qid"_"class_names[qid]".nt" : "misc_p31_other.nt"
    } else {
        f = "concept_backbone.nt"
    }

    print $0 >> f
    out[f]  # mark file handle
}
END {
    for (f in out) close(f)
}
' ../wikicore-stage1-P31_P279_P361.nt

# extract all subjects and create QID lists
# NB: these can be used as separate vocabularies in combination
for a in Q*.nt; do ../../extract_unique_subjects.sh $a ../subjects/$a.tsv ; done


#
# ----------------FOLD ALONG THIS LINE -------------------
#



# Load structural graph into Jena
cd ../jena
tdb2.tdbloader --loc /Users/mjsuhonos/Desktop/Wikidata-vocabs/working.nosync/jena /Users/mjsuhonos/Desktop/Wikidata-vocabs/working.nosync/nt/concept_backbone.nt

# Calculate query optimizations
tdb2.tdbupdate --loc /Users/mjsuhonos/Desktop/Wikidata-vocabs/working.nosync/jena --update=queries/materialize_graph.rq

# Export entities based on query
tdb2.tdbquery --loc /Users/mjsuhonos/Desktop/Wikidata-vocabs/working.nosync/jena --query=queries/export.rq --results=TSV > core_vocab.tsv

# Clean up and sort entities for joining
rg '<http://www.wikidata.org/entity' core_vocab.tsv| sort > ../wikicore-stage2_core_concepts.tsv






#
# ----------------DETACH HERE -------------------
#

# Combine excluded instances and remove them
# TODO: optimize; uses 16GB RAM, maybe parallelize?

# Usage: ./join_subjects_labels.sh subjects_unique.txt labels.nt output_joined.txt

cd ..
cat subjects/*.tsv | sort -u | join -v 1 wikicore-stage2_core_concepts.tsv - > wikicore-stage3-P31_removed.tsv

# create skos:Concept statements from QIDs
sed -E 's|(.*)|\1 <http://www.w3.org/1999/02/22-rdf-syntax-ns#type> <http://www.w3.org/2004/02/skos/core#Concept> .|' wikicore-stage3-P31_removed.tsv > wikicore-stage4-statements.nt

# create skos:Collection statements from QIDs
echo '<http://example.org/wikicore-20160122> <http://www.w3.org/1999/02/22-rdf-syntax-ns#type> <http://www.w3.org/2004/02/skos/core#Collection> .' > wikicore-stage4-collection.nt
sed -E 's|(.*)|<http://example.org/wikicore-20160122> <http://www.w3.org/2004/02/skos/core#member> \1 .|' wikicore-stage3-P31_removed.tsv >> wikicore-stage4-collection.nt

# join with skos labels
# NB: language can be selected here
gzcat ../source/wikidata-20251229-skos-labels-en.nt.gz | join -  wikicore-stage3-P31_removed.tsv > wikicore-stage4-skos-en.nt

# create turtle output ready to load
cat wikicore-stage4* | rapper -i ntriples -o turtle - -I 'http://www.wikidata.org/entity/' > wikicore.ttl


