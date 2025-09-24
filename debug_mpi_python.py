#!/usr/bin/env python3
"""
Debug script to check Python environment across MPI processes
"""
import os
import socket
import sys

print(f"=== Node: {socket.gethostname()} ===")
print(f"Python executable: {sys.executable}")
print(f"Python version: {sys.version}")
print(f"Python path: {sys.path}")
print(f"Current working directory: {os.getcwd()}")
print(f"USER: {os.environ.get('USER', 'unknown')}")
print(f"HOME: {os.environ.get('HOME', 'unknown')}")
print(f"PATH: {os.environ.get('PATH', 'unknown')}")
print(f"PYTHONPATH: {os.environ.get('PYTHONPATH', 'not set')}")

# Test mpi4py import
try:
    import mpi4py
    print(f"✓ mpi4py available at: {mpi4py.__file__}")
    from mpi4py import MPI
    comm = MPI.COMM_WORLD
    rank = comm.Get_rank()
    size = comm.Get_size()
    print(f"✓ MPI rank {rank} of {size}")
except ImportError as e:
    print(f"✗ mpi4py import failed: {e}")
except Exception as e:
    print(f"✗ MPI initialization failed: {e}")

print("=" * 50)
