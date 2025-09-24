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
