#!/bin/bash

# Test the proper MPI communication pattern with minimal data

WORKFLOW_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$WORKFLOW_DIR"

echo "=== Testing MPI Communication Pattern ==="
echo "Date: $(date)"

# Create a minimal test VCF file (first 100 lines)
TEST_VCF="test_minimal.vcf.gz"
ORIGINAL_VCF="data/20130502/ALL.chr1.250000.vcf.gz"

if [[ -f "$ORIGINAL_VCF" ]]; then
    echo "Creating minimal test file from $ORIGINAL_VCF..."
    # Extract first 100 lines (including headers) 
    zcat "$ORIGINAL_VCF" | head -100 | gzip > "$TEST_VCF"
    test_lines=$(zcat "$TEST_VCF" | wc -l)
    echo "Created $TEST_VCF with $test_lines lines"
else
    echo "ERROR: Original VCF file not found: $ORIGINAL_VCF"
    exit 1
fi

# Ensure columns.txt is available
if [[ ! -f "columns.txt" && -f "data/20130502/columns.txt" ]]; then
    ln -sf "data/20130502/columns.txt" columns.txt
    echo "Created symlink to columns.txt"
fi

# Test with different numbers of processes
for np in 2 3 4; do
    echo ""
    echo "=== Testing with $np processes ==="
    
    # Build MPI command
    mpi_cmd="mpirun -np $np"
    
    # Add hostfile if available
    if [[ -f "localhost.hosts" ]]; then
        mpi_cmd="$mpi_cmd --hostfile localhost.hosts"
    fi
    
    # Test the proper script
    script="bin/individuals_mpi_proper.py"
    if [[ -f "$script" ]]; then
        echo "Testing: $mpi_cmd python3 $script $TEST_VCF 1 1 50 $test_lines"
        echo "Expected: $(($np - 1)) workers + 1 merger"
        
        timeout 120 $mpi_cmd python3 "$script" "$TEST_VCF" 1 1 50 "$test_lines"
        exit_code=$?
        
        if [[ $exit_code -eq 0 ]]; then
            echo "✓ Test with $np processes PASSED"
        elif [[ $exit_code -eq 124 ]]; then
            echo "✗ Test with $np processes TIMED OUT (likely deadlock)"
        else
            echo "✗ Test with $np processes FAILED (exit code: $exit_code)"
        fi
    else
        echo "Script not found: $script"
    fi
done

# Cleanup
rm -f "$TEST_VCF"

echo ""
echo "=== Test Complete ==="
echo "If all tests passed, the MPI communication is working properly."
echo "If tests timed out, there's still a deadlock issue."
