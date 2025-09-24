#!/bin/bash

# Enhanced Spack environment propagation for multi-node MPI
# This creates a more robust environment setup

WORKFLOW_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "=== Enhanced Spack Environment Setup ==="

# Method 1: Create a comprehensive wrapper script
create_enhanced_wrapper() {
    echo "Creating enhanced MPI wrapper..."
    
    cat > "${WORKFLOW_DIR}/mpi_python_wrapper_enhanced.sh" << 'EOF'
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
EOF

    chmod +x "${WORKFLOW_DIR}/mpi_python_wrapper_enhanced.sh"
    echo "✓ Created enhanced wrapper: ${WORKFLOW_DIR}/mpi_python_wrapper_enhanced.sh"
}

# Method 2: Create environment export script with full paths
create_full_env_export() {
    echo "Creating full environment export..."
    
    if command -v spack >/dev/null 2>&1; then
        # Get current Spack environment info
        SPACK_ROOT_PATH=$(spack location -r 2>/dev/null || echo "")
        SPACK_ENV_PATH=$(spack env status 2>/dev/null | grep -o '/.*' || echo "")
        
        # Get Python and MPI installation paths
        SPACK_PYTHON_PATH=$(spack location -i python 2>/dev/null || echo "")
        SPACK_MPI_PATH=$(spack location -i openmpi 2>/dev/null || spack location -i mpich 2>/dev/null || echo "")
        SPACK_MPI4PY_PATH=$(spack location -i py-mpi4py 2>/dev/null || echo "")
        
        cat > "${WORKFLOW_DIR}/spack_env_full.sh" << EOF
#!/bin/bash
# Full Spack environment with absolute paths

# Spack root and environment
export SPACK_ROOT="$SPACK_ROOT_PATH"
export SPACK_ENV="$SPACK_ENV_PATH"

# Clear system MPI paths
export PATH=\$(echo \$PATH | tr ':' '\n' | grep -v '/usr.*mpi' | tr '\n' ':' | sed 's/:\$//')
export LD_LIBRARY_PATH=\$(echo \$LD_LIBRARY_PATH | tr ':' '\n' | grep -v '/usr.*mpi' | tr '\n' ':' | sed 's/:\$//')

# Add Spack paths
EOF

        # Add Python paths if found
        if [[ -n "$SPACK_PYTHON_PATH" ]]; then
            echo "export PATH=\"$SPACK_PYTHON_PATH/bin:\$PATH\"" >> "${WORKFLOW_DIR}/spack_env_full.sh"
            echo "export LD_LIBRARY_PATH=\"$SPACK_PYTHON_PATH/lib:\$LD_LIBRARY_PATH\"" >> "${WORKFLOW_DIR}/spack_env_full.sh"
            
            # Find Python site-packages
            PYTHON_SITE_PACKAGES=$(find "$SPACK_PYTHON_PATH" -name "site-packages" -type d | head -1)
            if [[ -n "$PYTHON_SITE_PACKAGES" ]]; then
                echo "export PYTHONPATH=\"$PYTHON_SITE_PACKAGES:\$PYTHONPATH\"" >> "${WORKFLOW_DIR}/spack_env_full.sh"
            fi
        fi
        
        # Add MPI paths if found
        if [[ -n "$SPACK_MPI_PATH" ]]; then
            echo "export PATH=\"$SPACK_MPI_PATH/bin:\$PATH\"" >> "${WORKFLOW_DIR}/spack_env_full.sh"
            echo "export LD_LIBRARY_PATH=\"$SPACK_MPI_PATH/lib:\$LD_LIBRARY_PATH\"" >> "${WORKFLOW_DIR}/spack_env_full.sh"
        fi
        
        # Add mpi4py paths if found
        if [[ -n "$SPACK_MPI4PY_PATH" ]]; then
            MPI4PY_SITE_PACKAGES=$(find "$SPACK_MPI4PY_PATH" -name "site-packages" -type d | head -1)
            if [[ -n "$MPI4PY_SITE_PACKAGES" ]]; then
                echo "export PYTHONPATH=\"$MPI4PY_SITE_PACKAGES:\$PYTHONPATH\"" >> "${WORKFLOW_DIR}/spack_env_full.sh"
            fi
        fi
        
        # Add workflow paths
        cat >> "${WORKFLOW_DIR}/spack_env_full.sh" << 'EOF'

# Add workflow paths
export LD_LIBRARY_PATH="${WORKFLOW_DIR}/lib:${LD_LIBRARY_PATH}"
export PYTHONPATH="${WORKFLOW_DIR}/lib:${PYTHONPATH}"

# Export environment name for reactivation
if [[ -n "$SPACK_ENV" ]]; then
    export SPACK_ENV_NAME="$(basename "$SPACK_ENV")"
fi

echo "DEBUG: Environment loaded on $(hostname)"
echo "DEBUG: Python: $(which python3 2>/dev/null || echo 'NOT FOUND')"
echo "DEBUG: MPI: $(which mpirun 2>/dev/null || echo 'NOT FOUND')"
EOF

        chmod +x "${WORKFLOW_DIR}/spack_env_full.sh"
        echo "✓ Created full environment export: ${WORKFLOW_DIR}/spack_env_full.sh"
        
    else
        echo "✗ Spack not available for full environment export"
    fi
}

# Method 3: Create a simple test script
create_node_test() {
    echo "Creating node test script..."
    
    cat > "${WORKFLOW_DIR}/test_node_env.sh" << 'EOF'
#!/bin/bash
# Test script to run on each node

echo "=== Node Environment Test ==="
echo "Node: $(hostname)"
echo "User: $(whoami)"
echo "Home: $HOME"
echo "Working dir: $(pwd)"
echo ""

echo "=== Path Information ==="
echo "PATH: $PATH"
echo "LD_LIBRARY_PATH: $LD_LIBRARY_PATH"
echo "PYTHONPATH: $PYTHONPATH"
echo ""

echo "=== Command Locations ==="
echo "Python: $(which python3 2>/dev/null || echo 'NOT FOUND')"
echo "MPI: $(which mpirun 2>/dev/null || echo 'NOT FOUND')"
echo "Spack: $(which spack 2>/dev/null || echo 'NOT FOUND')"
echo ""

echo "=== Python MPI4PY Test ==="
python3 -c "
import sys
print(f'Python executable: {sys.executable}')
print(f'Python path: {sys.path[:3]}...')

try:
    import mpi4py
    print(f'✓ mpi4py found: {mpi4py.__file__}')
    from mpi4py import MPI
    print(f'✓ MPI imported successfully')
except ImportError as e:
    print(f'✗ mpi4py import failed: {e}')
    sys.exit(1)
"

echo "=== Test Complete ==="
EOF
    
    chmod +x "${WORKFLOW_DIR}/test_node_env.sh"
    echo "✓ Created node test script: ${WORKFLOW_DIR}/test_node_env.sh"
}

# Run all methods
create_enhanced_wrapper
create_full_env_export  
create_node_test

echo ""
echo "=== Testing Node Environments ==="
echo "Testing environment propagation across nodes..."

# Test each node individually first
if [[ -f "hostfile" ]]; then
    echo "Using hostfile to test individual nodes:"
    cat hostfile | while read node slots; do
        node_name=$(echo $node | cut -d' ' -f1)
        echo ""
        echo "Testing node: $node_name"
        ssh "$node_name" "cd $(pwd) && ./test_node_env.sh" 2>/dev/null || echo "✗ Could not connect to $node_name"
    done
else
    echo "No hostfile found, skipping individual node tests"
fi

echo ""
echo "=== Setup Complete ==="
echo "Try these commands in order:"
echo ""
echo "1. Test with enhanced wrapper:"
echo "mpirun -np 4 --hostfile hostfile ./mpi_python_wrapper_enhanced.sh -c 'from mpi4py import MPI; print(f\"Rank {MPI.COMM_WORLD.Get_rank()} on {MPI.Get_processor_name()}\")'"
echo ""
echo "2. Test with full environment:"
echo "mpirun -np 4 --hostfile hostfile bash -c 'source ./spack_env_full.sh && python3 -c \"from mpi4py import MPI; print(f\\\"Rank {MPI.COMM_WORLD.Get_rank()} on {MPI.Get_processor_name()}\\\")\"'"
echo ""
echo "3. Run your actual workflow:"
echo "mpirun -np 16 --hostfile hostfile ./mpi_python_wrapper_enhanced.sh /path/to/individuals_mpi_proper.py ..."
