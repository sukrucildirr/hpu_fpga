#! /usr/bin/bash
# BSD 3-Clause Clear License
# Copyright © 2025 ZAMA. All rights reserved.
#
# aliases are not expanded when the shell is not interactive.
# Redefine here for more clarity

run_edalize=${PROJECT_DIR}/hw/scripts/edalize/run_edalize.py

RED='\033[1;31m'
GREEN='\033[1;32m'
NC='\033[0m'

module="tb_ram_wrapper_2RW"
###################################################################################################
# Usage
###################################################################################################
function usage () {
echo "Usage : run_simu.sh runs all the simulations for ${module}."
echo "./run_simu.sh [options]"
echo "Options are:"
echo "-h                       : print this help."
echo "-- <run_edalize options> : run_edalize options."
}


###################################################################################################
# input arguments
###################################################################################################

# A POSIX variable
OPTIND=1         # Reset in case getopts has been used previously in the shell.

# Initialize your own variables here:
while getopts "h" opt; do
  case "$opt" in
    h)
      usage
      exit 0
      ;;
  esac
done

shift $((OPTIND-1))

[ "${1:-}" = "--" ] && shift
args=$@


###################################################################################################
# Run simulation
###################################################################################################
# Write simulation command lines here
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)
mkdir -p ${PROJECT_DIR}/hw/output
SEED_FILE="${PROJECT_DIR}/hw/output/${module}.seed"
TMP_FILE="${PROJECT_DIR}/hw/output/${RANDOM}${RANDOM}._tmp"
echo -n "" > $SEED_FILE
echo -n "" > $TMP_FILE

#RAM_LATENCY_L=(1 2 3)
#RD_WR_ACCESS_TYPE_L=(0 1 2)
#KEEP_RD_DATA_L=(0 1)
for i in `seq 1 10`; do
    RAM_LATENCY=$((1+$RANDOM % 3))
    RD_WR_ACCESS_TYPE=$(($RANDOM % 3))
    KEEP_RD_DATA=$(($RANDOM % 2))

    cmd="$run_edalize -m ${module} -t $PROJECT_SIMU_TOOL  -P RAM_LATENCY int $RAM_LATENCY \
                                            -P RD_WR_ACCESS_TYPE int $RD_WR_ACCESS_TYPE \
                                            -P KEEP_RD_DATA int $KEEP_RD_DATA $args"
    echo "==========================================================="
    echo "INFO> Running : $cmd"
    echo "==========================================================="
    $cmd | tee >(grep "Seed" | head -1 >> $SEED_FILE) |  grep -c "> SUCCEED !" > $TMP_FILE
    exit_status=$?
    # In case of post processing, presence of several SUCCEED is necessary to be a real success
    succeed_cnt=$(cat $TMP_FILE)
    if [ $exit_status -gt 0 ] || [ $succeed_cnt -ne 1 ] ; then
        echo -e "${RED}FAILURE>${NC} $cmd" 1>&2
        rm -f $TMP_FILE
        exit $exit_status
    else
        echo -e "${GREEN}SUCCEED>${NC} $cmd" 1>&2
    fi
done

rm -f $TMP_FILE
