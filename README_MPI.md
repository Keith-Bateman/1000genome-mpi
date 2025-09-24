# 1000genome MPI Workflow

This directory contains an MPI-based implementation of the 1000genome workflow, converted from the original Pegasus/Condor version to run with pure MPI and bash scripting.

## Overview

The workflow processes genomic data from the 1000 Genomes Project to identify mutational overlaps. It has been converted to use MPI for parallel execution instead of relying on Pegasus WMS and HTCondor.

## Prerequisites

### System Requirements
- **MPI**: OpenMPI, MPICH, or Intel MPI
- **Python 3.8+** with the following packages:
  - `mpi4py`
  - `numpy`
  - `matplotlib`
  - `pybredala` (included in lib/)
  - `pydecaf` (included in lib/)

### Hardware Requirements
- **Memory**: Minimum 4GB RAM, recommended 8GB+
- **Disk Space**: Minimum 10GB free space
- **CPU**: Multi-core processor recommended

### Spack Environment Setup

If you're using **Spack** for package management (common on HPC clusters), set up the environment for multi-node execution:

```bash
# 1. Activate your Spack environment
spack env activate your-mpi-env

# 2. Set up MPI environment propagation
./setup_spack_env.sh auto

# 3. Test the setup
./test_spack_mpi.sh your_hostfile

# 4. Run demo workflow
./demo_mpi_workflow.sh your_hostfile
```

The setup script creates multiple methods to ensure `mpi4py` is available on all compute nodes:
- **Method 1**: Wrapper script that sources Spack on each node
- **Method 2**: Environment variable propagation via MPI
- **Method 3**: MPI `-x` flags for variable passing

## Quick Start

### 1. Prepare Input Data
```bash
# Unzip input data files
./prepare_input.sh
```

### 2. Run the Workflow

**Single Node Examples:**
```bash
# Run with default settings (all chromosomes, all populations)
./run_workflow_mpi.sh

# Run with custom parameters  
./run_workflow_mpi.sh -i 2 -p 8 -c "1,2,3" --populations "ALL,EUR"

# Dry run to see what would be executed
./run_workflow_mpi.sh --dry-run -v
```

**Multi-Node Examples:**
```bash
# Test single chromosome with 16 processes across nodes
./run_workflow_mpi.sh -p 16 --hostfile=hosts.txt -c "1" --populations "ALL" -v --timeout 10800

# Run multiple chromosomes with 32 processes
./run_workflow_mpi.sh -p 32 --hostfile=hosts.txt -c "1,2,22" --populations "ALL,EUR" -v

# Full workflow with additional MPI tuning
./run_workflow_mpi.sh -p 64 --hostfile=hosts.txt --mpi-args "--bind-to core --map-by node" --timeout 14400 -v
```

**Hostfile Format:**
```
node1 slots=8
node2 slots=8  
node3 slots=16
node4 slots=16
```

## Workflow Structure

The workflow consists of several phases:

### Phase 1: Data Processing (per chromosome)
1. **Individuals Jobs**: Process VCF files to extract individual genetic data
   - Uses `bin/individuals_mpi.py` 
   - Can be parallelized with multiple jobs per chromosome
   - Runs with MPI for inter-process communication

2. **Individuals Merge**: Combine results from parallel individuals jobs
   - Uses `bin/individuals_merge_mpi.py`
   - Aggregates data from multiple individuals jobs

3. **Sifting**: Extract SIFT scores from annotation files
   - Uses `bin/sifting.py`
   - Processes variant effect predictor data

### Phase 2: Analysis (per chromosome-population combination)
4. **Mutation Overlap**: Analyze mutation overlaps between individuals
   - Uses `bin/mutation_overlap.py`
   - Depends on individuals merge and sifting outputs

5. **Frequency Analysis**: Calculate mutation frequencies
   - Uses `bin/frequency.py`
   - Depends on individuals merge and sifting outputs

## Command Line Options

```
Usage: ./run_workflow_mpi.sh [OPTIONS]

OPTIONS:
    -d, --dataset DIR       Dataset directory name (default: 20130502)
    -i, --individuals N     Number of individuals jobs per chromosome (default: 1)
    -p, --processes N       Number of MPI processes (default: 4)
    -o, --output DIR        Output directory (default: ./workflow_output)
    -c, --chromosomes LIST  Comma-separated list of chromosomes (default: all from data.csv)
    --populations LIST      Comma-separated list of populations (default: ALL,EUR,EAS,AFR,AMR,SAS,GBR)
    --dry-run              Show commands without executing
    -v, --verbose          Enable verbose output
    -h, --help             Show help message
```

## Configuration

### Environment Setup
The workflow sources `env.sh` if available for environment configuration:
```bash
# Example env.sh content
module load mpi/openmpi
module load python/3.8
export LD_LIBRARY_PATH="${PWD}/lib:${LD_LIBRARY_PATH}"
export PYTHONPATH="${PWD}/lib:${PYTHONPATH}"
```

### Advanced Configuration
Edit `config.sh` to customize:
- Timeout values
- Resource requirements  
- File patterns
- MPI settings

## Input Data Structure

```
data/
├── 20130502/                    # Dataset directory
│   ├── ALL.chr1.250000.vcf.gz   # VCF files (compressed)
│   ├── ALL.chr2.250000.vcf.gz
│   ├── ...
│   ├── columns.txt              # Column definitions
│   └── *.annotation.vcf         # Annotation files for sifting
└── populations/                 # Population files
    ├── ALL
    ├── EUR
    ├── EAS
    ├── AFR
    ├── AMR
    ├── SAS
    └── GBR
```

## Output Structure

```
workflow_output/
├── logs/                        # Job logs
│   ├── workflow.log            # Main workflow log
│   ├── individuals_chr1_*.log  # Individual job logs
│   ├── sifting_chr1.log
│   └── ...
├── chr1n.tar.gz                # Individuals results (per chromosome)
├── sifted.SIFT.chr1.txt        # Sifting results
├── chr1-ALL.tar.gz             # Mutation overlap results
├── chr1-ALL-freq.tar.gz        # Frequency analysis results
└── ...
```

## Monitoring and Debugging

### View Workflow Progress
```bash
# Monitor main workflow log
tail -f workflow_output/logs/workflow.log

# Check specific job logs
tail -f workflow_output/logs/individuals_chr1_*.log
```

### Job Status
```bash
# List running MPI processes
ps aux | grep mpi

# Check job completion
ls -la workflow_output/logs/*.log
```

### Common Issues

1. **MPI Process Count**: Ensure MPI process count doesn't exceed available cores
2. **Memory Issues**: Reduce individuals jobs per chromosome if memory limited
3. **File Permissions**: Ensure input files are readable and output directory is writable
4. **Module Loading**: Check if required environment modules are loaded

## Performance Tuning

### Parallelization Options
- **Individuals Jobs**: Use `-i N` to create N parallel jobs per chromosome
- **MPI Processes**: Use `-p N` to set MPI process count  
- **Chromosome Selection**: Use `-c "1,2,3"` to process only specific chromosomes

### Memory Optimization
From the original documentation, memory requirements scale with parallelization:

| Individuals Jobs per Chromosome | Lines per Job | Memory per Job |
|:-------------------------------:|:-------------:|:--------------:|
| 1                              | 250,000       | ~6GB          |
| 2                              | 125,000       | ~4GB          |  
| 5                              | 50,000        | ~3GB          |
| 10                             | 25,000        | ~2GB          |

### Example Configurations

```bash
# High memory, single chromosome
./run_workflow_mpi.sh -i 1 -p 4 -c "1"

# Memory constrained, multiple jobs
./run_workflow_mpi.sh -i 5 -p 8 -c "1,2,3"

# Full workflow, balanced
./run_workflow_mpi.sh -i 2 -p 6
```

## Comparison with Pegasus Version

| Aspect | Pegasus Version | MPI Version |
|:-------|:---------------:|:-----------:|
| **Job Scheduling** | HTCondor | Bash + MPI |
| **Dependency Management** | Pegasus DAX | Bash scripting |
| **Parallelization** | Condor slots | MPI processes |
| **Monitoring** | Pegasus dashboard | Log files |
| **Resource Management** | HTCondor | Manual configuration |
| **Fault Tolerance** | Pegasus retry | Manual restart |

## Troubleshooting

### Environment Issues
```bash
# Check MPI installation
which mpirun mpiexec
mpirun --version

# Check Python packages
python3 -c "import mpi4py; print('mpi4py OK')"
python3 -c "import numpy; print('numpy OK')"

# Check library paths
ls -la lib/
```

### Job Failures
```bash
# Check job logs for errors
grep -i error workflow_output/logs/*.log

# Validate input files
ls -la data/20130502/
ls -la data/populations/
```

### Performance Issues
```bash
# Monitor resource usage
top -p $(pgrep -d, -f "python.*mpi")
htop

# Check disk space
df -h
```

### Quick Environment Test

Before running the workflow, test your environment:
```bash
./test_mpi_environment.sh
```

### Common Execution Issues

1. **"one or more individuals jobs failed"**
   - Most common cause: argument mismatch or missing files
   - Solution: The workflow now uses `individuals_mpi_fixed.py` with better error handling
   - Check that `columns.txt` exists (auto-symlinked from `data/20130502/`)

2. **MPI Import Errors**
   ```bash
   # Install MPI dependencies
   sudo apt-get install openmpi-bin openmpi-common libopenmpi-dev
   pip install mpi4py
   ```

3. **Compressed File Handling**
   - The improved script automatically handles `.gz` files
   - No need to decompress VCF files manually

4. **Debugging Individual Jobs**
   ```bash
   # Test a single chromosome manually
   cd /path/to/workflow
   mpirun -np 4 python3 bin/individuals_mpi_fixed.py \
     "data/20130502/ALL.chr22.phase3_shapeit2_mvncall_integrated_v5a.20130502.genotypes.vcf.gz" \
     22 1 1000 50000
   ```

## Files Overview

- `run_workflow_mpi.sh` - Main workflow orchestration script
- `job_functions.sh` - Helper functions for job execution
- `config.sh` - Configuration management
- `README_MPI.md` - This documentation
- `bin/*_mpi.py` - MPI-enabled Python scripts
- `bin/*.py` - Standard Python analysis scripts
- `lib/` - Decaf/Bredala MPI libraries

## License

Same as original 1000genome workflow - see LICENSE file.
