#!/bin/bash

###################################################################################
# Configuration for 1000genome MPI Workflow
# Default settings and configuration management
###################################################################################

# Workflow Configuration
export WORKFLOW_NAME="1000genome-mpi"
export WORKFLOW_VERSION="1.0.0"

# Default Directories
export DEFAULT_DATASET="20130502"
export DEFAULT_OUTPUT_DIR="workflow_output"
export DEFAULT_LOG_DIR="workflow_output/logs"

# Default Job Parameters  
export DEFAULT_INDIVIDUALS_JOBS=1
export DEFAULT_MPI_PROCS=4
# Note: Arrays can't be exported, handle in main script
DEFAULT_POPULATIONS_STR="ALL EUR EAS AFR AMR SAS GBR"

# Timeout Configuration (in seconds)
export TIMEOUT_INDIVIDUALS=7200    # 2 hours
export TIMEOUT_MERGE=1800          # 30 minutes  
export TIMEOUT_SIFTING=1800        # 30 minutes
export TIMEOUT_ANALYSIS=1800       # 30 minutes
export TIMEOUT_TOTAL=21600         # 6 hours total

# Resource Requirements
export MIN_MEMORY_GB=4
export MIN_DISK_GB=10

# File Patterns
export VCF_PATTERN="ALL.chr*.vcf.gz"
export ANNOTATION_PATTERN="*.annotation.vcf"
export OUTPUT_INDIVIDUALS_PATTERN="chr*n.tar.gz"
export OUTPUT_SIFTED_PATTERN="sifted.SIFT.chr*.txt"
export OUTPUT_MUTATION_PATTERN="chr*-*.tar.gz"
export OUTPUT_FREQUENCY_PATTERN="chr*-*-freq.tar.gz"

# MPI Configuration
export MPI_HOSTFILE=""
export MPI_MACHINEFILE=""
export MPI_EXTRA_ARGS=""

# Environment Modules (customize for your system)
export REQUIRED_MODULES=(
    "mpi"
    "python/3.8+"
)

# Python Requirements
export REQUIRED_PYTHON_PACKAGES=(
    "mpi4py"
    "numpy"
    "matplotlib"
)

# Logging Configuration
export LOG_LEVEL="INFO"  # DEBUG, INFO, WARN, ERROR
export LOG_FORMAT="[%Y-%m-%d %H:%M:%S]"
export LOG_ROTATION_SIZE="100M"
export LOG_RETENTION_DAYS=7

# Validation Functions
validate_config() {
    local errors=0
    
    # Check numeric values
    if ! [[ "$INDIVIDUALS_JOBS" =~ ^[0-9]+$ ]] || [[ "$INDIVIDUALS_JOBS" -lt 1 ]]; then
        echo "ERROR: INDIVIDUALS_JOBS must be a positive integer" >&2
        errors=1
    fi
    
    if ! [[ "$NUM_MPI_PROCS" =~ ^[0-9]+$ ]] || [[ "$NUM_MPI_PROCS" -lt 1 ]]; then
        echo "ERROR: NUM_MPI_PROCS must be a positive integer" >&2
        errors=1
    fi
    
    # Check directories exist
    if [[ -n "$DATASET" && ! -d "${WORKFLOW_DIR}/data/${DATASET}" ]]; then
        echo "ERROR: Dataset directory not found: ${WORKFLOW_DIR}/data/${DATASET}" >&2
        errors=1
    fi
    
    return $errors
}

check_system_requirements() {
    local errors=0
    
    # Check available memory
    if command -v free &> /dev/null; then
        local available_gb=$(free -g | awk '/^Mem:/{print $7}')
        if [[ "$available_gb" -lt "$MIN_MEMORY_GB" ]]; then
            echo "WARNING: Available memory (${available_gb}GB) is less than minimum (${MIN_MEMORY_GB}GB)" >&2
        fi
    fi
    
    # Check disk space
    if command -v df &> /dev/null; then
        local available_gb=$(df -BG "${WORKFLOW_DIR}" | awk 'NR==2{print $4}' | sed 's/G//')
        if [[ "$available_gb" -lt "$MIN_DISK_GB" ]]; then
            echo "WARNING: Available disk space (${available_gb}GB) is less than minimum (${MIN_DISK_GB}GB)" >&2
        fi
    fi
    
    # Check MPI availability
    if ! command -v mpirun &> /dev/null && ! command -v mpiexec &> /dev/null; then
        echo "ERROR: MPI not found (neither mpirun nor mpiexec)" >&2
        errors=1
    fi
    
    # Check Python and packages
    if ! command -v python3 &> /dev/null; then
        echo "ERROR: python3 not found" >&2
        errors=1
    else
        for package in "${REQUIRED_PYTHON_PACKAGES[@]}"; do
            if ! python3 -c "import $package" 2>/dev/null; then
                echo "ERROR: Python package not found: $package" >&2
                errors=1
            fi
        done
    fi
    
    return $errors
}

load_environment_modules() {
    if command -v module &> /dev/null; then
        echo "Loading environment modules..."
        for mod in "${REQUIRED_MODULES[@]}"; do
            if module avail "$mod" &>/dev/null; then
                echo "  Loading module: $mod"
                module load "$mod" || echo "  WARNING: Failed to load module: $mod"
            else
                echo "  WARNING: Module not available: $mod"
            fi
        done
    else
        echo "Environment modules not available (module command not found)"
    fi
}

# Configuration file management
save_config() {
    local config_file="$1"
    
    cat > "$config_file" << EOF
# 1000genome MPI Workflow Configuration
# Generated on $(date)

WORKFLOW_NAME="$WORKFLOW_NAME"
WORKFLOW_VERSION="$WORKFLOW_VERSION"
DATASET="$DATASET"
INDIVIDUALS_JOBS="$INDIVIDUALS_JOBS"
NUM_MPI_PROCS="$NUM_MPI_PROCS"
OUTPUT_DIR="$OUTPUT_DIR"
POPULATIONS=($(printf '"%s" ' "${POPULATIONS[@]}"))
CHROMOSOMES=($(printf '"%s" ' "${CHROMOSOMES[@]}"))

# Timeouts
TIMEOUT_INDIVIDUALS="$TIMEOUT_INDIVIDUALS"
TIMEOUT_MERGE="$TIMEOUT_MERGE"
TIMEOUT_SIFTING="$TIMEOUT_SIFTING"
TIMEOUT_ANALYSIS="$TIMEOUT_ANALYSIS"

# Flags
DRY_RUN="$DRY_RUN"
VERBOSE="$VERBOSE"
EOF
    
    echo "Configuration saved to: $config_file"
}

load_config() {
    local config_file="$1"
    
    if [[ -f "$config_file" ]]; then
        echo "Loading configuration from: $config_file"
        source "$config_file"
    else
        echo "Configuration file not found: $config_file"
        return 1
    fi
}

# Print current configuration
print_config() {
    cat << EOF
=== 1000genome MPI Workflow Configuration ===
Workflow: $WORKFLOW_NAME v$WORKFLOW_VERSION
Dataset: $DATASET
Individuals jobs per chromosome: $INDIVIDUALS_JOBS
MPI processes: $NUM_MPI_PROCS
Output directory: $OUTPUT_DIR
Populations: ${POPULATIONS[*]}
Chromosomes: ${CHROMOSOMES[*]:-"(all from data.csv)"}

Timeouts:
  Individuals jobs: ${TIMEOUT_INDIVIDUALS}s
  Merge jobs: ${TIMEOUT_MERGE}s  
  Sifting jobs: ${TIMEOUT_SIFTING}s
  Analysis jobs: ${TIMEOUT_ANALYSIS}s

Flags:  
  Dry run: $DRY_RUN
  Verbose: $VERBOSE
===========================================
EOF
}

# Export functions
export -f validate_config
export -f check_system_requirements  
export -f load_environment_modules
export -f save_config
export -f load_config
export -f print_config
