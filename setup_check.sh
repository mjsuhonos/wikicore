#!/bin/bash
# setup_check.sh
# Validate that all prerequisites are in place before running the pipeline

set -e

echo "========================================"
echo "Wiki Core Setup Validation"
echo "========================================"
echo ""

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

ERRORS=0
WARNINGS=0

check_command() {
    if command -v $1 &> /dev/null; then
        echo -e "${GREEN}✓${NC} $1 is installed"
        if [ ! -z "$2" ]; then
            VERSION=$($1 $2 2>&1 | head -1)
            echo "  Version: $VERSION"
        fi
    else
        echo -e "${RED}✗${NC} $1 is NOT installed"
        echo "  Install: $3"
        ((ERRORS++))
    fi
}

check_file() {
    if [ -f "$1" ]; then
        SIZE=$(du -h "$1" | cut -f1)
        echo -e "${GREEN}✓${NC} $1 exists ($SIZE)"
    else
        echo -e "${RED}✗${NC} $1 is missing"
        echo "  Expected: $2"
        ((ERRORS++))
    fi
}

check_directory() {
    if [ -d "$1" ]; then
        COUNT=$(ls "$1" 2>/dev/null | wc -l)
        echo -e "${GREEN}✓${NC} $1 exists ($COUNT files)"
    else
        echo -e "${YELLOW}⚠${NC} $1 does not exist"
        echo "  Note: $2"
        ((WARNINGS++))
    fi
}

echo "1. Checking required commands..."
echo "-----------------------------------"
check_command "gsplit" "--version" "GNU coreutils (brew install coreutils on macOS)"
check_command "pigz" "--version" "pigz (brew install pigz)"
check_command "rg" "--version" "ripgrep (brew install ripgrep)"
check_command "parallel" "--version" "GNU parallel (brew install parallel)"
check_command "python3" "--version" "Python 3"
check_command "awk" "--version" "awk (usually pre-installed)"
check_command "sort" "--version" "sort (usually pre-installed)"
check_command "join" "--version" "join (usually pre-installed)"
check_command "tdb2.tdbloader" "--version" "Apache Jena (download from https://jena.apache.org/)"
check_command "tdb2.tdbquery" "--version" "Apache Jena"
check_command "tdb2.tdbupdate" "--version" "Apache Jena"
echo ""

echo "2. Checking directory structure..."
echo "-----------------------------------"
check_directory "source.nosync" "Will be created if missing, but you need to add data files"
check_directory "queries" "Required! Should contain SPARQL queries"
check_directory "working.nosync" "Will be created automatically"
check_directory "working.nosync/buckets_qid" "Will be generated from backbone data"
echo ""

echo "3. Checking required data files..."
echo "-----------------------------------"
check_file "source.nosync/wikidata-*-propdirect.nt.gz" "Wikidata property direct dump (~100GB compressed)"
check_file "source.nosync/wikidata-*-skos-labels-*.nt.gz" "Wikidata SKOS labels dump (~50GB compressed)"
check_file "source.nosync/sitelinks_*_qids.tsv" "Wikipedia sitelinks file (TSV format)"
echo ""

echo "4. Checking required SPARQL queries..."
echo "-----------------------------------"
check_file "queries/materialize_ancestors.rq" "SPARQL UPDATE query for transitive closure"
check_file "queries/materialize_child_counts.rq" "SPARQL UPDATE query for child counts"
check_file "queries/export.rq" "SPARQL SELECT query for exporting concepts"
echo ""

echo "5. Checking Python scripts..."
echo "-----------------------------------"
check_file "partition_all_chunks.py" "Main partitioning script"
echo ""

echo "6. Checking system resources..."
echo "-----------------------------------"
# Check available memory
if command -v free &> /dev/null; then
    TOTAL_MEM=$(free -g | awk '/^Mem:/ {print $2}')
    echo "Total memory: ${TOTAL_MEM}GB"
    if [ $TOTAL_MEM -lt 32 ]; then
        echo -e "${YELLOW}⚠${NC} Less than 32GB RAM available"
        echo "  Recommendation: 32GB minimum, 64GB recommended"
        ((WARNINGS++))
    else
        echo -e "${GREEN}✓${NC} Sufficient memory (${TOTAL_MEM}GB >= 32GB)"
    fi
elif command -v sysctl &> /dev/null; then
    # macOS
    TOTAL_MEM=$(($(sysctl -n hw.memsize) / 1024 / 1024 / 1024))
    echo "Total memory: ${TOTAL_MEM}GB"
    if [ $TOTAL_MEM -lt 32 ]; then
        echo -e "${YELLOW}⚠${NC} Less than 32GB RAM available"
        echo "  Recommendation: 32GB minimum, 64GB recommended"
        ((WARNINGS++))
    else
        echo -e "${GREEN}✓${NC} Sufficient memory (${TOTAL_MEM}GB >= 32GB)"
    fi
else
    echo -e "${YELLOW}⚠${NC} Could not determine available memory"
    ((WARNINGS++))
fi

# Check CPU cores
CORES=$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo "unknown")
echo "CPU cores: $CORES"
if [ "$CORES" != "unknown" ] && [ $CORES -lt 4 ]; then
    echo -e "${YELLOW}⚠${NC} Less than 4 cores available"
    echo "  Recommendation: 8+ cores for good performance"
    ((WARNINGS++))
else
    echo -e "${GREEN}✓${NC} Sufficient CPU cores"
fi

# Check available disk space
AVAILABLE=$(df -h . | awk 'NR==2 {print $4}')
echo "Available disk space: $AVAILABLE"
echo "  Note: Pipeline requires ~800GB total"
echo ""

echo "7. Environment variables..."
echo "-----------------------------------"
if [ -z "$JENA_JAVA_OPTS" ]; then
    echo -e "${YELLOW}⚠${NC} JENA_JAVA_OPTS not set"
    echo "  Recommendation: export JENA_JAVA_OPTS=\"-Xmx32g -XX:ParallelGCThreads=\$(nproc)\""
    ((WARNINGS++))
else
    echo -e "${GREEN}✓${NC} JENA_JAVA_OPTS=$JENA_JAVA_OPTS"
fi
echo ""

echo "========================================"
echo "Validation Summary"
echo "========================================"
if [ $ERRORS -eq 0 ] && [ $WARNINGS -eq 0 ]; then
    echo -e "${GREEN}✓ All checks passed!${NC}"
    echo "You can proceed with: make all"
elif [ $ERRORS -eq 0 ]; then
    echo -e "${YELLOW}⚠ $WARNINGS warning(s) found${NC}"
    echo "Pipeline should work, but review warnings above"
else
    echo -e "${RED}✗ $ERRORS error(s) found${NC}"
    echo -e "${YELLOW}⚠ $WARNINGS warning(s) found${NC}"
    echo ""
    echo "Please resolve errors before running the pipeline"
    exit 1
fi
echo ""

echo "Next steps:"
echo "1. Review any warnings above"
echo "2. Ensure bucket files are generated (see README_WORKFLOW.md)"
echo "3. Run: make all"
echo "4. Or run step-by-step to debug"
echo ""
