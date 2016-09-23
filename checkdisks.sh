#!/bin/bash

declare -r PROG_NAME=$0

print_help()
{
  echo  "Usage: $PROG_NAME [OPTIONS]"
  echo  "OPTIONS:"
  echo  " -h          Display this help message"
  echo  " -n          Don't colorize output"
  echo  " -s <field>  Sort by \"field\", one of"
  echo  "               dev, port, model, serial,"
  echo  "               size, age, bad, status."
}

UDISKS=`which udisks`
if [ -z "$UDISKS" ]; then
  echo $0 requires \"udisks\". Please install it first.
  exit 1
fi

USE_COLOR=1
USE_SORT=""

OPTIND=1
while getopts "hns:" opt; do
  case $opt in
    n)
      USE_COLOR=0
      ;;
    s)
      USE_SORT=$OPTARG
      ;;
    h|*)
      print_help
      exit 3
      ;;
  esac
done

declare -r NA="-N/A-"

if test $USE_COLOR -eq 0; then
  declare -r CL_N=""
  declare -r CL_RED=""
  declare -r CL_GRN=""
  declare -r CL_YLW=""
  declare -r CL_BLU=""
  declare -r CL_MAG=""
  declare -r CL_CYN=""

  declare -r CL_BOLD=""
else
  declare -r CL_N="\x1B[0m"
  declare -r CL_RED="\x1B[31m"
  declare -r CL_GRN="\x1B[32m"
  declare -r CL_YLW="\x1B[33m"
  declare -r CL_BLU="\x1B[34m"
  declare -r CL_MAG="\x1B[35m"
  declare -r CL_CYN="\x1B[36m"

  declare -r CL_BOLD="\x1B[1m"
fi

HEADING=()
SORT_PARAM=()
GREP_PAT=()
SED_PAT=()
DATA_MOD=()
JUSTIFY=()
COLORIZE=()
MAX_LEN=()

DATA=()
DATA_COL=()

colorize_assessment()
{
  if test "$1" = "Good"; then
    echo "$CL_GRN"
  elif test "$1" = "$NA"; then
    echo ""
  else
    printf "$CL_RED"
  fi
}

colorize_bad_sect()
{
  if test $1 -gt 0; then
    echo "$CL_RED"
  else
    echo ""
  fi
}

colorize_temp()
{
  N=$(echo "$1" | sed -e 's/\([0-9]\+\).*/\1/')
  if test $N -ge 120; then
    echo "$CL_RED"
  elif test $N -ge 110; then
    echo "$CL_YLW"
  else
    echo "$CL_GRN"
  fi
}

prettify_bytes()
{
  local -r UNITS=("" "K" "M" "G" "T" "P" "E")
  OUT=$1
  I=0

  while test $OUT -ge 1000; do
    ((OUT /= 1000))
    ((I++))
  done

  echo -n "${OUT}${UNITS[$I]}B"
}

prettify_age()
{
  local -r UNITS=("h" "d" "w" "y")
  local -r   DIV=(24  7   52  1000)
  AGE=`echo "$1" | cut -d' ' -f1 | sed -e 's/\([0-9]\)\..*/\1/'`
  UNIT=`echo "$1" | cut -d' ' -f2`
  I=0

  if test "$UNIT" = "hours" -o -z "$UNIT"; then
    I=0
  elif test "$UNIT" = "days"; then
    I=1
  else
    return
  fi

  SUB=0
  while test $I -lt ${#UNITS[@]}; do
    if test ${AGE} -gt ${DIV[$I]}; then
      SUB=$((AGE % DIV[$I]))
      AGE=$((AGE / DIV[$I]))
    else
      break
    fi
    ((I++))
  done

  if test $I -eq ${#UNITS[@]}; then
    echo -n "${AGE}${UNITS[((I - 1))]}"
  elif test $I -eq 0; then
    echo -n "${AGE}${UNITS[$I]}"
  else
    printf "%2d%s %2d%s" ${AGE} "${UNITS[$I]}" ${SUB} "${UNITS[((I - 1))]}"
  fi
}

prettify_temp()
{
  NUM=$(echo $1 | sed -e 's/[^0-9.]*\([0-9.]\+\).*/\1/')
  printf "%.1lfF" $NUM
}

F=-1
HEADING[((++F))]="Device"
SORT_PARAM[$F]="dev"
SORT_FLAG[$F]=""

HEADING[((++F))]="Port"
SORT_PARAM[$F]="port"
SORT_FLAG[$F]="-k1.1,1.3 -k1.4n"

HEADING[((++F))]="Model #"
SORT_PARAM[$F]="model"
SORT_FLAG[$F]="-g"
GREP_PAT[$F]="model:\s+"
SED_PAT[$F]='s/^\s*model:\s\+\([^\s]\+\)/\1/'
JUSTIFY[$F]="-"

HEADING[((++F))]="Serial #"
SORT_FLAG[$F]="-g"
SORT_PARAM[$F]="serial"
GREP_PAT[$F]="serial:"
SED_PAT[$F]='s/^\s*serial:\s\+\([^\s]\+\)/\1/'
JUSTIFY[$F]="-"

HEADING[((++F))]="Size"
SORT_FLAG[$F]="-n"
SORT_PARAM[$F]="size"
GREP_PAT[$F]="size:\s+"
SED_PAT[$F]='s/^\s*size:\s*\([0-9]\+\)$/\1/'
JUSTIFY[$F]=""
DATA_MOD[$F]=prettify_bytes

HEADING[((++F))]="Age"
SORT_FLAG[$F]="-h"
SORT_PARAM[$F]="age"
GREP_PAT[$F]="power-on-hours"
SED_PAT[$F]='s/^\s*power-on-hours.*\s\+\([0-9.]\+\s\(hours\|days\)\?\).*/\1/'
JUSTIFY[$F]=""
DATA_MOD[$F]=prettify_age

HEADING[((++F))]="Temp."
SORT_FLAG[$F]="-h"
SORT_PARAM[$F]="temp"
GREP_PAT[$F]="temperature-celsius"
SED_PAT[$F]='s/.*\/\s\?\([0-9]\+\(\.[0-9]\+\)\?F\).*/\1/'
JUSTIFY[$F]=""
COLORIZE[$F]=colorize_temp
DATA_MOD[$F]=prettify_temp

HEADING[((++F))]="Bad Sect."
SORT_FLAG[$F]="-n"
SORT_PARAM[$F]="bad"
GREP_PAT[$F]="current-pending-sector|reported-uncorrect"
SED_PAT[$F]='s/.*\s\([0-9]\+\)\ssectors.*/\1/'
JUSTIFY[$F]="-"
COLORIZE[$F]=colorize_bad_sect

HEADING[((++F))]="Status"
SORT_FLAG[$F]=""
SORT_PARAM[$F]="status"
GREP_PAT[$F]="overall assessment"
SED_PAT[$F]='s/^\s*overall assessment:\s\+\([^\s]\+\)/\1/'
JUSTIFY[$F]="-"
COLORIZE[$F]=colorize_assessment

ASSESS_OFF=$F
N_FIELDS=${#HEADING[@]}
LEN_NA=${#NA}

SORT_FIELD=0
SORT_FLAGS=""
if ! test -z "$USE_SORT"; then
  for I in $(seq 0 $((N_FIELDS -1))); do
    if test "$USE_SORT" = "${SORT_PARAM[$I]}"; then
      SORT_FIELD=$I
      SORT_FLAGS="${SORT_FLAG[$I]}"
      break
    fi
  done
fi

for I in $(seq 0 $((N_FIELDS - 1))); do
  MAX_LEN[$I]=${#HEADING[$I]}
  if test $LEN_NA -gt ${MAX_LEN[$I]}; then
    MAX_LEN[$I]=$LEN_NA
  fi
done

DEVS="$(ls -1 /dev/sd?)"
N_DEVS=$(echo "$DEVS" | wc -l)

for I in $(seq 0 $((N_DEVS * N_FIELDS))); do
  DATA[$I]="$NA"
done

P=0
PORTS[((P++))]="/sys/devices/pci*/*/ata*/host*/target*/*/block*/"
PORTS[((P++))]="/sys/devices/pci*/*/*/ata*/host*/target*/*/block*/"
PORTS[((P++))]="/sys/devices/pci*/*/usb*/*/*/host*/target*/*/block*/"
PORTS[((P++))]="/sys/devices/pci*/*/usb*/[0-9]*/*/*/host*/target*/*/block*/"
declare -r N_PORTS=${#PORTS[@]}

I=0
while read DEV; do
  I_P=$((I * N_FIELDS))
  DEV=`basename ${DEV}`
  F_OFF=0

  printf " Collecting information for %d devices: %d%%\r" $N_DEVS $((I * 100 / N_DEVS))
  
  DATA[$((I_P+F_OFF))]=$DEV
  if test ${#DATA[$((I_P+F_OFF))]} -gt ${MAX_LEN[$F_OFF]}; then
    MAX_LEN[$F_OFF]=${#DATA[$((I_P+F_OFF))]}
  fi
  ((F_OFF++))

  for P in `seq 0 $N_PORTS`; do
    PORT_PATH=`ls -d ${PORTS[$P]}/${DEV} 2> /dev/null`
    PORT=`echo "$PORT_PATH" | sed -e 's:.*/\(\(usb\|ata\)[0-9]\+\)/.*target[0-9]\+\:[0-9]\+\:\([0-9]\+\).*:\1.\3:'`
    if test -n "${PORT}"; then
      DATA[$((I_P+F_OFF))]=$PORT
      if test ${#DATA[$((I_P+F_OFF))]} -gt ${MAX_LEN[$F_OFF]}; then
        MAX_LEN[$F_OFF]=${#DATA[$((I_P+F_OFF))]}
      fi
      break;
    fi
  done
  ((F_OFF++))

  LINES="$(udisks --show-info /dev/${DEV})"
  while read LINE; do
    for F in $(seq ${F_OFF} $((N_FIELDS - 1))); do
      OFF=$((I_P + F))
      if test "${DATA[(($OFF))]}" = "${NA}"; then
        if echo $LINE | grep -E "${GREP_PAT[$F]}" &> /dev/null; then
          DATUM=`echo $LINE | sed -e "${SED_PAT[$F]}"`
          if test $? = 0; then
            if ! [ -z "${COLORIZE[$F]}" ]; then
              DATA_COL[$OFF]=`${COLORIZE[$F]} "${DATUM}"`
            fi
            if ! [ -z "$DATUM" ]; then
              DATA[$OFF]="$DATUM"
            fi
          fi
          break
        fi
      fi
    done
  done <<< "$LINES"
  ((I++))
done <<< "$DEVS"

NDEVS=$I

SORT_ORDER=()
J=0
while read LINE; do
  SORT_ORDER[((J++))]=`echo $LINE | sed -e 's/.* \([0-9]\+\)$/\1/g'`
done <<< "$(for I in $(seq 0 $((N_DEVS - 1))); do echo "${DATA[((I * N_FIELDS + SORT_FIELD))]} $I"; done | sort $SORT_FLAGS)"

for I in $(seq 0 $((NDEVS - 1))); do
  I_P=$((I * N_FIELDS))

  for F in $(seq 0 $((N_FIELDS - 1))); do
    OFF=$((I_P + F))
    DATUM="${DATA[$OFF]}"
    if test "$DATUM" != "${NA}"; then
      if ! [ -z "${DATA_MOD[$F]}" ]; then
        DATUM=`${DATA_MOD[$F]} "${DATUM}"`
      fi
    fi
    if test ${#DATUM} -gt ${MAX_LEN[$F]}; then
      MAX_LEN[$F]=${#DATUM}
    fi
    DATA[$OFF]="$DATUM"
  done
done

for I in $(seq 0 $((N_FIELDS - 1))); do
  printf "${CL_BOLD}%-*.*s  ${CL_N}" "${MAX_LEN[$I]}" "${MAX_LEN[$I]}" "${HEADING[$I]}"
done

for I in ${SORT_ORDER[*]}; do
  echo
  I_P=$((I * N_FIELDS))

  BAD=0
  ASSESS="${DATA[((I_P + ASSESS_OFF))]}"
  if test "${ASSESS}" != "Good" -a "${ASSESS}" != "${NA}"; then
    BAD=1
  fi

  for F in $(seq 0 $((N_FIELDS - 1))); do
    COL="${DATA_COL[((I_P + F))]}"
    if test $BAD = 1; then
      #if test "x${COL}" = "x"; then
      #  COL="$CL_RED"
      #fi
      COL="${CL_BOLD}${COL}"
    fi
      
    printf "${COL}%${JUSTIFY[$F]}*.*s  ${CL_N}" "${MAX_LEN[$F]}" "${MAX_LEN[$F]}" "${DATA[((I_P + F))]}"
  done
done

printf "${CL_N}\n"

