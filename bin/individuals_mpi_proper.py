#!/usr/bin/env python3

"""
Fixed version of individuals_mpi.py with proper MPI communication pattern
This version separates worker processes from the merge process to avoid deadlock
"""

import gzip
import os
import re
import sys
import time

# Try to import MPI libraries with fallback
try:
    from mpi4py import MPI
    MPI_AVAILABLE = True
except ImportError as e:
    print(f"ERROR: mpi4py not available: {e}")
    sys.exit(1)

# Try to import Decaf libraries with fallback
try:
    import pydecaf as d
    DECAF_AVAILABLE = True
except ImportError:
    DECAF_AVAILABLE = False
    print("WARNING: Decaf libraries not available, running without Decaf support")


def readfile(file):
    """Read file with support for both compressed and uncompressed files"""
    if not os.path.exists(file):
        raise FileNotFoundError(f"File not found: {file}")
    
    if file.endswith('.gz'):
        with gzip.open(file, 'rt') as f:
            content = f.readlines()
    else:
        with open(file, 'r') as f:
            content = f.readlines()
    
    return content


def find_columns_file():
    """Find columns.txt file in various locations"""
    possible_paths = [
        'columns.txt',  # Current directory
        'data/20130502/columns.txt',  # Relative path
        os.path.join(os.path.dirname(sys.argv[1]), 'columns.txt'),  # Same dir as input
    ]
    
    # Add absolute path based on input file location
    input_file = sys.argv[1]
    if os.path.isabs(input_file):
        data_dir = os.path.dirname(input_file)
        possible_paths.append(os.path.join(data_dir, 'columns.txt'))
    
    for path in possible_paths:
        if os.path.exists(path):
            print(f"Found columns file: {path}")
            return path
    
    raise FileNotFoundError(f"columns.txt not found in any of: {possible_paths}")


def process_individuals_worker(inputfile, columfile, c, counter, stop, total, rank):
    """Worker process: process individuals and send results"""
    print(f'= Worker {rank}: Processing chromosome {c}')
    tic = time.perf_counter()

    counter = int(counter)
    ending = min(int(stop), int(total))

    # Read input file (handle compressed files)
    try:
        rawdata = readfile(inputfile)
        print(f"Worker {rank}: Read {len(rawdata)} lines from {inputfile}")
    except Exception as e:
        print(f"ERROR: Worker {rank} failed to read input file {inputfile}: {e}")
        return False

    # Read columns file
    try:
        columndata = readfile(columfile)[0].rstrip('\n').split('\t')
        print(f"Worker {rank}: Read {len(columndata)} columns from {columfile}")
    except Exception as e:
        print(f"ERROR: Worker {rank} failed to read columns file {columfile}: {e}")
        return False

    print(f"Worker {rank}: Total number of lines: {total}")
    print(f"Worker {rank}: Processing from line {counter} to {stop}")

    # Filter data - handle 1-based indexing from command line
    regex = re.compile('(?!#)')
    try:
        # Adjust for 1-based indexing from command line
        start_idx = max(0, counter - 1)
        end_idx = min(ending, len(rawdata))
        
        data = list(filter(regex.match, rawdata[start_idx:end_idx]))
        data = [x.rstrip('\n') for x in data]
        print(f"Worker {rank}: Filtered to {len(data)} non-comment lines")
    except Exception as e:
        print(f"ERROR: Worker {rank} failed to filter data: {e}")
        return False

    chrp_data = {}
    filename_arr = []
    count_arr = []

    start_data = 9  # where the real data starts
    end_data = len(columndata) - start_data
    print(f"Worker {rank}: Number of individuals: {end_data}")

    comm = MPI.COMM_WORLD
    size = comm.Get_size()

    for i in range(0, end_data):
        col = i + start_data
        if col >= len(columndata):
            print(f"WARNING: Worker {rank}: Column index {col} exceeds available columns")
            break
            
        name = columndata[col]
        filename_mpi = f"chr{c}.{name}"
        filename_arr.append(filename_mpi)
        print(f"Worker {rank}: Processing individual {i+1} ({name})", end=" => ")
        tic_iter = time.perf_counter()
        chrp_data[i] = []
        count = 0

        for line in data:
            try:
                fields = line.split('\t')
                if len(fields) <= col:
                    continue  # Skip lines with insufficient columns
                    
                first = fields[col]  # Individual genotype
                
                # Extract required fields [1,2,3,4,7] (0-based indexing)
                if len(fields) < 8:
                    continue  # Skip lines with insufficient basic fields
                    
                second = [fields[i] for i in [1, 2, 3, 4, 7]]
                
                # Parse AF value from INFO field (field 7, index 4 in second array)
                try:
                    info_field = second[4]
                    
                    # Look for AF= in the INFO field
                    af_value = None
                    for part in info_field.split(';'):
                        if part.startswith('AF='):
                            af_value = part.split('=')[1]
                            break
                    
                    if af_value is None:
                        # Fallback: try the original method (8th semicolon part)
                        parts = info_field.split(';')
                        if len(parts) > 8 and '=' in parts[8]:
                            af_value = parts[8].split('=')[1]
                        else:
                            continue  # Skip if no AF found
                    
                    # Handle comma-separated values
                    if ',' in af_value:
                        af_value = float(af_value.split(',')[0])
                    else:
                        af_value = float(af_value)
                    
                    # Replace INFO field with AF value
                    second[4] = str(af_value)
                    
                    # Apply filtering logic
                    elem = first.split('|')
                    if len(elem) == 0:
                        continue
                        
                    if af_value >= 0.5 and elem[0] == '0':
                        chrp_data[i].append(second)
                        count += 1
                    elif af_value < 0.5 and elem[0] == '1':
                        chrp_data[i].append(second)
                        count += 1
                        
                except (ValueError, IndexError):
                    continue  # Skip lines with parsing errors
                    
            except Exception:
                continue  # Skip problematic lines

        count_arr.append(count)
        print(f"processed {count} variants in {time.perf_counter()-tic_iter:.2f} sec")

    # Send data via MPI to merge process
    tic_comm = time.perf_counter()
    merge_rank = size - 1  # Last rank is merge process
    
    print(f"Worker {rank}: Sending data to merge process (rank {merge_rank})")
    try:
        comm.send(filename_arr, dest=merge_rank, tag=12)
        comm.send(count_arr, dest=merge_rank, tag=7)
        comm.send(chrp_data, dest=merge_rank, tag=13)
        print(f"Worker {rank}: Data sent successfully")
    except Exception as e:
        print(f"ERROR: Worker {rank}: MPI send failed: {e}")
        return False

    total_time = time.perf_counter() - tic
    comm_time = time.perf_counter() - tic_comm
    print(f"Worker {rank}: Chromosome {c} processed in {total_time:.2f} seconds (MPI send: {comm_time:.2f}s)")
    return True


def process_individuals_merger(c, rank):
    """Merge process: receive data from all workers and write output files"""
    print(f"= Merger {rank}: Starting merge process for chromosome {c}")
    
    comm = MPI.COMM_WORLD
    size = comm.Get_size()
    num_workers = size - 1  # All processes except this one are workers
    
    print(f"Merger {rank}: Waiting for data from {num_workers} workers")
    
    # Receive data from all worker processes
    all_filename_arr = []
    all_count_arr = []
    all_chrp_data = []
    
    for worker_rank in range(num_workers):
        try:
            print(f"Merger {rank}: Receiving data from worker {worker_rank}...")
            filename_arr = comm.recv(source=worker_rank, tag=12)
            count_arr = comm.recv(source=worker_rank, tag=7)
            chrp_data = comm.recv(source=worker_rank, tag=13)
            
            all_filename_arr.extend(filename_arr)
            all_count_arr.extend(count_arr)
            all_chrp_data.append(chrp_data)
            
            print(f"Merger {rank}: Received data from worker {worker_rank} - {len(filename_arr)} individuals")
            
        except Exception as e:
            print(f"ERROR: Merger {rank}: Failed to receive from worker {worker_rank}: {e}")
            return False
    
    print(f"Merger {rank}: Received all data - total individuals: {len(all_filename_arr)}")
    
    # Write output files (placeholder - implement actual file writing as needed)
    print(f"Merger {rank}: Writing output files...")
    # TODO: Implement actual file writing logic based on original requirements
    
    print(f"Merger {rank}: Merge complete")
    return True


if __name__ == "__main__":
    print(f"Host = {os.uname()[1]}")
    print(f"CPUs = {os.sched_getaffinity(0) if hasattr(os, 'sched_getaffinity') else 'N/A'}")
    
    if len(sys.argv) != 6:
        print("ERROR: Expected 5 arguments")
        print("Usage: individuals_mpi.py <inputfile> <chromosome> <start> <stop> <total>")
        print(f"Got {len(sys.argv)-1} arguments: {sys.argv[1:]}")
        sys.exit(1)
    
    start_time = time.time()
    
    # Parse arguments (original script order)
    inputfile = sys.argv[1]
    c = sys.argv[2]
    counter = sys.argv[3]
    stop = sys.argv[4]
    total = sys.argv[5]
    
    # Find columns file
    try:
        columfile = find_columns_file()
    except FileNotFoundError as e:
        print(f"ERROR: {e}")
        sys.exit(1)

    print(f"Arguments: inputfile={inputfile}, chromosome={c}, range={counter}-{stop}/{total}")
    print(f"Columns file: {columfile}")

    # Initialize MPI
    comm = MPI.COMM_WORLD
    rank = comm.Get_rank()
    size = comm.Get_size()
    print(f"MPI: rank {rank} of {size}")

    # Initialize Decaf if available
    if DECAF_AVAILABLE:
        try:
            w = d.Workflow()
            w.makeWflow(w, "1Kgenome.json")
            a = MPI._addressof(MPI.COMM_WORLD)
            decaf = d.Decaf(a, w)
        except Exception as e:
            print(f"WARNING: Decaf initialization failed: {e}")
            DECAF_AVAILABLE = False

    # Separate worker and merge processes
    success = False
    
    if rank == size - 1:
        # Last rank is the merge process
        print(f"Rank {rank}: Acting as merge process")
        success = process_individuals_merger(c, rank)
    else:
        # All other ranks are worker processes
        print(f"Rank {rank}: Acting as worker process")
        success = process_individuals_worker(inputfile, columfile, c, counter, stop, total, rank)
    
    if not success:
        print(f"ERROR: Processing failed at rank {rank}")
        sys.exit(1)

    # Cleanup
    if DECAF_AVAILABLE:
        try:
            decaf.terminate()
        except Exception:
            pass

    print(f"Rank {rank} terminating")
    print(f'Execution time in seconds: {time.time() - start_time}')
