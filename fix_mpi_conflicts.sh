#!/bin/bash

# Quick fix for MPI library conflicts
# Run this before executing your workflow

echo "=== MPI Library Conflict Fix ==="
echo "This script will prioritize Spack MPI over system MPI"
echo ""

# Check current MPI
echo "Current MPI location: $(which mpirun 2>/dev/null || echo 'NOT FOUND')"
echo ""

# Method 1: Remove system MPI paths from environment
echo "1. Removing system MPI paths from environment..."
export PATH=$(echo $PATH | tr ':' '\n' | grep -v '/usr.*mpi' | tr '\n' ':' | sed 's/:$//')
export LD_LIBRARY_PATH=$(echo $LD_LIBRARY_PATH | tr ':' '\n' | grep -v '/usr.*mpi' | tr '\n' ':' | sed 's/:$//')

# Method 2: Ensure Spack is sourced
echo "2. Sourcing Spack environment..."
if command -v spack &> /dev/null; then
    echo "✓ Spack found: $(which spack)"
    
    # Try to activate environment if one exists
    if spack env status &> /dev/null; then
        echo "✓ Spack environment already active"
    else
        echo "⚠ No active Spack environment"
        echo "You may need to run: spack env activate your-env-name"
    fi
    
    # Load MPI package if not in environment
    echo "3. Loading Spack MPI package..."
    if ! spack find --loaded | grep -q -E "(openmpi|mpich)"; then
        echo "Loading OpenMPI from Spack..."
        spack load openmpi 2>/dev/null || spack load mpich 2>/dev/null || echo "Could not load MPI package"
    else
        echo "✓ MPI package already loaded"
    fi
    
    # Prioritize Spack MPI in PATH
    echo "4. Prioritizing Spack MPI in PATH..."
    SPACK_MPI_PREFIX=$(spack location -i openmpi 2>/dev/null || spack location -i mpich 2>/dev/null || echo "")
    if [[ -n "$SPACK_MPI_PREFIX" ]]; then
        export PATH="$SPACK_MPI_PREFIX/bin:$PATH"
        export LD_LIBRARY_PATH="$SPACK_MPI_PREFIX/lib:$LD_LIBRARY_PATH"
        echo "✓ Spack MPI prioritized: $SPACK_MPI_PREFIX"
    else
        echo "✗ Could not find Spack MPI installation"
    fi
    
else
    echo "✗ Spack not found in PATH"
    echo "Please source your Spack setup first:"
    echo "  source /path/to/spack/share/spack/setup-env.sh"
    exit 1
fi

echo ""
echo "=== Results ==="
echo "New MPI location: $(which mpirun 2>/dev/null || echo 'NOT FOUND')"
if command -v mpirun &> /dev/null; then
    echo "MPI version:"
    mpirun --version 2>&1 | head -2
    
    # Test MPI libraries
    echo "MPI library check:"
    ldd $(which mpirun) 2>/dev/null | grep -E "(openmpi|pmix)" | head -3 || echo "No OpenMPI libraries found"
else
    echo "✗ MPI still not found"
    exit 1
fi

echo ""
echo "=== Python MPI Test ==="
echo "Checking mpi4py installation..."
python3 -c "
import sys
try:
    import mpi4py
    print(f'mpi4py location: {mpi4py.__file__}')
    print(f'mpi4py version: {mpi4py.__version__}')
except ImportError as e:
    print(f'✗ mpi4py not installed: {e}')
    sys.exit(1)

try:
    from mpi4py import MPI
    print('✓ mpi4py imported successfully')
    print(f'MPI version: {MPI.Get_version()}')
    print(f'MPI vendor: {MPI.get_vendor()}')
except ImportError as e:
    print(f'✗ mpi4py import failed: {e}')
    print('This usually means mpi4py was compiled against a different MPI version.')
    print('Solutions:')
    print('  1. spack install py-mpi4py && spack load py-mpi4py')
    print('  2. pip install --no-binary=mpi4py mpi4py')
    sys.exit(1)
except Exception as e:
    print(f'✗ MPI initialization failed: {e}')
    sys.exit(1)
"

echo ""
echo "=== Environment Fixed! ==="
echo "You can now run your workflow:"
echo "./run_workflow_mpi.sh -p 16 --hostfile=hostfile -c \"1\" -v"
echo ""
echo "Or export these environment variables for your current session:"
echo "export PATH=\"$PATH\""
echo "export LD_LIBRARY_PATH=\"$LD_LIBRARY_PATH\""
