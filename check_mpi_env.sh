#!/bin/bash

# MPI Environment Diagnostic Script
# Run this to check Python/mpi4py availability across all MPI processes

echo "Checking MPI environment across all processes..."

mpirun -np 4 --hostfile=${1:-localhost.hosts} bash -c '
echo "=== Process $OMPI_COMM_WORLD_RANK on $(hostname) ==="
echo "Python path: $(which python3)"
echo "Python version: $(python3 --version 2>&1)"
echo "PYTHONPATH: $PYTHONPATH"
echo "LD_LIBRARY_PATH: $LD_LIBRARY_PATH"
echo "SPACK_ENV: $SPACK_ENV"
echo "PATH: $PATH"
echo -n "mpi4py test: "
python3 -c "
try:
    from mpi4py import MPI
    print(f\"SUCCESS - MPI rank {MPI.COMM_WORLD.Get_rank()}/{MPI.COMM_WORLD.Get_size()}\")
except Exception as e:
    print(f\"FAILED - {e}\")
" 2>&1
echo "====================================="
'
