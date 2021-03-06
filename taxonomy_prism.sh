#!/bin/bash

function get_opts() {

   PWD0=$PWD
   DRY_RUN=no
   DEBUG=no
   HPC_TYPE=slurm
   FILES=
   OUT_DIR=
   DATA_DIR=
   SAMPLE_RATE=
   MAX_TASKS=50


   help_text="
\n
./taxonomy_prism.sh  [-h] [-n] [-d] [-s SAMPLE_RATE] -D datadir -O outdir [-C local|slurm ] input_file_names\n
\n
\n
example:\n
taxonomy_prism.sh -n -D /dataset/Tash_FL1_Ryegrass/ztmp/For_Alan -O /dataset/Tash_FL1_Ryegrass/ztmp/seq_qc/test/taxonomy  /dataset/Tash_FL1_Ryegrass/ztmp/For_Alan/*.fastq.gz\n
\n
"

   # defaults:
   while getopts ":nhO:C:D:s:m:" opt; do
   case $opt in
       n)
         DRY_RUN=yes
         ;;
       d)
         DEBUG=yes
         ;;
       h)
         echo -e $help_text
         exit 0
         ;;
       O)
         OUT_DIR=$OPTARG
         ;;
       D)
         DATA_DIR=$OPTARG
         ;;
       C)
         HPC_TYPE=$OPTARG
         ;;
       s)
         SAMPLE_RATE=$OPTARG
         ;;
       m)
         MAX_TASKS=$OPTARG
         ;;
       \?)
         echo "Invalid option: -$OPTARG" >&2
         exit 1
         ;;
       :)
         echo "Option -$OPTARG requires an argument." >&2
         exit 1
         ;;
     esac
   done

   shift $((OPTIND-1))

   FILES=$@
}


function check_opts() {
   if [ ! -d $OUT_DIR ]; then
      echo "OUT_DIR $OUT_DIR not found"
      exit 1
   fi
   if [ ! -d $DATA_DIR ]; then
      echo "DATA_DIR $DATA_DIR not found"
      exit 1
   fi

   if [[ $HPC_TYPE != "local" && $HPC_TYPE != "slurm" ]]; then
      echo "HPC_TYPE must be one of local, slurm"
      exit 1
   fi
}

function echo_opts() {
  echo DATA_DIR=$DATA_DIR
  echo OUT_DIR=$OUT_DIR
  echo DRY_RUN=$DRY_RUN
  echo DEBUG=$DEBUG
  echo HPC_TYPE=$HPC_TYPE
  echo FILES=$FILES
  echo SAMPLE_RATE=$SAMPLE_RATE
}

#
# edit this method to set required environment (or set up
# before running this script)
#
function configure_env() {
   cd $SEQ_PRISMS_BIN
   cp ./taxonomy_prism.sh $OUT_DIR
   cp ./taxonomy_prism.mk $OUT_DIR
   cp ./taxonomy_prism.py $OUT_DIR
   cp ./data_prism.py $OUT_DIR  # temporary measure - data_prism will be packaged and installed in system 
   cp ./taxonomy_prism.r $OUT_DIR
   echo "
[tardish]
[tardis_engine]
max_tasks=$MAX_TASKS
" > $OUT_DIR/.tardishrc
   cd $OUT_DIR
}


function check_env() {
   if [ -z "$SEQ_PRISMS_BIN" ]; then
      echo "SEQ_PRISMS_BIN not set - exiting"
      exit 1
   fi
}

function get_targets() {
   TARGETS=""
   for file in $FILES; do
      base=`basename $file`
      TARGETS="$TARGETS $OUT_DIR/${base}.taxonomy_prism"
   done 
}


function fake_prism() {
   echo "dry run ! "
   make -n -f taxonomy_prism.mk -d -k  --no-builtin-rules -j 16 hpc_type=$HPC_TYPE sample_rate=$SAMPLE_RATE data_dir=$DATA_DIR out_dir=$OUT_DIR  $TARGETS > $OUT_DIR/taxonomy_prism.log 2>&1
   echo "dry run : summary commands are 
   tardis.py -q -hpctype $HPC_TYPE -d $OUT_DIR  $OUT_DIR/taxonomy_prism.py --summary_type summary_table --rownames --measure information $OUT_DIR/*.fastq.gz.blastresults.gz.pickle  > $OUT_DIR/information_table.txt
   tardis.py -q -hpctype $HPC_TYPE -d $OUT_DIR  /dataset/bioinformatics_dev/active/R3.3/R-3.3.0/bin/Rscript --vanilla  $OUT_DIR/taxonomy_prism.r analysis_name=\"Taxonomy Summary (100 most variable taxa)\" summary_table_file=$OUT_DIR/information_table.txt output_base=\"taxonomy_summary\" 1\>${OUT_DIR}/plots.stdout 2\>${OUT_DIR}/plots.stderr
   "
   exit 0
}

function run_prism() {
   make -f taxonomy_prism.mk -d -k  --no-builtin-rules -j 16 hpc_type=$HPC_TYPE sample_rate=$SAMPLE_RATE data_dir=$DATA_DIR out_dir=$OUT_DIR $TARGETS > $OUT_DIR/taxonomy_prism.log 2>&1
   tardis.py -q -hpctype $HPC_TYPE -d $OUT_DIR  $OUT_DIR/taxonomy_prism.py --summary_type summary_table --rownames --measure "information" $OUT_DIR/*.blastresults.*.pickle  > $OUT_DIR/information_table.txt

   # currently the next line will fail, as the libraries Heatplus, RColorBrewer, gplots ansd matrixStats not available to the
   # R instance in the bifo-essential conda env. As a work-around until this is sorted , locate the run1.sh wrapper script and run the plot build manally 
   # on (e.g. ) intrepid, using /dataset/bioinformatics_dev/active/R3.3/R-3.3.0/bin/Rscript  

   echo "need to run : tardis.py -hpctype $HPC_TYPE -d $OUT_DIR  Rscript --vanilla  $OUT_DIR/taxonomy_prism.r analysis_name=\'Taxonomy Summary \(100 most variable taxa\)\' summary_table_file=$OUT_DIR/information_table.txt output_base=\"taxonomy_summary\" 1\>${OUT_DIR}/plots.stdout 2\>${OUT_DIR}/plots.stderr"
}

function html_prism() {
   echo "tba" > $OUT_DIR/taxonomy_prism.html 2>&1
}


function main() {
   get_opts $@
   check_opts
   echo_opts
   check_env
   get_targets
   configure_env
   if [ $DRY_RUN != "no" ]; then
      fake_prism
   else
      run_prism
      if [ $? == 0 ] ; then
         html_prism
      else
         echo "error state from taxonomy run - skipping html page generation"
         exit 1
      fi
   fi
}


set -x
main $@
set +x
