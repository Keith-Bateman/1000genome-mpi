#!/bin/bash

# Fixed multi-node Spack test
echo "=== Testing Spack Environment on Multiple Nodes ==="

# Test 1: Basic Spack availability
echo "Test 1: Basic Spack setup"
mpirun -np 2 --hostfile hostfile bash -c '
export SPACK_ROOT="/home/kbateman/spack"
export PATH="/home/kbateman/spack/bin:$PATH"
hostname=$(hostname)
echo "Node: $hostname"
echo "Spack: $(which spack 2>/dev/null || echo NOT_FOUND)"
if [[ -f "/home/kbateman/spack/share/spack/setup-env.sh" ]]; then
  echo "✓ Spack setup script exists on $hostname"
else
  echo "✗ Spack setup script missing on $hostname"
fi
'

echo ""
echo "Test 2: Spack environment activation"
mpirun -np 2 --hostfile hostfile bash -c '
export SPACK_ROOT="/home/kbateman/spack"
export PATH="/home/kbateman/spack/bin:$PATH"
hostname=$(hostname)
echo "=== Node: $hostname ==="

# Source Spack setup
if [[ -f "/home/kbateman/spack/share/spack/setup-env.sh" ]]; then
  source /home/kbateman/spack/share/spack/setup-env.sh
  echo "✓ Spack setup sourced on $hostname"
  
  # Check available environments
  echo "Available Spack environments:"
  spack env list 2>/dev/null || echo "No environments found"
  
  # Try to activate environment (replace with your env name)
  # For now, just test loading packages directly
  echo "Loading packages directly..."
  spack load py-mpi4py 2>/dev/null && echo "✓ py-mpi4py loaded" || echo "✗ py-mpi4py load failed"
  spack load python 2>/dev/null && echo "✓ python loaded" || echo "✗ python load failed"
  
else
  echo "✗ Spack setup script not found on $hostname"
fi
'

echo ""
echo "Test 3: Python and mpi4py test"
mpirun -np 2 --hostfile hostfile bash -c '
export SPACK_ROOT="/home/kbateman/spack"
export PATH="/home/kbateman/spack/bin:$PATH"
hostname=$(hostname)

# Source Spack
source /home/kbateman/spack/share/spack/setup-env.sh 2>/dev/null

# Load packages
spack load py-mpi4py python 2>/dev/null

echo "=== Python Test on $hostname ==="
echo "Python: $(which python3)"
echo "Python path check:"
python3 -c "
import sys
print(f\"Python executable: {sys.executable}\")
print(f\"Python version: {sys.version.split()[0]}\")
try:
    import mpi4py
    print(f\"✓ mpi4py found: {mpi4py.__file__}\")
    from mpi4py import MPI
    print(f\"✓ MPI imported successfully on $hostname\")
except ImportError as e:
    print(f\"✗ mpi4py import failed on $hostname: {e}\")
    sys.exit(1)
" 2>/dev/null || echo "Python test failed on $hostname"
'

echo ""
echo "=== Test Complete ==="
echo "If all tests pass, you can use this command structure for your workflow:"
echo "mpirun -np 16 --hostfile hostfile bash -c 'export SPACK_ROOT=\"/home/kbateman/spack\"; export PATH=\"/home/kbateman/spack/bin:\$PATH\"; source /home/kbateman/spack/share/spack/setup-env.sh; spack load py-mpi4py python; python3 individuals_mpi_proper.py [args]'"
