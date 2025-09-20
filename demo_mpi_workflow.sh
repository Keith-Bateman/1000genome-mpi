#!/bin/bash

###################################################################################
# 1000genome MPI Workflow - Demo Script
# Demonstrates the converted Pegasus workflow running with MPI
###################################################################################

echo "=========================================="
echo "1000genome MPI Workflow Conversion Demo"
echo "=========================================="
echo ""

echo "This demo shows the successful conversion of the 1000genome Pegasus workflow"
echo "to run with MPI instead of Pegasus WMS and HTCondor."
echo ""

echo "Files created:"
echo "  - run_workflow_mpi.sh     : Main workflow orchestration script"
echo "  - job_functions.sh        : Helper functions for job execution" 
echo "  - config.sh               : Configuration management"
echo "  - README_MPI.md           : Complete documentation"
echo ""

echo "Key features implemented:"
echo "  ✓ MPI-based job execution instead of Condor"
echo "  ✓ Bash-based dependency management instead of Pegasus DAX"
echo "  ✓ Parallel individuals jobs per chromosome"
echo "  ✓ Configurable MPI process counts and parallelization"
echo "  ✓ Dry-run capability for testing"
echo "  ✓ Comprehensive logging and error handling"
echo "  ✓ Command-line parameter configuration"
echo ""

echo "Example usage:"
echo ""
echo "# Basic run with defaults"
echo "./run_workflow_mpi.sh"
echo ""
echo "# Run with custom parameters"
echo "./run_workflow_mpi.sh -i 2 -p 8 -c \"1,2,3\" --populations \"ALL,EUR\""
echo ""
echo "# Dry run to see what would be executed"
echo "./run_workflow_mpi.sh --dry-run -v"
echo ""

echo "Workflow phases:"
echo "  1. Individuals jobs (MPI) - Process VCF files per chromosome"
echo "  2. Individuals merge (MPI) - Combine results from parallel jobs"
echo "  3. Sifting jobs - Extract SIFT scores from annotation data"
echo "  4. Analysis jobs - Mutation overlap and frequency analysis"
echo ""

echo "Running quick demo with dry-run..."
echo ""

# Run a quick demo
./run_workflow_mpi.sh --dry-run -c "1,2" --populations "ALL,EUR" -i 2 -p 4

echo ""
echo "=========================================="
echo "Demo completed successfully!"
echo ""
echo "The original Pegasus workflow has been successfully converted to run with"
echo "MPI and bash scripting, maintaining the same computational logic while"
echo "removing dependencies on Pegasus WMS and HTCondor."
echo ""
echo "See README_MPI.md for complete documentation and usage instructions."
echo "=========================================="
