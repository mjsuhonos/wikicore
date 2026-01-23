select(.sitelinks.enwiki.title?)
| "<http://www.wikidata.org/entity/\(.id)>\thttps://en.wikipedia.org/wiki/\(.sitelinks.enwiki.title | gsub(" "; "_"))"
