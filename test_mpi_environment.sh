#!/bin/bash

# Quick test script to verify MPI and Python environment
# Usage: ./test_mpi_environment.sh

echo "=== Testing MPI and Python Environment ==="
echo "Date: $(date)"
echo "Host: $(hostname)"
echo "User: $(whoami)"
echo "Working directory: $(pwd)"

echo ""
echo "=== Checking MPI ==="
if command -v mpirun &> /dev/null; then
    echo "✓ mpirun found: $(which mpirun)"
    mpirun --version 2>/dev/null || echo "mpirun version check failed"
else
    echo "✗ mpirun not found"
    exit 1
fi

echo ""
echo "=== Checking Python ==="
if command -v python3 &> /dev/null; then
    echo "✓ python3 found: $(which python3)"
    python3 --version
else
    echo "✗ python3 not found"
    exit 1
fi

echo ""
echo "=== Testing Python MPI Import ==="
python3 -c "
try:
    from mpi4py import MPI
    print('✓ mpi4py import successful')
    print(f'MPI version: {MPI.Get_version()}')
except ImportError as e:
    print(f'✗ mpi4py import failed: {e}')
    exit(1)
"

echo ""
echo "=== Testing Optional Libraries ==="
python3 -c "
try:
    import pydecaf
    print('✓ pydecaf available')
except ImportError:
    print('- pydecaf not available (optional)')

try:
    import pybredala  
    print('✓ pybredala available')
except ImportError:
    print('- pybredala not available (optional)')

try:
    import numpy
    print('✓ numpy available')
except ImportError:
    print('- numpy not available')
"

echo ""
echo "=== Testing Simple MPI Program ==="
cat > /tmp/test_mpi.py << 'EOF'
from mpi4py import MPI

comm = MPI.COMM_WORLD
rank = comm.Get_rank()
size = comm.Get_size()

print(f"Hello from rank {rank} of {size}")
EOF

echo "Running: mpirun -np 2 python3 /tmp/test_mpi.py"
if mpirun -np 2 python3 /tmp/test_mpi.py; then
    echo "✓ Basic MPI test successful"
else
    echo "✗ Basic MPI test failed"
    exit 1
fi

rm -f /tmp/test_mpi.py

echo ""
echo "=== Environment Test Complete ==="
echo "All tests passed! MPI and Python environment is working."
