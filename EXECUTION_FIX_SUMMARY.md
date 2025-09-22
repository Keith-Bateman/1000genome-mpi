# MPI Workflow Execution Fix Summary

## Problem
User reported "one or more individuals jobs failed" when running the MPI workflow outside the container environment.

## Root Cause Analysis
1. **Argument Mismatch**: The workflow was passing 6 arguments to `individuals_mpi.py`, but the original script expected only 5
2. **Hardcoded File Path**: Original script hardcoded `columfile='columns.txt'` but workflow tried to pass it as an argument
3. **Environment Differences**: Container vs. real environment had different library availability and file access patterns

## Fixes Implemented

### 1. Fixed Argument Passing (`job_functions.sh`)
**Before:**
```bash
# Passed 6 arguments including columns_file
local command="$mpi_cmd -np $num_procs python3 ${WORKFLOW_DIR}/bin/individuals_mpi.py \"$input_file\" \"$columns_file\" $chr_num $start_line $end_line $total_lines"
```

**After:**
```bash  
# Pass only 5 arguments as expected by original script
local command="$mpi_cmd -np $num_procs python3 ${WORKFLOW_DIR}/bin/individuals_mpi_fixed.py \"$input_file\" $chr_num $start_line $end_line $total_lines"
```

### 2. Created Improved Script (`bin/individuals_mpi_fixed.py`)
**Enhancements:**
- **Smart columns.txt lookup**: Searches multiple locations for the file
- **Compressed file support**: Automatically handles `.gz` files  
- **Better error handling**: Graceful fallbacks and detailed error messages
- **Library fallbacks**: Works even when Decaf/Bredala libraries are missing
- **Robust parsing**: Handles malformed data lines gracefully

### 3. Added Environment Testing (`test_mpi_environment.sh`)
**Features:**
- Tests MPI installation and basic functionality
- Verifies Python MPI library availability
- Checks optional libraries (Decaf, Bredala, numpy)
- Runs simple MPI program to validate setup

### 4. Automatic File Linking
```bash
# Auto-create symlink to columns.txt if needed
if [[ ! -f "columns.txt" && -f "${WORKFLOW_DIR}/data/20130502/columns.txt" ]]; then
    ln -sf "${WORKFLOW_DIR}/data/20130502/columns.txt" columns.txt
fi
```

### 5. Updated Documentation
- Added troubleshooting section with common issues
- Provided debugging commands for manual testing
- Documented environment setup requirements

## Usage Instructions

### Test Environment First
```bash
./test_mpi_environment.sh
```

### Run Workflow with Fixes
```bash
# The workflow now automatically uses the improved script
./run_workflow_mpi.sh --verbose

# Or with dry-run to test logic
./run_workflow_mpi.sh --dry-run --verbose
```

### Debug Individual Components
```bash
# Test a single chromosome manually
mpirun -np 4 python3 bin/individuals_mpi_fixed.py \
  "data/20130502/ALL.chr22.phase3_shapeit2_mvncall_integrated_v5a.20130502.genotypes.vcf.gz" \
  22 1 1000 50000
```

## Expected Results
- No more "argument mismatch" errors
- Proper handling of compressed VCF files
- Graceful fallback when optional libraries are missing
- Better error messages for debugging
- Successful execution outside container environment

## Files Modified
1. `/workspace/apps/1000genome-workflow/job_functions.sh` - Fixed argument passing
2. `/workspace/apps/1000genome-workflow/bin/individuals_mpi_fixed.py` - New improved script
3. `/workspace/apps/1000genome-workflow/test_mpi_environment.sh` - New environment test
4. `/workspace/apps/1000genome-workflow/README_MPI.md` - Updated documentation

The workflow should now execute successfully outside the container with proper error handling and debugging capabilities.
