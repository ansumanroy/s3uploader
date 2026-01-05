#!/bin/bash
# Generate test files of desired size for S3 upload testing
# Usage: ./create-test-file.sh [size] [output-file]
# Examples:
#   ./create-test-file.sh 10M
#   ./create-test-file.sh 100MB test-file.bin
#   ./create-test-file.sh 2G large-file.bin

set -e

# Check arguments
if [ $# -lt 1 ]; then
    echo "Usage: $0 <size> [output-file]"
    echo ""
    echo "Size can be specified with units:"
    echo "  b, B   - bytes"
    echo "  k, KB  - kilobytes"
    echo "  m, MB  - megabytes"
    echo "  g, GB  - gigabytes"
    echo ""
    echo "Examples:"
    echo "  $0 10M"
    echo "  $0 100MB test-file.bin"
    echo "  $0 2G large-file.bin"
    echo "  $0 1048576 1mb-file.bin"
    exit 1
fi

SIZE_ARG=$1
OUTPUT_FILE=${2:-""}

# Parse size and convert to bytes
parse_size() {
    local size_str=$1
    local size_val
    local size_unit
    
    # Extract numeric part and unit
    if [[ "$size_str" =~ ^([0-9]+)([a-zA-Z]+)$ ]]; then
        size_val=${BASH_REMATCH[1]}
        size_unit=${BASH_REMATCH[2],,}  # Convert to lowercase
    elif [[ "$size_str" =~ ^([0-9]+)$ ]]; then
        # If no unit specified, assume bytes
        size_val=$size_str
        size_unit="b"
    else
        echo "Error: Invalid size format: $size_str"
        echo "  Size must be a number followed by optional unit (b/k/m/g/B/KB/MB/GB)"
        exit 1
    fi
    
    # Convert to bytes based on unit
    case "$size_unit" in
        b|bytes)
            echo $size_val
            ;;
        k|kb)
            echo $((size_val * 1024))
            ;;
        m|mb)
            echo $((size_val * 1024 * 1024))
            ;;
        g|gb)
            echo $((size_val * 1024 * 1024 * 1024))
            ;;
        *)
            echo "Error: Unknown size unit: $size_unit"
            echo "  Supported units: b/k/m/g/B/KB/MB/GB"
            exit 1
            ;;
    esac
}

# Convert bytes to human-readable format
bytes_to_human() {
    local bytes=$1
    if [ $bytes -ge 1073741824 ]; then
        # Use numfmt if available, otherwise use bc, otherwise simple calculation
        if command -v numfmt &>/dev/null; then
            echo "$(numfmt --to=iec-i --suffix=B $bytes)"
        elif command -v bc &>/dev/null; then
            echo "$(echo "scale=2; $bytes / 1073741824" | bc)GB"
        else
            echo "$((bytes / 1073741824))GB"
        fi
    elif [ $bytes -ge 1048576 ]; then
        if command -v numfmt &>/dev/null; then
            echo "$(numfmt --to=iec-i --suffix=B $bytes)"
        elif command -v bc &>/dev/null; then
            echo "$(echo "scale=2; $bytes / 1048576" | bc)MB"
        else
            echo "$((bytes / 1048576))MB"
        fi
    elif [ $bytes -ge 1024 ]; then
        if command -v numfmt &>/dev/null; then
            echo "$(numfmt --to=iec-i --suffix=B $bytes)"
        elif command -v bc &>/dev/null; then
            echo "$(echo "scale=2; $bytes / 1024" | bc)KB"
        else
            echo "$((bytes / 1024))KB"
        fi
    else
        echo "${bytes}B"
    fi
}

# Parse size and get bytes
SIZE_BYTES=$(parse_size "$SIZE_ARG")

# Validate minimum size (at least 1 byte)
if [ $SIZE_BYTES -lt 1 ]; then
    echo "Error: Size must be at least 1 byte"
    exit 1
fi

# Generate default filename if not provided
if [ -z "$OUTPUT_FILE" ]; then
    # Create filename from size
    SIZE_HUMAN=$(echo "$SIZE_ARG" | tr '[:upper:]' '[:lower:]')
    OUTPUT_FILE="test-${SIZE_HUMAN}.bin"
fi

# Check if output file already exists
if [ -f "$OUTPUT_FILE" ]; then
    echo "Warning: File '$OUTPUT_FILE' already exists."
    read -p "Overwrite? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Aborted."
        exit 1
    fi
    rm -f "$OUTPUT_FILE"
fi

# Display information
SIZE_HUMAN_READABLE=$(bytes_to_human $SIZE_BYTES)
echo "Generating test file..."
echo "  Size: $SIZE_HUMAN_READABLE ($SIZE_BYTES bytes)"
echo "  Output: $OUTPUT_FILE"

# Generate file using dd with /dev/urandom
# Use optimal block size based on file size for better performance
if [ $SIZE_BYTES -ge 1048576 ]; then
    # For files >= 1MB, use 1MB blocks
    BLOCK_SIZE=1M
    BLOCK_COUNT=$((SIZE_BYTES / 1048576))
    REMAINDER=$((SIZE_BYTES % 1048576))
    
    if [ $REMAINDER -eq 0 ]; then
        # Exact size
        dd if=/dev/urandom of="$OUTPUT_FILE" bs=$BLOCK_SIZE count=$BLOCK_COUNT status=none 2>&1 || \
        dd if=/dev/urandom of="$OUTPUT_FILE" bs=$BLOCK_SIZE count=$BLOCK_COUNT 2>&1 | grep -v "^[0-9]"
    else
        # Write main blocks first
        dd if=/dev/urandom of="$OUTPUT_FILE" bs=$BLOCK_SIZE count=$BLOCK_COUNT status=none 2>&1 || \
        dd if=/dev/urandom of="$OUTPUT_FILE" bs=$BLOCK_SIZE count=$BLOCK_COUNT 2>&1 | grep -v "^[0-9]"
        # Append remainder
        dd if=/dev/urandom of="$OUTPUT_FILE" bs=1 count=$REMAINDER seek=$((BLOCK_COUNT * 1048576)) conv=notrunc status=none 2>&1 || \
        dd if=/dev/urandom of="$OUTPUT_FILE" bs=1 count=$REMAINDER seek=$((BLOCK_COUNT * 1048576)) conv=notrunc 2>&1 | grep -v "^[0-9]"
    fi
elif [ $SIZE_BYTES -ge 1024 ]; then
    # For files >= 1KB, use 1KB blocks
    BLOCK_SIZE=1K
    BLOCK_COUNT=$((SIZE_BYTES / 1024))
    REMAINDER=$((SIZE_BYTES % 1024))
    
    if [ $REMAINDER -eq 0 ]; then
        dd if=/dev/urandom of="$OUTPUT_FILE" bs=$BLOCK_SIZE count=$BLOCK_COUNT status=none 2>&1 || \
        dd if=/dev/urandom of="$OUTPUT_FILE" bs=$BLOCK_SIZE count=$BLOCK_COUNT 2>&1 | grep -v "^[0-9]"
    else
        dd if=/dev/urandom of="$OUTPUT_FILE" bs=$BLOCK_SIZE count=$BLOCK_COUNT status=none 2>&1 || \
        dd if=/dev/urandom of="$OUTPUT_FILE" bs=$BLOCK_SIZE count=$BLOCK_COUNT 2>&1 | grep -v "^[0-9]"
        dd if=/dev/urandom of="$OUTPUT_FILE" bs=1 count=$REMAINDER seek=$((BLOCK_COUNT * 1024)) conv=notrunc status=none 2>&1 || \
        dd if=/dev/urandom of="$OUTPUT_FILE" bs=1 count=$REMAINDER seek=$((BLOCK_COUNT * 1024)) conv=notrunc 2>&1 | grep -v "^[0-9]"
    fi
else
    # For small files, use byte-by-byte
    dd if=/dev/urandom of="$OUTPUT_FILE" bs=1 count=$SIZE_BYTES status=none 2>&1 || \
    dd if=/dev/urandom of="$OUTPUT_FILE" bs=1 count=$SIZE_BYTES 2>&1 | grep -v "^[0-9]"
fi

# Verify file was created and get actual size
if [ ! -f "$OUTPUT_FILE" ]; then
    echo "Error: Failed to create file"
    exit 1
fi

ACTUAL_SIZE=$(stat -f%z "$OUTPUT_FILE" 2>/dev/null || stat -c%s "$OUTPUT_FILE" 2>/dev/null)
ACTUAL_SIZE_HUMAN=$(bytes_to_human $ACTUAL_SIZE)

echo "✓ File created successfully!"
echo "  File: $OUTPUT_FILE"
echo "  Size: $ACTUAL_SIZE_HUMAN ($ACTUAL_SIZE bytes)"

# Verify size matches (allow 1 byte difference due to rounding)
if [ $ACTUAL_SIZE -eq $SIZE_BYTES ] || [ $ACTUAL_SIZE -eq $((SIZE_BYTES + 1)) ] || [ $ACTUAL_SIZE -eq $((SIZE_BYTES - 1)) ]; then
    echo "  ✓ Size matches requested size"
else
    echo "  ⚠ Warning: Actual size ($ACTUAL_SIZE) differs from requested size ($SIZE_BYTES)"
fi

