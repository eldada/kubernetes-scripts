#!/bin/bash

# UNCOMMENT this line to enable debugging
# set -xv

## Get formatted results of kubectl top pod --containers

OUT=top-$(date +"%Y-%m-%d_%H:%M:%S").csv
NAMESPACE=--all-namespaces
QUITE=false
HEADERS=true
SCRIPT_NAME=$0
DURATION=0
INTERVAL=5
POD=
CONTAINERS=

######### Functions #########

errorExit () {
    echo -e "\nERROR: $1\n"
    exit 1
}

usage () {
    cat << END_USAGE

${SCRIPT_NAME} - Get formatted results of kubectl top pod in a Kubernetes cluster for a selected namespace and pod in a CSV format

Usage: ${SCRIPT_NAME} <options>

-n | --namespace <name>                : Namespace to analyse.      Default: default
-p | --pod <name>                      : Pod to analyse.
-d | --duration <seconds>              : Duration of sampling.      Default: ${DURATION} (infinite)
-i | --interval <seconds>              : Interval between samples.  Default: ${INTERVAL}
-o | --output <name>                   : Output file.               Default: top-<timestamp>.csv
-c | --containers                      : Output per container.      Default: off
-q | --quite                           : Don't output to screen.    Default: Output to screen
-h | --help                            : Show this usage
--no-headers                           : Don't print headers line

Examples:
========
Get for pod foo in namespace bar:                                $ ${SCRIPT_NAME} --namespace bar --pod foo
Get for pod foo in namespace bar and output to file foo.csv :    $ ${SCRIPT_NAME} --namespace bar --pod foo --output foo.csv

END_USAGE

    exit 1
}

# Process command line options. See usage above for supported options
processOptions () {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -n | --namespace)
                NAMESPACE="--namespace $2"
                shift 2
            ;;
            -p | --pod)
                POD="$2"
                shift 2
            ;;
            -d | --duration)
                DURATION="$2"
                shift 2
            ;;
            -i | --interval)
                INTERVAL="$2"
                shift 2
            ;;
            -o | --output)
                OUT=$2
                shift 2
            ;;
            -c | --containers)
                CONTAINERS="--containers"
                shift 1
            ;;
            -q | --quite)
                QUITE=true
                shift 1
            ;;
            --no-headers)
                HEADERS=false
                shift 1
            ;;
            -h | --help)
                usage
                exit 0
            ;;
            *)
                usage
            ;;
        esac
    done

    [ -z "${POD}" ] && errorExit "Must provide pod name (--pod <POD>)"
}

# Test connection to a cluster by kubectl
testConnection () {
    kubectl cluster-info > /dev/null || errorExit "Connection to cluster failed"
    kubectl get pod ${NAMESPACE} "${POD}" > /dev/null || errorExit "Pod ${POD} not found in namespace ${NAMESPACE}"
}

formatCpu () {
    local result=$1
    if [[ ${result} =~ m$ ]]; then
        result=$(echo "${result}" | tr -d 'm')
        result=$(awk "BEGIN {print ${result}/1000}")
    fi

    echo -n "${result}"
}

formatMemory () {
    local result=$1
    if [[ ${result} =~ M ]]; then
        result=$(echo "${result}" | tr -d 'Mi')
        result=$(awk "BEGIN {print ${result}/1000}")
    elif [[ ${result} =~ m ]]; then
        result=$(echo "${result}" | tr -d 'm')
        result=$(awk "BEGIN {print ${result}/1000000000000}")
    elif [[ ${result} =~ G ]]; then
        result=$(echo "${result}" | tr -d 'Gi')
    fi

    echo -n "${result}"
}

getPodsTop () {
    local condition=true
    local counter=0
    local line=
    local time_stamp=
    local cpu=
    local memory=

    if [ "${DURATION}" != 0 ]; then
        condition="[]"
    fi

    while ${condition}; do
        line=$(kubectl top pod ${NAMESPACE} "${POD}" --no-headers ${CONTAINERS} --use-protocol-buffers)
#        echo "--- $line"
        local final_line=

        # Go over all the containers
        local OLD_IFS=${IFS}
        IFS=$'\n'
        for l in ${line}; do
            local container=""
            local header="Timestamp,Pod,CPU (cores),Memory (GB)"
            time_stamp=$(date +"%Y-%m-%d_%H:%M:%S")
            if [ -n "${CONTAINERS}" ]; then
                container=$(echo "${l}" | awk '{print $2}')
                cpu=$(formatCpu "$(echo "${l}" | awk '{print $3}')")
                memory=$(formatMemory "$(echo "${l}" | awk '{print $4}')")
                header="Timestamp,Pod,Container,CPU (cores),Memory (GB)"
            else
                cpu=$(formatCpu "$(echo "${l}" | awk '{print $2}')")
                memory=$(formatMemory "$(echo "${l}" | awk '{print $3}')")
            fi
            local out_file=${OUT}

            # Print header in each file if this is the first line
            if [ ${counter} -eq 0 ]; then
                if [ "${HEADERS}" == true ]; then
                    echo "${header}" > "${out_file}"
                else
                    echo -n "" > "${out_file}"
                fi
            fi

            final_line=${time_stamp},${POD},${cpu},${memory}
            if [ -n "${CONTAINERS}" ]; then
                final_line=${time_stamp},${POD},${container},${cpu},${memory}
            fi

            if [ "${QUITE}" == true ]; then
                echo "${final_line}" >> "${out_file}"
            else
                echo "${final_line}" | tee -a "${out_file}"
            fi
        done
        IFS=${OLD_IFS}

        sleep "${INTERVAL}"

        (( counter++ ))
    done
}

main () {
    processOptions "$@"
    [ "${QUITE}" == true ] || echo "Getting Pod memory and cpu usage"
    testConnection
    getPodsTop
}

######### Main #########

main "$@"
