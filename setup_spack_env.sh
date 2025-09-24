#!/bin/bash

# Spack Environment Setup for MPI Workflow
# This script helps propagate Spack environment to all MPI processes

WORKFLOW_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Method 1: Source Spack environment in each MPI process
setup_spack_method1() {
    echo "Setting up Spack environment propagation (Method 1: Source in each process)"
    
    # Create a wrapper script that sources Spack before running Python
    cat > "${WORKFLOW_DIR}/mpi_python_wrapper.sh" << 'EOF'
#!/bin/bash
# MPI Python wrapper that sources Spack environment

# Clear any existing system MPI paths to avoid conflicts
export PATH=$(echo $PATH | tr ':' '\n' | grep -v '/usr.*mpi' | tr '\n' ':' | sed 's/:$//')
export LD_LIBRARY_PATH=$(echo $LD_LIBRARY_PATH | tr ':' '\n' | grep -v '/usr.*mpi' | tr '\n' ':' | sed 's/:$//')

# Source Spack setup if available
if [[ -f "/opt/spack/share/spack/setup-env.sh" ]]; then
    source /opt/spack/share/spack/setup-env.sh
elif [[ -f "$HOME/spack/share/spack/setup-env.sh" ]]; then
    source $HOME/spack/share/spack/setup-env.sh
elif [[ -n "$SPACK_ROOT" ]]; then
    source $SPACK_ROOT/share/spack/setup-env.sh
fi

# Activate the Spack environment if specified
if [[ -n "$SPACK_ENV_NAME" ]]; then
    spack env activate "$SPACK_ENV_NAME"
elif [[ -n "$SPACK_ENV" ]]; then
    spack env activate "$SPACK_ENV"
fi

# Ensure Spack MPI is prioritized in PATH
if command -v spack &> /dev/null; then
    # Get Spack MPI installation prefix
    SPACK_MPI_PREFIX=$(spack location -i openmpi 2>/dev/null || spack location -i mpich 2>/dev/null || echo "")
    if [[ -n "$SPACK_MPI_PREFIX" ]]; then
        export PATH="$SPACK_MPI_PREFIX/bin:$PATH"
        export LD_LIBRARY_PATH="$SPACK_MPI_PREFIX/lib:$LD_LIBRARY_PATH"
    fi
fi

# Add workflow lib paths
export LD_LIBRARY_PATH="${WORKFLOW_DIR}/lib:${LD_LIBRARY_PATH}"
export PYTHONPATH="${WORKFLOW_DIR}/lib:${PYTHONPATH}"

# Verify we're using the right MPI
echo "DEBUG: Using MPI from: $(which mpirun 2>/dev/null || echo 'NOT FOUND')"

# Execute the Python script with all arguments
exec python3 "$@"
EOF
    
    chmod +x "${WORKFLOW_DIR}/mpi_python_wrapper.sh"
    echo "Created MPI Python wrapper: ${WORKFLOW_DIR}/mpi_python_wrapper.sh"
}

# Method 2: Export all Spack environment variables
setup_spack_method2() {
    echo "Setting up Spack environment propagation (Method 2: Export variables)"
    
    local env_file="${WORKFLOW_DIR}/spack_env_vars.sh"
    
    cat > "$env_file" << 'EOF'
#!/bin/bash
# Spack environment variables for MPI propagation

# Get current Spack environment variables
if command -v spack &> /dev/null; then
    # Export Spack paths
    export SPACK_ROOT="$(spack location -r 2>/dev/null || echo "")"
    export SPACK_ENV="$(spack env status 2>/dev/null | grep -o '/.*' || echo "")"
    
    # Get Python and library paths from Spack
    if [[ -n "$SPACK_ENV" ]]; then
        # Export the environment name for reactivation
        export SPACK_ENV_NAME="$(basename "$SPACK_ENV")"
        
        # Get paths from active environment
        spack_python_path="$(spack location -i python 2>/dev/null)/bin:$PATH"
        spack_lib_path="$(spack location -i python 2>/dev/null)/lib:$(spack find --format '{prefix}/lib' --loaded | tr '\n' ':')$LD_LIBRARY_PATH"
        spack_python_lib="$(spack find --format '{prefix}/lib/python*/site-packages' --loaded | tr '\n' ':')$PYTHONPATH"
        
        export PATH="$spack_python_path"
        export LD_LIBRARY_PATH="$spack_lib_path"
        export PYTHONPATH="$spack_python_lib"
    fi
fi
EOF
    
    source "$env_file"
    echo "Created Spack environment file: $env_file"
}

# Method 3: Use MPI environment propagation
setup_spack_method3() {
    echo "Setting up Spack environment propagation (Method 3: MPI -x flags)"
    
    # Get current environment variables to propagate
    local mpi_env_vars=""
    
    if [[ -n "$SPACK_ROOT" ]]; then
        mpi_env_vars="$mpi_env_vars -x SPACK_ROOT"
    fi
    
    if [[ -n "$SPACK_ENV" ]]; then
        mpi_env_vars="$mpi_env_vars -x SPACK_ENV"
    fi
    
    # Add Python and library paths
    mpi_env_vars="$mpi_env_vars -x PATH -x LD_LIBRARY_PATH -x PYTHONPATH"
    
    # Store in a file for the workflow to use
    echo "$mpi_env_vars" > "${WORKFLOW_DIR}/mpi_env_flags.txt"
    
    echo "MPI environment flags: $mpi_env_vars"
    echo "Saved to: ${WORKFLOW_DIR}/mpi_env_flags.txt"
}

# Auto-detect and recommend best method
auto_setup() {
    echo "Auto-detecting Spack setup..."
    
    if command -v spack &> /dev/null; then
        echo "✓ Spack command found"
        
        if spack env status &> /dev/null; then
            echo "✓ Spack environment is active"
            setup_spack_method1
            setup_spack_method2  
            setup_spack_method3
            echo ""
            echo "All methods set up. Recommended approach:"
            echo "1. Try Method 1 (wrapper script) first"
            echo "2. If that fails, try Method 2 (environment variables)"
            echo "3. Use Method 3 (MPI -x flags) as fallback"
        else
            echo "⚠ No active Spack environment detected"
            echo "Please activate your Spack environment first:"
            echo "  spack env activate <your-env-name>"
        fi
    else
        echo "✗ Spack not found in PATH"
        echo "Please ensure Spack is properly installed and sourced"
    fi
}

# Main execution
case "${1:-auto}" in
    "1"|"method1"|"wrapper")
        setup_spack_method1
        ;;
    "2"|"method2"|"export")
        setup_spack_method2
        ;;
    "3"|"method3"|"mpi")
        setup_spack_method3
        ;;
    "auto"|"")
        auto_setup
        ;;
    *)
        echo "Usage: $0 [method1|method2|method3|auto]"
        echo "  method1: Use wrapper script"
        echo "  method2: Export environment variables"  
        echo "  method3: Use MPI -x flags"
        echo "  auto: Auto-detect and set up all methods"
        ;;
esac
