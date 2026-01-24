#!/bin/zsh

# Usage: ./extract_and_count_fast.sh wikidata-20251229-whitelist.nt [output.txt]

INPUT_FILE="$1"
OUTPUT_FILE="$2"

if [[ -z "$INPUT_FILE" ]]; then
  echo "Usage: $0 <input_file.nt> [output_file.txt]"
  exit 1
fi

# Detect CPU cores
CPU_CORES=$(sysctl -n hw.ncpu)

# Detect total RAM in GB
TOTAL_RAM_BYTES=$(sysctl -n hw.memsize)
TOTAL_RAM_GB=$((TOTAL_RAM_BYTES / 1024 / 1024 / 1024))

# Allocate RAM: 1/8th per chunk for parallel processing, rest for final sort
CHUNK_RAM_GB=$(( TOTAL_RAM_GB / 8 ))
FINAL_SORT_RAM_GB=$(( TOTAL_RAM_GB - CHUNK_RAM_GB * CPU_CORES ))

# Safety checks
[[ $FINAL_SORT_RAM_GB -le 4 ]] && FINAL_SORT_RAM_GB=4
[[ $CHUNK_RAM_GB -le 1 ]] && CHUNK_RAM_GB=1

echo "Processing $INPUT_FILE with $CPU_CORES cores..."
#echo "Chunk RAM per parallel task: ${CHUNK_RAM_GB}G"
#echo "Final sort RAM: ${FINAL_SORT_RAM_GB}G"

# Build the pipeline
PIPELINE="parallel --pipepart -a \"$INPUT_FILE\" -j $CPU_CORES \"awk '{print \\\$1}' | sort -u -S ${CHUNK_RAM_GB}G\" | sort -u -S ${FINAL_SORT_RAM_GB}G --parallel=$CPU_CORES"

if [[ -n "$OUTPUT_FILE" ]]; then
  # Stream to both file and line count in one pass
  TOTAL_LINES=$(eval "$PIPELINE" | tee "$OUTPUT_FILE" | parallel --pipe "wc -l" | awk '{s+=$1} END {print s}')
  echo "Unique subjects saved to $OUTPUT_FILE"
else
  # Stream to stdout and line count
  TOTAL_LINES=$(eval "$PIPELINE" | tee /dev/tty | parallel --pipe "wc -l" | awk '{s+=$1} END {print s}')
fi

echo "Total unique subjects: $TOTAL_LINES"
