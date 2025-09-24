#!/bin/bash

# Diagnostic script for MPI library conflicts
# Run this to debug which MPI libraries are being used

echo "=== MPI Library Diagnostic ==="
echo "Date: $(date)"
echo "Node: $(hostname)"
echo "User: $(whoami)"
echo ""

echo "=== Environment Variables ==="
echo "PATH: $PATH"
echo ""
echo "LD_LIBRARY_PATH: $LD_LIBRARY_PATH"
echo ""
echo "SPACK_ROOT: $SPACK_ROOT"
echo "SPACK_ENV: $SPACK_ENV"
echo ""

echo "=== MPI Commands Location ==="
echo "which mpirun: $(which mpirun 2>/dev/null || echo 'NOT FOUND')"
echo "which mpiexec: $(which mpiexec 2>/dev/null || echo 'NOT FOUND')"
echo ""

echo "=== MPI Versions ==="
if command -v mpirun &> /dev/null; then
    echo "mpirun --version:"
    mpirun --version 2>&1 | head -3
else
    echo "mpirun not found in PATH"
fi
echo ""

echo "=== Library Dependencies ==="
if command -v mpirun &> /dev/null; then
    echo "ldd mpirun (showing MPI libraries):"
    ldd $(which mpirun) 2>/dev/null | grep -E "(mpi|pmix|orte)" || echo "No MPI-related libraries found"
else
    echo "Cannot check mpirun dependencies - not found"
fi
echo ""

echo "=== Spack Environment Status ==="
if command -v spack &> /dev/null; then
    echo "Spack found: $(which spack)"
    echo "Spack environment status:"
    spack env status 2>/dev/null || echo "No active environment or error"
    echo ""
    echo "Spack loaded packages:"
    spack find --loaded 2>/dev/null | grep -E "(mpi|openmpi|mpich)" || echo "No MPI packages loaded"
else
    echo "Spack not found in PATH"
fi
echo ""

echo "=== System MPI (Potential Conflicts) ==="
echo "System OpenMPI packages:"
dpkg -l | grep -E "(openmpi|libopenmpi)" 2>/dev/null || echo "No system OpenMPI packages found"
echo ""

echo "=== Python MPI4PY ==="
python3 -c "
try:
    import mpi4py
    print(f'mpi4py location: {mpi4py.__file__}')
    print(f'mpi4py version: {mpi4py.__version__}')
    from mpi4py import MPI
    print(f'MPI library version: {MPI.Get_version()}')
    print(f'MPI library name: {MPI.get_vendor()}')
except Exception as e:
    print(f'mpi4py error: {e}')
"
echo ""

echo "=== Recommendations ==="
echo "1. Make sure Spack environment is activated:"
echo "   spack env activate your-env-name"
echo ""
echo "2. Check that Spack MPI is in PATH before system MPI:"
echo "   which mpirun  # Should show Spack path, not /usr/bin/"
echo ""
echo "3. If using system MPI, try explicitly loading Spack modules:"
echo "   spack load openmpi  # or mpich"
echo ""
echo "4. For Slurm jobs, make sure to activate environment in job script:"
echo "   source /path/to/spack/setup-env.sh"
echo "   spack env activate your-env-name"
