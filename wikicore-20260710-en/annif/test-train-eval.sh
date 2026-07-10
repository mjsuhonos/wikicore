#!/bin/bash
annif load-vocab 'wikicore-20260710-core-en' '/Users/mjsuhonos/Documents/GitHub/wikicore2/wikicore-20260710-en/core.nt'
annif train 'wikicore_en_mllm_*train.tsv' '/Users/mjsuhonos/Documents/GitHub/wikicore2/wikicore-20260710-en/fulltext/splits/*train.tsv'
annif eval 'wikicore_en_mllm_*train.tsv' '/Users/mjsuhonos/Documents/GitHub/wikicore2/wikicore-20260710-en/fulltext/splits/*eval.tsv' -M 'data/eval/20260710_wikicore_en_mllm_*train.tsv.json'
annif train 'wikicore_en_mllm_class_*train.tsv' '/Users/mjsuhonos/Documents/GitHub/wikicore2/wikicore-20260710-en/fulltext/splits/class/*train.tsv'
annif eval 'wikicore_en_mllm_class_*train.tsv' '/Users/mjsuhonos/Documents/GitHub/wikicore2/wikicore-20260710-en/fulltext/splits/class/*eval.tsv' -M 'data/eval/20260710_wikicore_en_mllm_class_*train.tsv.json'
annif train 'wikicore_en_mllm_occupation_*train.tsv' '/Users/mjsuhonos/Documents/GitHub/wikicore2/wikicore-20260710-en/fulltext/splits/occupation/*train.tsv'
annif eval 'wikicore_en_mllm_occupation_*train.tsv' '/Users/mjsuhonos/Documents/GitHub/wikicore2/wikicore-20260710-en/fulltext/splits/occupation/*eval.tsv' -M 'data/eval/20260710_wikicore_en_mllm_occupation_*train.tsv.json'
