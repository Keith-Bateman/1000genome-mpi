#!/bin/bash

###################################################################################
# Job Functions for 1000genome MPI Workflow
# Helper functions for different job types
###################################################################################

# Source this file to get job execution functions

# Get MPI command with Spack environment support
get_mpi_command() {
    local script="$1"
    shift
    local args=("$@")
    
    # Determine MPI base command
    local mpi_base=""
    if [[ "$DRY_RUN" == "true" ]]; then
        mpi_base="mpirun"  # Use mpirun for dry runs
    elif command -v mpirun &> /dev/null; then
        mpi_base="mpirun"
    elif command -v mpiexec &> /dev/null; then
        mpi_base="mpiexec"
    else
        echo "ERROR: Neither mpirun nor mpiexec found" >&2
        return 1
    fi
    
    # Build base MPI command
    local mpi_cmd="$mpi_base"
    local mpi_args=("-np" "$NUM_MPI_PROCS")
    
    # Add hostfile if specified
    if [[ -n "$HOSTFILE" && -f "$HOSTFILE" ]]; then
        mpi_args+=("--hostfile" "$HOSTFILE")
        log_debug "Using hostfile: $HOSTFILE"
    fi
    
    # Method 1: Use wrapper script if available
    if [[ -f "${WORKFLOW_DIR}/mpi_python_wrapper.sh" ]]; then
        log_debug "Using Spack wrapper script"
        mpi_args+=("${WORKFLOW_DIR}/mpi_python_wrapper.sh" "$script")
        
    # Method 2: Use environment variable propagation  
    elif [[ -f "${WORKFLOW_DIR}/spack_env_vars.sh" ]]; then
        log_debug "Using Spack environment variables"
        mpi_args+=("bash" "-c" "source ${WORKFLOW_DIR}/spack_env_vars.sh && python3 $script")
        
    # Method 3: Use MPI -x flags if available
    elif [[ -f "${WORKFLOW_DIR}/mpi_env_flags.txt" ]]; then
        log_debug "Using MPI environment flags"
        local env_flags
        env_flags="$(cat "${WORKFLOW_DIR}/mpi_env_flags.txt")"
        read -ra flag_array <<< "$env_flags"
        mpi_args=("${flag_array[@]}" "${mpi_args[@]}")
        mpi_args+=("python3" "$script")
        
    # Fallback: Regular python3
    else
        log_debug "Using regular python3 (no Spack support detected)"
        mpi_args+=("python3" "$script")
    fi
    
    # Add script arguments
    mpi_args+=("${args[@]}")
    
    # Add any additional MPI arguments
    if [[ -n "$MPI_ARGS" ]]; then
        read -ra additional_args <<< "$MPI_ARGS"
        # Insert additional args after -np but before the command
        local temp_args=("${mpi_args[@]:0:2}")  # Keep -np N
        temp_args+=("${additional_args[@]}")     # Add custom args
        temp_args+=("${mpi_args[@]:2}")         # Add rest
        mpi_args=("${temp_args[@]}")
        log_debug "Using additional MPI args: $MPI_ARGS"
    fi
    
    echo "${mpi_cmd} ${mpi_args[*]}"
}

# Execute a job with timeout and error handling
execute_job() {
    local job_name="$1"
    local command="$2"
    local timeout_seconds="${3:-3600}"  # Default 1 hour timeout
    local log_file="${LOG_DIR}/${job_name}.log"
    local pid_file="${LOG_DIR}/${job_name}.pid"
    
    echo "[$(date)] Starting job: $job_name" | tee -a "$log_file"
    echo "[$(date)] Command: $command" | tee -a "$log_file"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        echo "DRY RUN: $command"
        return 0
    fi
    
    # Start the job in background and capture PID
    eval "$command" >> "$log_file" 2>&1 &
    local job_pid=$!
    echo $job_pid > "$pid_file"
    
    # Wait for job with timeout
    local count=0
    while kill -0 $job_pid 2>/dev/null && [[ $count -lt $timeout_seconds ]]; do
        sleep 1
        ((count++))
    done
    
    # Check if job completed or timed out
    if kill -0 $job_pid 2>/dev/null; then
        echo "[$(date)] Job timed out after ${timeout_seconds}s: $job_name" | tee -a "$log_file"
        kill -TERM $job_pid 2>/dev/null
        wait $job_pid 2>/dev/null
        rm -f "$pid_file"
        return 124  # Timeout exit code
    fi
    
    # Get exit status
    wait $job_pid
    local exit_code=$?
    rm -f "$pid_file"
    
    if [[ $exit_code -eq 0 ]]; then
        echo "[$(date)] Job completed successfully: $job_name" | tee -a "$log_file"
    else
        echo "[$(date)] Job failed with exit code $exit_code: $job_name" | tee -a "$log_file"
    fi
    
    return $exit_code
}

# Check if required input files exist
check_input_files() {
    local -a files=("$@")
    local missing_files=()
    
    for file in "${files[@]}"; do
        if [[ ! -f "$file" ]]; then
            missing_files+=("$file")
        fi
    done
    
    if [[ ${#missing_files[@]} -gt 0 ]]; then
        echo "ERROR: Missing input files:" >&2
        printf "  %s\n" "${missing_files[@]}" >&2
        return 1
    fi
    
    return 0
}

# Wait for files to be created (with timeout)
wait_for_files() {
    local timeout_seconds="$1"
    shift
    local -a files=("$@")
    
    local count=0
    while [[ $count -lt $timeout_seconds ]]; do
        local all_exist=true
        for file in "${files[@]}"; do
            if [[ ! -f "$file" ]]; then
                all_exist=false
                break
            fi
        done
        
        if [[ "$all_exist" == "true" ]]; then
            return 0
        fi
        
        sleep 1
        ((count++))
    done
    
    echo "ERROR: Timeout waiting for files after ${timeout_seconds}s" >&2
    printf "  Missing: "
    for file in "${files[@]}"; do
        if [[ ! -f "$file" ]]; then
            printf "%s " "$file"
        fi
    done
    printf "\n" >&2
    
    return 1
}

# Individuals job runner
run_individuals_job() {
    local chr_num="$1"
    local vcf_file="$2"
    local columns_file="$3"
    local start_line="$4"
    local end_line="$5"
    local total_lines="$6"
    local num_procs="${7:-$NUM_MPI_PROCS}"
    
    local job_name="individuals_chr${chr_num}_${start_line}_${end_line}"
    local input_file="${WORKFLOW_DIR}/data/${DATASET}/${vcf_file}"
    
    # For dry run, don't check files
    if [[ "$DRY_RUN" != "true" ]]; then
        # Validate inputs
        check_input_files "$input_file" "$columns_file" || return 1
    fi
    
    # Ensure columns.txt is available in current directory
    if [[ "$DRY_RUN" != "true" ]]; then
        if [[ ! -f "columns.txt" && -f "${WORKFLOW_DIR}/data/20130502/columns.txt" ]]; then
            ln -sf "${WORKFLOW_DIR}/data/20130502/columns.txt" columns.txt
            log_info "Created symlink to columns.txt"
        fi
    fi
    
    # Use improved script with proper MPI communication if available
    local script="${WORKFLOW_DIR}/bin/individuals_mpi_proper.py"
    if [[ ! -f "$script" ]]; then
        script="${WORKFLOW_DIR}/bin/individuals_mpi_fixed.py" 
        log_warning "Using fallback script: individuals_mpi_fixed.py"
    else
        log_info "Using proper MPI script: individuals_mpi_proper.py"
    fi
    
    if [[ ! -f "$script" ]]; then
        script="${WORKFLOW_DIR}/bin/individuals_mpi.py"
        log_warning "Using original script: individuals_mpi.py"
    fi
    
    # Build command using new get_mpi_command with Spack support
    local command=$(get_mpi_command "$script" "$input_file" "$chr_num" "$start_line" "$end_line" "$total_lines") || return 1
    
    execute_job "$job_name" "$command" "${TIMEOUT_INDIVIDUALS:-10800}"  # Use configured timeout
}

# Individuals merge job runner
run_individuals_merge_job() {
    local chr_num="$1"
    local num_procs="${2:-$((NUM_MPI_PROCS + 1))}"  # Needs one extra process for merge
    
    local job_name="individuals_merge_chr${chr_num}"
    
    # Use merge script if available, otherwise fall back to original
    local script="${WORKFLOW_DIR}/bin/individuals_merge_mpi.py"
    
    # Build command using new get_mpi_command with Spack support
    local command=$(get_mpi_command "$script" "$chr_num") || return 1
    
    execute_job "$job_name" "$command" 1800  # 30 minute timeout
}

# Sifting job runner
run_sifting_job() {
    local chr_num="$1"
    local annotation_file="$2"
    
    local job_name="sifting_chr${chr_num}"
    local input_file="${WORKFLOW_DIR}/data/${DATASET}/${annotation_file}"
    
    # For dry run, don't check files
    if [[ "$DRY_RUN" != "true" ]]; then
        # Validate inputs
        check_input_files "$input_file" || return 1
    fi
    
    # Build command (no MPI needed for sifting)
    local command="python3 ${WORKFLOW_DIR}/bin/sifting.py \"$input_file\" $chr_num"
    
    execute_job "$job_name" "$command" 1800  # 30 minute timeout
}

# Mutation overlap job runner
run_mutation_overlap_job() {
    local chr_num="$1"
    local population="$2"
    
    local job_name="mutation_overlap_chr${chr_num}_${population}"
    
    # Expected input files
    local individuals_file="chr${chr_num}n.tar.gz"
    local sifted_file="sifted.SIFT.chr${chr_num}.txt"
    local population_file="${WORKFLOW_DIR}/data/populations/${population}"
    local columns_file="${WORKFLOW_DIR}/data/${DATASET}/columns.txt"
    
    # For dry run, don't check files
    if [[ "$DRY_RUN" != "true" ]]; then
        # Validate inputs
        check_input_files "$sifted_file" "$population_file" "$columns_file" || return 1
        
        # Check for individuals file (may be created by merge job)
        if [[ ! -f "$individuals_file" ]]; then
            echo "WARNING: Individuals file not found: $individuals_file"
            echo "Checking for merged directory..."
            if [[ ! -d "merged" ]]; then
                echo "ERROR: Neither individuals file nor merged directory found"
                return 1
            fi
        fi
    fi
    
    # Build command
    local command="python3 ${WORKFLOW_DIR}/bin/mutation_overlap.py -c $chr_num -pop $population"
    
    execute_job "$job_name" "$command" 1800  # 30 minute timeout
}

# Frequency job runner  
run_frequency_job() {
    local chr_num="$1"
    local population="$2"
    
    local job_name="frequency_chr${chr_num}_${population}"
    
    # Expected input files
    local individuals_file="chr${chr_num}n.tar.gz"
    local sifted_file="sifted.SIFT.chr${chr_num}.txt"
    local population_file="${WORKFLOW_DIR}/data/populations/${population}"
    local columns_file="${WORKFLOW_DIR}/data/${DATASET}/columns.txt"
    
    # For dry run, don't check files
    if [[ "$DRY_RUN" != "true" ]]; then
        # Validate inputs
        check_input_files "$sifted_file" "$population_file" "$columns_file" || return 1
        
        # Check for individuals file (may be created by merge job)
        if [[ ! -f "$individuals_file" ]]; then
            echo "WARNING: Individuals file not found: $individuals_file"
            echo "Checking for merged directory..."
            if [[ ! -d "merged" ]]; then
                echo "ERROR: Neither individuals file nor merged directory found"
                return 1
            fi
        fi
    fi
    
    # Build command
    local command="python3 ${WORKFLOW_DIR}/bin/frequency.py -c $chr_num -pop $population"
    
    execute_job "$job_name" "$command" 1800  # 30 minute timeout
}

# Parallel job launcher
launch_parallel_jobs() {
    local -a job_commands=("$@")
    local -a pids=()
    
    # Launch all jobs
    for cmd in "${job_commands[@]}"; do
        eval "$cmd" &
        pids+=($!)
    done
    
    # Wait for all jobs
    local failed=0
    for pid in "${pids[@]}"; do
        if ! wait "$pid"; then
            failed=1
        fi
    done
    
    return $failed
}

# Job status checker
check_job_status() {
    local job_name="$1"
    local pid_file="${LOG_DIR}/${job_name}.pid"
    local log_file="${LOG_DIR}/${job_name}.log"
    
    if [[ -f "$pid_file" ]]; then
        local pid=$(cat "$pid_file")
        if kill -0 "$pid" 2>/dev/null; then
            echo "RUNNING"
            return 0
        else
            echo "FINISHED"
            rm -f "$pid_file"
            return 0
        fi
    else
        if [[ -f "$log_file" ]]; then
            if grep -q "completed successfully" "$log_file"; then
                echo "SUCCESS"
                return 0
            elif grep -q "failed with exit code" "$log_file"; then
                echo "FAILED"
                return 1
            else
                echo "UNKNOWN"
                return 2
            fi
        else
            echo "NOT_STARTED"
            return 3
        fi
    fi
}

# Kill running job
kill_job() {
    local job_name="$1" 
    local pid_file="${LOG_DIR}/${job_name}.pid"
    
    if [[ -f "$pid_file" ]]; then
        local pid=$(cat "$pid_file")
        if kill -0 "$pid" 2>/dev/null; then
            echo "Killing job $job_name (PID: $pid)"
            kill -TERM "$pid"
            sleep 2
            if kill -0 "$pid" 2>/dev/null; then
                kill -KILL "$pid"
            fi
        fi
        rm -f "$pid_file"
    fi
}

# Export functions
export -f get_mpi_command
export -f execute_job
export -f check_input_files
export -f wait_for_files
export -f run_individuals_job
export -f run_individuals_merge_job  
export -f run_sifting_job
export -f run_mutation_overlap_job
export -f run_frequency_job
export -f launch_parallel_jobs
export -f check_job_status
export -f kill_job
