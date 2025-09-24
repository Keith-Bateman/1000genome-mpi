#!/bin/bash

# Test Spack MPI environment setup

WORKFLOW_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "Testing Spack MPI environment setup..."

# Step 1: Set up Spack environment propagation
echo "Step 1: Setting up Spack environment..."
./setup_spack_env.sh auto

echo ""
echo "Step 2: Testing MPI environment across nodes..."
if [[ -f "${1:-localhost.hosts}" ]]; then
    ./check_mpi_env.sh "${1:-localhost.hosts}"
else
    echo "Warning: No hostfile found, testing with localhost only"
    ./check_mpi_env.sh
fi

echo ""
echo "Step 3: Testing a simple MPI Python script..."
cat > test_mpi_simple.py << 'EOF'
#!/usr/bin/env python3
try:
    from mpi4py import MPI
    comm = MPI.COMM_WORLD
    rank = comm.Get_rank()
    size = comm.Get_size()
    import socket
    hostname = socket.gethostname()
    print(f"SUCCESS: Rank {rank}/{size} on {hostname}")
except Exception as e:
    import socket
    hostname = socket.gethostname()
    print(f"FAILED: Rank ? on {hostname}: {e}")
EOF

# Test with the workflow's MPI command system
echo "Testing get_mpi_command function..."
source job_functions.sh
source config.sh

# Set required variables for testing
NUM_MPI_PROCS=${NUM_MPI_PROCS:-4}
HOSTFILE=${1:-"localhost.hosts"}

if [[ -f "$HOSTFILE" ]]; then
    echo "Using hostfile: $HOSTFILE"
else
    echo "Hostfile not found, using localhost"
    unset HOSTFILE
fi

test_cmd=$(get_mpi_command "test_mpi_simple.py")
echo "Running: $test_cmd"

if [[ "$test_cmd" != *"ERROR"* ]]; then
    eval "$test_cmd"
else
    echo "Error in MPI command generation: $test_cmd"
fi

# Cleanup
rm -f test_mpi_simple.py

echo ""
echo "Setup complete! Try running the workflow now:"
echo "./run_workflow_mpi.sh --dry-run -v"
echo ""
echo "For actual execution with your hostfile:"
echo "./run_workflow_mpi.sh -p 16 --hostfile=your_hostfile -c \"1\" -v"
