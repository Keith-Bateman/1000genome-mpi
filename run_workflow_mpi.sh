#!/bin/bash

###################################################################################
# 1000genome MPI Workflow Runner
# Converts Pegasus-based workflow to run with MPI instead of Pegasus/Condor
###################################################################################

set -e  # Exit on any error

# Get workflow directory
WORKFLOW_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source configuration and helper functions
source "${WORKFLOW_DIR}/config.sh"

# Default configuration
DATA_CSV="${WORKFLOW_DIR}/data.csv"
DATASET="${DEFAULT_DATASET}"
INDIVIDUALS_JOBS="${DEFAULT_INDIVIDUALS_JOBS}"
NUM_MPI_PROCS="${DEFAULT_MPI_PROCS}"
OUTPUT_DIR="${WORKFLOW_DIR}/${DEFAULT_OUTPUT_DIR}"
LOG_DIR="${OUTPUT_DIR}/logs"
# Convert string to array for populations
read -ra POPULATIONS <<< "$DEFAULT_POPULATIONS_STR"
# MPI multi-node configuration
HOSTFILE="${DEFAULT_HOSTFILE}"
MPI_ARGS="${DEFAULT_MPI_ARGS}"
TIMEOUT_INDIVIDUALS="${TIMEOUT_INDIVIDUALS}"
DRY_RUN=false
VERBOSE=false

# Source job functions after setting up variables
source "${WORKFLOW_DIR}/job_functions.sh"

# Usage function
usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Convert and run 1000genome Pegasus workflow using MPI

OPTIONS:
    -d, --dataset DIR       Dataset directory name (default: 20130502)
    -i, --individuals N     Number of individuals jobs per chromosome (default: 1)
    -p, --processes N       Number of MPI processes (default: 8)
    --hostfile FILE         MPI hostfile for multi-node execution
    --mpi-args "ARGS"       Additional MPI arguments (quoted)
    --timeout SECONDS       Job timeout in seconds for individuals jobs (default: 10800)
    -o, --output DIR        Output directory (default: ./workflow_output)
    -c, --chromosomes LIST  Comma-separated list of chromosomes (default: all from data.csv)
    --populations LIST      Comma-separated list of populations (default: ALL,EUR,EAS,AFR,AMR,SAS,GBR)
    --dry-run              Show commands without executing
    -v, --verbose          Enable verbose output
    -h, --help             Show this help message

EXAMPLES:
    $0                                          # Run with defaults
    $0 -i 2 -p 8                               # Use 2 individuals jobs per chromosome, 8 MPI processes
    $0 -c "1,2,3" --populations "ALL,EUR"     # Run only chromosomes 1,2,3 with ALL and EUR populations
    $0 --dry-run -v                           # Show what would be executed

MULTI-NODE EXAMPLES:
    $0 -p 16 --hostfile hosts.txt                          # 16 processes across nodes in hosts.txt
    $0 -p 32 --hostfile hosts.txt --mpi-args "-bind-to core"  # With additional MPI options
    $0 -p 8 --hostfile hosts.txt -c "1" --timeout 14400       # Single chromosome, 4 hour timeout

HOSTFILE FORMAT:
    node1 slots=4
    node2 slots=4
    node3 slots=8
EOF
}

# Logging functions
log_info() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] INFO: $*" | tee -a "${LOG_DIR}/workflow.log"
}

log_error() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $*" | tee -a "${LOG_DIR}/workflow.log" >&2
}

log_debug() {
    if [[ "$VERBOSE" == "true" ]]; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] DEBUG: $*" | tee -a "${LOG_DIR}/workflow.log"
    fi
}

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -d|--dataset)
                DATASET="$2"
                shift 2
                ;;
            -i|--individuals)
                INDIVIDUALS_JOBS="$2"
                shift 2
                ;;
            -p|--processes)
                NUM_MPI_PROCS="$2"
                shift 2
                ;;
            --hostfile)
                HOSTFILE="$2"
                shift 2
                ;;
            --mpi-args)
                MPI_ARGS="$2"
                shift 2
                ;;
            --timeout)
                TIMEOUT_INDIVIDUALS="$2"
                shift 2
                ;;
            -o|--output)
                OUTPUT_DIR="$2"
                shift 2
                ;;
            -c|--chromosomes)
                IFS=',' read -ra CHROMOSOMES_OVERRIDE <<< "$2"
                shift 2
                ;;
            --populations)
                IFS=',' read -ra POPULATIONS <<< "$2"
                shift 2
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            -v|--verbose)
                VERBOSE=true
                shift
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                usage
                exit 1
                ;;
        esac
    done
}

# Validate environment and inputs
validate_environment() {
    # Create output directories first
    mkdir -p "${OUTPUT_DIR}" "${LOG_DIR}"
    
    log_info "Validating environment..."
    
    # Check required files
    if [[ ! -f "$DATA_CSV" ]]; then
        log_error "Data CSV file not found: $DATA_CSV"
        exit 1
    fi
    
    if [[ ! -d "${WORKFLOW_DIR}/data/${DATASET}" ]]; then
        log_error "Dataset directory not found: ${WORKFLOW_DIR}/data/${DATASET}"
        exit 1
    fi
    
    if [[ ! -f "${WORKFLOW_DIR}/data/${DATASET}/columns.txt" ]]; then
        log_error "Columns file not found: ${WORKFLOW_DIR}/data/${DATASET}/columns.txt"
        exit 1
    fi
    
    # Check MPI availability (only if not dry run)
    if [[ "$DRY_RUN" == "false" ]]; then
        if ! command -v mpirun &> /dev/null && ! command -v mpiexec &> /dev/null; then
            log_error "MPI not found. Please ensure mpirun or mpiexec is available."
            exit 1
        fi
        
        # Check Python and required modules
        if ! python3 -c "import mpi4py" 2>/dev/null; then
            log_error "mpi4py not available. Please install mpi4py."
            exit 1
        fi
    fi
    
    log_info "Environment validation complete"
}

# Setup environment
setup_environment() {
    log_info "Setting up environment..."
    
    # Source environment if available (ignore errors for missing modules)
    if [[ -f "${WORKFLOW_DIR}/env.sh" ]]; then
        log_debug "Sourcing environment from env.sh"
        if ! source "${WORKFLOW_DIR}/env.sh" 2>/dev/null; then
            log_debug "Warning: Some environment setup commands failed (likely missing modules), continuing..."
        fi
    fi
    
    # Set library paths for Decaf/Bredala libraries
    export LD_LIBRARY_PATH="${WORKFLOW_DIR}/lib:${LD_LIBRARY_PATH}"
    export PYTHONPATH="${WORKFLOW_DIR}/lib:${PYTHONPATH}"
    
    # Change to workflow directory
    cd "${WORKFLOW_DIR}"
    
    log_info "Environment setup complete"
}

# Read chromosome data from CSV
read_chromosome_data() {
    log_info "Reading chromosome data from $DATA_CSV"
    
    declare -g -A CHROMOSOME_DATA
    declare -g -a CHROMOSOMES
    
    while IFS=',' read -r vcf_file lines annotation_file; do
        # Skip empty lines and comments
        [[ -z "$vcf_file" || "$vcf_file" =~ ^[#] ]] && continue
        
        # Extract chromosome number from filename (handle .gz files)
        if [[ "$vcf_file" =~ ALL\.chr([0-9]+)\..*\.vcf(\.gz)? ]]; then
            chr_num="${BASH_REMATCH[1]}"
            CHROMOSOME_DATA["$chr_num"]="$vcf_file,$lines,$annotation_file"
            CHROMOSOMES+=("$chr_num")
            log_debug "Found chromosome $chr_num: $vcf_file ($lines lines)"
        fi
    done < "$DATA_CSV"
    
    # Apply chromosome filter if specified
    if [[ -n "${CHROMOSOMES_OVERRIDE:-}" ]]; then
        CHROMOSOMES=("${CHROMOSOMES_OVERRIDE[@]}")
        log_info "Using specified chromosomes: ${CHROMOSOMES[*]}"
    else
        log_info "Using all chromosomes: ${CHROMOSOMES[*]}"
    fi
}

# This function is now handled by job_functions.sh

# Run individuals jobs for a chromosome using job functions
run_individuals_jobs() {
    local chr_num="$1"
    local vcf_file="$2"
    local total_lines="$3"
    
    log_info "Running individuals jobs for chromosome $chr_num"
    
    # Calculate line ranges for parallel jobs
    local lines_per_job=$((total_lines / INDIVIDUALS_JOBS))
    local remainder=$((total_lines % INDIVIDUALS_JOBS))
    
    local job_commands=()
    local counter=1
    
    for ((job=0; job<INDIVIDUALS_JOBS; job++)); do
        local start=$counter
        local end=$((counter + lines_per_job - 1))
        
        # Add remainder to last job
        if [[ $job -eq $((INDIVIDUALS_JOBS - 1)) ]]; then
            end=$((end + remainder))
        fi
        
        local columns_file="${WORKFLOW_DIR}/data/${DATASET}/columns.txt"
        
        # Build job command using job functions
        job_commands+=("run_individuals_job $chr_num \"$vcf_file\" \"$columns_file\" $start $end $total_lines")
        
        counter=$((end + 1))
    done
    
    # Launch jobs in parallel using job functions
    if ! launch_parallel_jobs "${job_commands[@]}"; then
        log_error "One or more individuals jobs failed for chromosome $chr_num"
        return 1
    fi
    
    log_info "All individuals jobs completed for chromosome $chr_num"
}

# Run individuals merge job using job functions
run_individuals_merge() {
    local chr_num="$1"
    
    log_info "Running individuals merge for chromosome $chr_num"
    
    if ! run_individuals_merge_job "$chr_num"; then
        log_error "Individuals merge failed for chromosome $chr_num"
        return 1
    fi
    
    log_info "Individuals merge completed for chromosome $chr_num"
}

# Run sifting job using job functions
run_sifting() {
    local chr_num="$1"
    local annotation_file="$2"
    
    log_info "Running sifting for chromosome $chr_num"
    
    if ! run_sifting_job "$chr_num" "$annotation_file"; then
        log_error "Sifting failed for chromosome $chr_num"
        return 1
    fi
    
    log_info "Sifting completed for chromosome $chr_num"
}

# Run mutation overlap job using job functions
run_mutation_overlap() {
    local chr_num="$1"
    local population="$2"
    
    log_info "Running mutation overlap for chromosome $chr_num, population $population"
    
    if ! run_mutation_overlap_job "$chr_num" "$population"; then
        log_error "Mutation overlap failed for chromosome $chr_num, population $population"
        return 1
    fi
    
    log_info "Mutation overlap completed for chromosome $chr_num, population $population"
}

# Run frequency job using job functions
run_frequency() {
    local chr_num="$1"
    local population="$2"
    
    log_info "Running frequency analysis for chromosome $chr_num, population $population"
    
    if ! run_frequency_job "$chr_num" "$population"; then
        log_error "Frequency analysis failed for chromosome $chr_num, population $population"
        return 1
    fi
    
    log_info "Frequency analysis completed for chromosome $chr_num, population $population"
}

# Main workflow execution
run_workflow() {
    log_info "Starting 1000genome MPI workflow"
    log_info "Configuration:"
    log_info "  Dataset: $DATASET"
    log_info "  Individuals jobs per chromosome: $INDIVIDUALS_JOBS"
    log_info "  MPI processes: $NUM_MPI_PROCS"
    log_info "  Output directory: $OUTPUT_DIR"
    log_info "  Chromosomes: ${CHROMOSOMES[*]}"
    log_info "  Populations: ${POPULATIONS[*]}"
    
    # Phase 1: Process each chromosome (individuals -> merge, sifting in parallel)
    for chr_num in "${CHROMOSOMES[@]}"; do
        log_info "Processing chromosome $chr_num"
        
        # Parse chromosome data
        local chr_data="${CHROMOSOME_DATA[$chr_num]}"
        IFS=',' read -r vcf_file total_lines annotation_file <<< "$chr_data"
        
        # Run individuals jobs
        if ! run_individuals_jobs "$chr_num" "$vcf_file" "$total_lines"; then
            log_error "Individuals jobs failed for chromosome $chr_num"
            return 1
        fi
        
        # Run individuals merge and sifting in parallel
        run_individuals_merge "$chr_num" &
        local merge_pid=$!
        
        run_sifting "$chr_num" "$annotation_file" &
        local sifting_pid=$!
        
        # Wait for both to complete
        local failed=0
        if ! wait "$merge_pid"; then
            log_error "Individuals merge failed for chromosome $chr_num"
            failed=1
        fi
        
        if ! wait "$sifting_pid"; then
            log_error "Sifting failed for chromosome $chr_num"
            failed=1
        fi
        
        if [[ $failed -ne 0 ]]; then
            return 1
        fi
        
        log_info "Chromosome $chr_num processing complete"
    done
    
    # Phase 2: Analysis jobs (mutation overlap and frequency for each chr-population pair)
    log_info "Starting analysis phase"
    
    for chr_num in "${CHROMOSOMES[@]}"; do
        for population in "${POPULATIONS[@]}"; do
            # Check if population file exists
            if [[ ! -f "${WORKFLOW_DIR}/data/populations/${population}" ]]; then
                log_debug "Population file not found: ${population}, skipping"
                continue
            fi
            
            # Run mutation overlap and frequency in parallel
            run_mutation_overlap "$chr_num" "$population" &
            local overlap_pid=$!
            
            run_frequency "$chr_num" "$population" &
            local freq_pid=$!
            
            # Wait for both to complete
            local failed=0
            if ! wait "$overlap_pid"; then
                log_error "Mutation overlap failed for chromosome $chr_num, population $population"
                failed=1
            fi
            
            if ! wait "$freq_pid"; then
                log_error "Frequency analysis failed for chromosome $chr_num, population $population"
                failed=1
            fi
            
            if [[ $failed -ne 0 ]]; then
                return 1
            fi
        done
    done
    
    log_info "1000genome MPI workflow completed successfully"
}

# Cleanup function
cleanup() {
    log_info "Cleaning up temporary files..."
    # Add cleanup logic here if needed
}

# Main execution
main() {
    # Set up signal handlers
    trap cleanup EXIT
    trap 'log_error "Workflow interrupted"; exit 1' INT TERM
    
    # Parse arguments
    parse_args "$@"
    
    # Validate and setup
    validate_environment
    setup_environment
    read_chromosome_data
    
    # Run the workflow
    if run_workflow; then
        log_info "Workflow completed successfully!"
        exit 0
    else
        log_error "Workflow failed!"
        exit 1
    fi
}

# Only run main if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
