#!/usr/bin/env python3

###################################################################################
# Debug version of individuals_mpi.py
# Fixes issues found in the original script for running outside container
###################################################################################

import os
import sys
import re
import time
import tarfile
import shutil
import gzip

# Try to import MPI libraries, with fallback for debugging
try:
    import pybredala as bd
    import pydecaf as d
    from mpi4py import MPI
    DECAF_AVAILABLE = True
    print("DEBUG: Decaf libraries loaded successfully")
except ImportError as e:
    print(f"DEBUG: Decaf libraries not available: {e}")
    print("DEBUG: Running in fallback mode without Decaf")
    DECAF_AVAILABLE = False
    try:
        from mpi4py import MPI
        print("DEBUG: MPI4Py loaded successfully")
    except ImportError as e:
        print(f"ERROR: MPI4Py not available: {e}")
        sys.exit(1)


def compress(output, input_dir):
    with tarfile.open(output, "w:gz") as file:
        file.add(input_dir, arcname=os.path.basename(input_dir))

def readfile(file):
    """Read file with support for both compressed and uncompressed files"""
    print(f"DEBUG: Reading file: {file}")
    
    if not os.path.exists(file):
        print(f"ERROR: File not found: {file}")
        raise FileNotFoundError(f"File not found: {file}")
    
    try:
        if file.endswith('.gz'):
            with gzip.open(file, 'rt') as f:
                content = f.readlines()
        else:
            with open(file, 'r') as f:
                content = f.readlines()
        
        print(f"DEBUG: Successfully read {len(content)} lines from {file}")
        return content
        
    except Exception as e:
        print(f"ERROR: Failed to read file {file}: {e}")
        raise

def processing(inputfile, columfile, c, counter, stop, total):
    print(f'DEBUG: Starting processing for chromosome: {c}')
    print(f'DEBUG: Parameters - inputfile: {inputfile}, columfile: {columfile}')
    print(f'DEBUG: Range - counter: {counter}, stop: {stop}, total: {total}')
    
    tic = time.perf_counter()

    counter = int(counter)
    ending = min(int(stop), int(total))

    ### step 0 - Read input file
    print(f"DEBUG: Reading input file: {inputfile}")
    try:
        rawdata = readfile(inputfile)
    except Exception as e:
        print(f"ERROR: Failed to read input file: {e}")
        return False

    ### step 1 - Read column file
    print(f"DEBUG: Reading column file: {columfile}")
    try:
        # Check if columfile is absolute path or relative
        if not os.path.isabs(columfile):
            # Try in current directory first
            if os.path.exists(columfile):
                columndata = readfile(columfile)[0].rstrip('\n').split('\t')
            else:
                # Try in same directory as input file
                columfile_alt = os.path.join(os.path.dirname(inputfile), columfile)
                print(f"DEBUG: Trying alternate column file path: {columfile_alt}")
                columndata = readfile(columfile_alt)[0].rstrip('\n').split('\t')
        else:
            columndata = readfile(columfile)[0].rstrip('\n').split('\t')
    except Exception as e:
        print(f"ERROR: Failed to read column file: {e}")
        return False

    print(f"DEBUG: Total number of lines in input: {len(rawdata)}")
    print(f"DEBUG: Processing range {counter} to {ending}")
    print(f"DEBUG: Number of columns: {len(columndata)}")

    # Filter out comment lines and select range
    regex = re.compile('(?!#)')
    try:
        data = list(filter(regex.match, rawdata[counter-1:ending]))  # Adjust for 1-based indexing
        data = [x.rstrip('\n') for x in data]
        print(f"DEBUG: Filtered data has {len(data)} lines")
    except Exception as e:
        print(f"ERROR: Failed to filter data: {e}")
        return False

    chrp_data = {}
    filename_arr = []
    count_arr = []

    start_data = 9  # where the real data starts
    end_data = len(columndata) - start_data
    print(f"DEBUG: Processing {end_data} individuals (columns {start_data} to {len(columndata)-1})")

    # Get MPI info
    try:
        comm = MPI.COMM_WORLD
        rank = comm.Get_rank()
        size = comm.Get_size()
        print(f"DEBUG: MPI rank {rank} of {size}")
    except Exception as e:
        print(f"ERROR: MPI initialization failed: {e}")
        return False

    # Process each individual (column)
    for i in range(0, end_data):
        col = i + start_data
        if col >= len(columndata):
            print(f"WARNING: Column {col} exceeds available columns ({len(columndata)})")
            break
            
        name = columndata[col]
        filename_mpi = "chr{}.{}".format(c, name)
        filename_arr.append(filename_mpi)
        
        print(f"DEBUG: Processing individual {i+1}/{end_data}: {name}")
        tic_iter = time.perf_counter()
        chrp_data[i] = []
        count = 0

        # Process each line of data
        for line_idx, line in enumerate(data):
            try:
                fields = line.split('\t')
                if len(fields) <= col:
                    print(f"WARNING: Line {line_idx} has insufficient columns ({len(fields)} < {col+1})")
                    continue
                    
                first = fields[col]  # Individual genotype
                
                # Extract key fields (positions 1,2,3,4,7)
                if len(fields) < 8:
                    print(f"WARNING: Line {line_idx} has insufficient basic fields ({len(fields)})")
                    continue
                    
                second = [fields[i] for i in [1, 2, 3, 4, 7]]
                
                # Parse AF value from INFO field
                try:
                    info_field = second[4]  # INFO field
                    af_parts = info_field.split(';')
                    af_value = None
                    
                    # Look for AF= in INFO field
                    for part in af_parts:
                        if part.startswith('AF='):
                            af_value = part.split('=')[1]
                            break
                    
                    if af_value is None:
                        # Fallback: try 8th semicolon-separated field as in original
                        if len(af_parts) > 8:
                            af_value = af_parts[8].split('=')[1] if '=' in af_parts[8] else af_parts[8]
                        else:
                            continue  # Skip if no AF value found
                    
                    # Handle multiple AF values (comma-separated)
                    if ',' in af_value:
                        af_value = float(af_value.split(',')[0])
                    else:
                        af_value = float(af_value)
                    
                    # Replace INFO field with AF value
                    second[4] = str(af_value)
                    
                    # Apply filtering logic
                    elem = first.split('|')
                    if af_value >= 0.5 and elem[0] == '0':
                        chrp_data[i].append(second)
                        count += 1
                    elif af_value < 0.5 and elem[0] == '1':
                        chrp_data[i].append(second)
                        count += 1
                        
                except (ValueError, IndexError) as e:
                    # Skip lines with parsing errors
                    continue
                    
            except Exception as e:
                print(f"WARNING: Error processing line {line_idx}: {e}")
                continue

        count_arr.append(count)
        print(f"DEBUG: Individual {name} processed {count} variants in {time.perf_counter()-tic_iter:.2f}s")

    # Send data via MPI
    print("DEBUG: Sending data via MPI...")
    try:
        send_dest = size - 1  # Send to last rank (merge process)
        
        comm.send(filename_arr, dest=send_dest, tag=12)
        comm.send(count_arr, dest=send_dest, tag=7)
        comm.send(chrp_data, dest=send_dest, tag=13)
        
        print(f"DEBUG: Data sent to rank {send_dest}")
        
    except Exception as e:
        print(f"ERROR: MPI send failed: {e}")
        return False

    total_time = time.perf_counter() - tic
    print(f"DEBUG: Chromosome {c} processed in {total_time:.2f} seconds")
    return True


if __name__ == "__main__":
    print("="*60)
    print("DEBUG: Starting individuals_mpi.py")
    print(f"DEBUG: Host = {os.uname()[1]}")
    print(f"DEBUG: Python version = {sys.version}")
    print(f"DEBUG: Working directory = {os.getcwd()}")
    
    # Print command line arguments
    print(f"DEBUG: Command line arguments:")
    for i, arg in enumerate(sys.argv):
        print(f"  argv[{i}] = {arg}")
    
    if len(sys.argv) != 6:
        print("ERROR: Wrong number of arguments")
        print("Usage: individuals_mpi.py <inputfile> <columfile> <chromosome> <start> <end> <total>")
        print("  Note: This script expects columfile as argv[2], not hardcoded")
        sys.exit(1)
    
    start_time = time.time()
    
    # Parse arguments (corrected order)
    inputfile = sys.argv[1]
    columfile = sys.argv[2]  # Now taken from command line
    c = sys.argv[3]
    counter = sys.argv[4]
    stop = sys.argv[5]
    
    # For total, we'll try to determine it from the file if needed
    try:
        total = int(sys.argv[5])  # Use stop as total for now
    except:
        total = 250000  # Default fallback

    print(f"DEBUG: Parsed arguments:")
    print(f"  inputfile = {inputfile}")
    print(f"  columfile = {columfile}")
    print(f"  chromosome = {c}")
    print(f"  counter = {counter}")
    print(f"  stop = {stop}")
    print(f"  total = {total}")

    # Initialize MPI
    try:
        comm = MPI.COMM_WORLD
        rank = comm.Get_rank()
        size = comm.Get_size()
        print(f"DEBUG: MPI initialized - rank {rank} of {size}")
    except Exception as e:
        print(f"ERROR: MPI initialization failed: {e}")
        sys.exit(1)

    # Initialize Decaf if available
    if DECAF_AVAILABLE:
        try:
            w = d.Workflow()
            w.makeWflow(w, "1Kgenome.json")
            
            a = MPI._addressof(MPI.COMM_WORLD)
            decaf = d.Decaf(a, w)
            print("DEBUG: Decaf initialized successfully")
        except Exception as e:
            print(f"WARNING: Decaf initialization failed: {e}")
            print("DEBUG: Continuing without Decaf")
            DECAF_AVAILABLE = False

    # Run main processing
    try:
        success = processing(inputfile=inputfile, 
                           columfile=columfile, 
                           c=c, 
                           counter=counter, 
                           stop=stop,
                           total=total)
        
        if success:
            print(f"DEBUG: individuals at rank {rank} completed successfully")
        else:
            print(f"ERROR: individuals at rank {rank} failed")
            sys.exit(1)
            
    except Exception as e:
        print(f"ERROR: Processing failed: {e}")
        import traceback
        traceback.print_exc()
        sys.exit(1)

    # Cleanup
    if DECAF_AVAILABLE:
        try:
            decaf.terminate()
            print("DEBUG: Decaf terminated")
        except:
            pass

    total_time = time.time() - start_time
    print(f'DEBUG: Execution time in seconds: {total_time}')
    print("DEBUG: individuals_mpi.py completed")
    print("="*60)
