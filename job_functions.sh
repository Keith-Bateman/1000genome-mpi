#!/bin/bash

###################################################################################
# Job Functions for 1000genome MPI Workflow
# Helper functions for different job types
###################################################################################

# Source this file to get job execution functions

# Get MPI command (mpirun or mpiexec)
get_mpi_command() {
    if [[ "$DRY_RUN" == "true" ]]; then
        echo "mpirun"  # Use mpirun for dry runs
        return 0
    fi
    
    if command -v mpirun &> /dev/null; then
        echo "mpirun"
    elif command -v mpiexec &> /dev/null; then
        echo "mpiexec"
    else
        echo "ERROR: Neither mpirun nor mpiexec found" >&2
        return 1
    fi
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
    local mpi_cmd=$(get_mpi_command) || return 1
    
    local input_file="${WORKFLOW_DIR}/data/${DATASET}/${vcf_file}"
    
    # For dry run, don't check files
    if [[ "$DRY_RUN" != "true" ]]; then
        # Validate inputs
        check_input_files "$input_file" "$columns_file" || return 1
    fi
    
    # Build command  
    local command="$mpi_cmd -np $num_procs python3 ${WORKFLOW_DIR}/bin/individuals_mpi.py \"$input_file\" \"$columns_file\" $chr_num $start_line $end_line $total_lines"
    
    execute_job "$job_name" "$command" 7200  # 2 hour timeout
}

# Individuals merge job runner
run_individuals_merge_job() {
    local chr_num="$1"
    local num_procs="${2:-$((NUM_MPI_PROCS + 1))}"  # Needs one extra process for merge
    
    local job_name="individuals_merge_chr${chr_num}"
    local mpi_cmd=$(get_mpi_command) || return 1
    
    # Build command
    local command="$mpi_cmd -np $num_procs python3 ${WORKFLOW_DIR}/bin/individuals_merge_mpi.py $chr_num"
    
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
