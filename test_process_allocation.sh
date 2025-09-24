#!/bin/bash

# Quick test for MPI process count
echo "=== Testing MPI Process Allocation ==="

# Test with different process counts
for np in 1 2 4; do
    echo ""
    echo "Testing with $np processes:"
    echo "Command: mpirun -np $np python3 -c \"
from mpi4py import MPI
comm = MPI.COMM_WORLD
rank = comm.Get_rank()
size = comm.Get_size()
if rank == size - 1:
    print(f'Rank {rank}: MERGER (size={size}, workers={size-1})')
else:
    print(f'Rank {rank}: WORKER (size={size}, workers={size-1})')
\""
    
    mpirun -np $np python3 -c "
from mpi4py import MPI
comm = MPI.COMM_WORLD
rank = comm.Get_rank()
size = comm.Get_size()
if rank == size - 1:
    print(f'Rank {rank}: MERGER (size={size}, workers={size-1})')
else:
    print(f'Rank {rank}: WORKER (size={size}, workers={size-1})')
"
done

echo ""
echo "=== Analysis ==="
echo "- With 1 process: Rank 0 is merger, 0 workers = NO PROCESSING"
echo "- With 2 processes: Rank 1 is merger, 1 worker = MINIMAL PROCESSING"  
echo "- With 4 processes: Rank 3 is merger, 3 workers = GOOD PROCESSING"
echo ""
echo "For 2504 individuals, you want 8-16 processes for good performance."
