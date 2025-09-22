#!/usr/bin/env python3

"""
Fixed version of individuals_mpi.py that handles common issues:
1. Compressed input files (.gz)
2. Absolute path handling for columns.txt
3. Better error handling and debugging
4. Graceful fallback when Decaf libraries are not available
"""

import os
import sys
import re
import time
import gzip

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


def processing(inputfile, columfile, c, counter, stop, total):
    print('= Now processing chromosome: {}'.format(c))
    tic = time.perf_counter()

    counter = int(counter)
    ending = min(int(stop), int(total))

    # Read input file (handle compressed files)
    try:
        rawdata = readfile(inputfile)
        print(f"Read {len(rawdata)} lines from {inputfile}")
    except Exception as e:
        print(f"ERROR: Failed to read input file {inputfile}: {e}")
        return False

    # Read columns file
    try:
        columndata = readfile(columfile)[0].rstrip('\n').split('\t')
        print(f"Read {len(columndata)} columns from {columfile}")
    except Exception as e:
        print(f"ERROR: Failed to read columns file {columfile}: {e}")
        return False

    print("== Total number of lines: {}".format(total))
    print("== Processing from line {} to {}".format(counter, stop))

    # Filter data - handle 1-based indexing from command line
    regex = re.compile('(?!#)')
    try:
        # Adjust for 1-based indexing from command line
        start_idx = max(0, counter - 1)
        end_idx = min(ending, len(rawdata))
        
        data = list(filter(regex.match, rawdata[start_idx:end_idx]))
        data = [x.rstrip('\n') for x in data]
        print(f"Filtered to {len(data)} non-comment lines")
    except Exception as e:
        print(f"ERROR: Failed to filter data: {e}")
        return False

    chrp_data = {}
    filename_arr = []
    count_arr = []

    start_data = 9  # where the real data starts
    end_data = len(columndata) - start_data
    print("== Number of individuals: {}".format(end_data))

    comm = MPI.COMM_WORLD
    size = comm.Get_size()

    for i in range(0, end_data):
        col = i + start_data
        if col >= len(columndata):
            print(f"WARNING: Column index {col} exceeds available columns")
            break
            
        name = columndata[col]
        filename_mpi = "chr{}.{}".format(c, name)
        filename_arr.append(filename_mpi)
        print("=== Processing individual {} ({})".format(i+1, name), end=" => ")
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
        print("processed {} variants in {:0.2f} sec".format(count, time.perf_counter()-tic_iter))

    # Send data via MPI
    tic_comm = time.perf_counter()
    send_dest = size - 1  # Send to merge process (last rank)
    
    try:
        comm.send(filename_arr, dest=send_dest, tag=12)
        comm.send(count_arr, dest=send_dest, tag=7)
        comm.send(chrp_data, dest=send_dest, tag=13)
        print(f"Data sent to merge process (rank {send_dest})")
    except Exception as e:
        print(f"ERROR: MPI send failed: {e}")
        return False

    total_time = time.perf_counter() - tic
    comm_time = time.perf_counter() - tic_comm
    print("= Chromosome {} processed in {:0.2f} seconds (MPI send: {:0.2f}s)".format(c, total_time, comm_time))
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

    # Process data
    try:
        success = processing(inputfile=inputfile, 
                           columfile=columfile, 
                           c=c, 
                           counter=counter, 
                           stop=stop,
                           total=total)
        
        if not success:
            print(f"ERROR: Processing failed at rank {rank}")
            sys.exit(1)
            
    except Exception as e:
        print(f"ERROR: Processing exception: {e}")
        import traceback
        traceback.print_exc()
        sys.exit(1)

    # Cleanup
    if DECAF_AVAILABLE:
        try:
            decaf.terminate()
        except Exception:
            pass

    print("individuals at rank {} terminating".format(rank))
    print('Execution time in seconds: {}'.format(time.time() - start_time))
