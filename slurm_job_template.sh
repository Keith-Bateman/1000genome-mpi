#!/bin/bash
#SBATCH --job-name=1000genome-mpi
#SBATCH --nodes=4
#SBATCH --ntasks-per-node=4
#SBATCH --cpus-per-task=1
#SBATCH --time=04:00:00
#SBATCH --mem=32G
#SBATCH --output=1000genome_%j.out
#SBATCH --error=1000genome_%j.err

# 1000 Genomes MPI Workflow - Slurm Job Script
# This script properly sets up Spack environment to avoid MPI conflicts

set -e  # Exit on any error

echo "=== Job Information ==="
echo "Job ID: $SLURM_JOB_ID"
echo "Job Name: $SLURM_JOB_NAME"
echo "Nodes: $SLURM_JOB_NUM_NODES"
echo "Tasks: $SLURM_NTASKS"
echo "Start Time: $(date)"
echo "Working Directory: $SLURM_SUBMIT_DIR"
echo ""

# Change to the workflow directory
cd $SLURM_SUBMIT_DIR
WORKFLOW_DIR="$SLURM_SUBMIT_DIR"

echo "=== Environment Setup ==="

# Method 1: Source Spack setup (MODIFY THESE PATHS FOR YOUR SYSTEM)
# Uncomment and modify the path that matches your Spack installation:

# Option A: Standard Spack installation
# source /opt/spack/share/spack/setup-env.sh

# Option B: Home directory Spack installation  
# source $HOME/spack/share/spack/setup-env.sh

# Option C: Custom Spack installation
# source /path/to/your/spack/share/spack/setup-env.sh

# Activate your Spack environment (MODIFY THE ENVIRONMENT NAME)
# spack env activate your-mpi-environment-name

# Method 2: Alternative - Load specific Spack packages
# If you don't use Spack environments, load the packages directly:
# spack load openmpi  # or spack load mpich
# spack load python
# spack load py-mpi4py

# Method 3: Module system (if your cluster uses modules)
# module load spack
# module load openmpi/4.1.1
# module load python/3.9
# module load mpi4py

echo "Current environment after Spack setup:"
echo "PATH: $PATH"
echo "LD_LIBRARY_PATH: $LD_LIBRARY_PATH"
echo "PYTHONPATH: $PYTHONPATH"
echo ""

# Verify MPI setup
echo "=== MPI Verification ==="
echo "MPI command: $(which mpirun 2>/dev/null || echo 'NOT FOUND')"
if command -v mpirun &> /dev/null; then
    echo "MPI version:"
    mpirun --version | head -2
else
    echo "ERROR: mpirun not found after Spack setup!"
    echo "Please check your Spack environment configuration."
    exit 1
fi
echo ""

# Test Python MPI
echo "=== Python MPI Test ==="
python3 -c "
try:
    from mpi4py import MPI
    print('✓ mpi4py imported successfully')
    print(f'MPI version: {MPI.Get_version()}')
    print(f'MPI vendor: {MPI.get_vendor()}')
except ImportError as e:
    print(f'✗ mpi4py import failed: {e}')
    exit(1)
"
echo ""

# Set up the workflow environment
echo "=== Workflow Setup ==="
./setup_spack_env.sh auto

# Create hostfile from Slurm allocation
echo "=== Creating Hostfile ==="
scontrol show hostnames $SLURM_JOB_NODELIST > hostfile
echo "Nodes in job:"
cat hostfile
echo ""

# Add slots information to hostfile (tasks per node)
TASKS_PER_NODE=$((SLURM_NTASKS / SLURM_JOB_NUM_NODES))
echo "Tasks per node: $TASKS_PER_NODE"

# Create proper hostfile format
cat hostfile | while read node; do
    echo "$node slots=$TASKS_PER_NODE"
done > hostfile_with_slots

echo "Hostfile with slots:"
cat hostfile_with_slots
echo ""

# Run the workflow
echo "=== Running 1000 Genomes Workflow ==="
echo "Command: ./run_workflow_mpi.sh -p $SLURM_NTASKS --hostfile=hostfile_with_slots -c \"1\" --populations \"ALL\" -v --timeout 10800"
echo ""

# Execute the workflow
./run_workflow_mpi.sh \
    -p $SLURM_NTASKS \
    --hostfile=hostfile_with_slots \
    -c "1" \
    --populations "ALL" \
    -v \
    --timeout 10800

EXIT_CODE=$?

echo ""
echo "=== Job Complete ==="
echo "End Time: $(date)"
echo "Exit Code: $EXIT_CODE"

if [[ $EXIT_CODE -eq 0 ]]; then
    echo "✓ Workflow completed successfully!"
else
    echo "✗ Workflow failed with exit code $EXIT_CODE"
    echo "Check the logs in workflow_output/logs/ for details"
fi

exit $EXIT_CODE
