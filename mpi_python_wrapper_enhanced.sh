#!/bin/bash
# Enhanced MPI Python wrapper for multi-node Spack environment

# Debug: Show where we're running
echo "DEBUG: Running on $(hostname) as user $(whoami)"
echo "DEBUG: Original PATH: $PATH"
echo "DEBUG: Original LD_LIBRARY_PATH: $LD_LIBRARY_PATH"

# Clear problematic system paths first
export PATH=$(echo $PATH | tr ':' '\n' | grep -v '/usr.*mpi' | tr '\n' ':' | sed 's/:$//')
export LD_LIBRARY_PATH=$(echo $LD_LIBRARY_PATH | tr ':' '\n' | grep -v '/usr.*mpi' | tr '\n' ':' | sed 's/:$//')

# Try multiple Spack setup locations
SPACK_SETUP=""
for setup_path in \
    "/opt/spack/share/spack/setup-env.sh" \
    "$HOME/spack/share/spack/setup-env.sh" \
    "/usr/local/spack/share/spack/setup-env.sh" \
    "/apps/spack/share/spack/setup-env.sh"; do
    
    if [[ -f "$setup_path" ]]; then
        echo "DEBUG: Found Spack setup at: $setup_path"
        SPACK_SETUP="$setup_path"
        break
    fi
done

if [[ -n "$SPACK_SETUP" ]]; then
    echo "DEBUG: Sourcing Spack setup: $SPACK_SETUP"
    source "$SPACK_SETUP"
else
    echo "ERROR: No Spack setup found on $(hostname)"
    echo "Searched locations:"
    echo "  /opt/spack/share/spack/setup-env.sh"
    echo "  $HOME/spack/share/spack/setup-env.sh"
    echo "  /usr/local/spack/share/spack/setup-env.sh"
    echo "  /apps/spack/share/spack/setup-env.sh"
fi

# Try to activate Spack environment (use multiple methods)
if [[ -n "$SPACK_ENV_NAME" ]]; then
    echo "DEBUG: Activating Spack environment: $SPACK_ENV_NAME"
    spack env activate "$SPACK_ENV_NAME" 2>/dev/null || echo "WARNING: Could not activate $SPACK_ENV_NAME"
elif [[ -n "$SPACK_ENV" ]]; then
    echo "DEBUG: Activating Spack environment: $SPACK_ENV"
    spack env activate "$SPACK_ENV" 2>/dev/null || echo "WARNING: Could not activate $SPACK_ENV"
fi

# Load MPI packages directly if no environment
if command -v spack >/dev/null 2>&1; then
    echo "DEBUG: Spack command available, loading packages..."
    spack load py-mpi4py 2>/dev/null || echo "DEBUG: Could not load py-mpi4py"
    spack load python 2>/dev/null || echo "DEBUG: Could not load python"
    spack load openmpi 2>/dev/null || spack load mpich 2>/dev/null || echo "DEBUG: Could not load MPI"
else
    echo "WARNING: Spack command not available on $(hostname)"
fi

# Add workflow paths
export LD_LIBRARY_PATH="${WORKFLOW_DIR}/lib:${LD_LIBRARY_PATH}"
export PYTHONPATH="${WORKFLOW_DIR}/lib:${PYTHONPATH}"

# Show final environment
echo "DEBUG: Final PATH: $PATH"
echo "DEBUG: Final LD_LIBRARY_PATH: $LD_LIBRARY_PATH"
echo "DEBUG: Python location: $(which python3 2>/dev/null || echo 'NOT FOUND')"

# Test mpi4py before executing
echo "DEBUG: Testing mpi4py import..."
python3 -c "
try:
    from mpi4py import MPI
    print('DEBUG: mpi4py import successful on $(hostname)')
except ImportError as e:
    print(f'ERROR: mpi4py import failed on $(hostname): {e}')
    import sys
    sys.exit(1)
" || exit 1

# Execute the Python script
echo "DEBUG: Executing: python3 $*"
exec python3 "$@"
