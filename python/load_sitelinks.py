#!/usr/bin/env python3
"""
load_sitelinks.py
Load sitelink information into Jena TDB as :hasSitelink properties
Usage:
    load_sitelinks.py <sitelinks_file> <jena_dir>
"""

import sys
from pathlib import Path
import tempfile
import subprocess

sitelinks_file = Path(sys.argv[1])
jena_dir = Path(sys.argv[2])

# Create a temporary SPARQL update file
temp_file = tempfile.NamedTemporaryFile(mode='w', suffix='.rq', delete=False)

print(f"Loading sitelinks from {sitelinks_file} into {jena_dir}")

# Write SPARQL INSERT statements for each QID with sitelinks
temp_file.write("""PREFIX : <http://example.org/ontology/>

INSERT DATA {
""")

count = 0
with open(sitelinks_file) as f:
    for line in f:
        qid_uri = line.strip()
        if qid_uri.startswith('<http://www.wikidata.org/entity/') and qid_uri.endswith('>'):
            temp_file.write(f"  {qid_uri} :hasSitelink \"true\" .\n")
            count += 1
            if count % 100000 == 0:
                print(f"Processed {count} sitelinks...")

temp_file.write("}\n")
temp_file.close()

print(f"Generated SPARQL update with {count} sitelink assertions")

# Apply the update to Jena
try:
    result = subprocess.run([
        'tdb2.tdbupdate', 
        '--loc', str(jena_dir),
        '--update', temp_file.name
    ], capture_output=True, text=True)
    
    if result.returncode == 0:
        print("Successfully loaded sitelinks into Jena")
    else:
        print(f"Error loading sitelinks: {result.stderr}")
        sys.exit(1)
        
finally:
    # Clean up temp file
    Path(temp_file.name).unlink()