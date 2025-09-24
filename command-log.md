The point I was at was to run this:

`mpirun -np 16 --hostfile hostfile bash -c 'export SPACK_ROOT="/home/kbateman/spack"; export PATH="/home/kbateman/spack/bin:$PATH"; source /
home/kbateman/spack/share/spack/setup-env.sh;
 spack load py-mpi4py python@3.11.7; python3 bin/individuals_mpi_proper.py /home/kbateman/1000genome-mpi-main/data/20130502/ALL.chr1.250000.vcf.gz 1 1 1000 250000'`

Hostfile should look like this:
`
ares-comp-01
ares-comp-02
...
`

Full workflow will use "250000" instead of "1000" for argument 3.

Also, This has to be integrated into the run_workflow_mpi.sh command for the full workflow, that's not done yet. And there may be problems with other phases that arise as you continue to run it.

For my Spack installation, I did:
`
spack load iowarp
spack load py-mpi4py
`

You might have to create an environment for this, I know I did. I believe the instructions in README_MPI.md are correct, but you can run some of the several tests to clarify, such as test_spack_multinode_fixed.py to test your multinode spack environment, test_mpi_environment.sh to test the MPI environment, etc.
