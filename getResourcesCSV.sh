#!/bin/bash

# UNCOMMENT this line to enable debugging
# set -xv

## Get resources requests and limits per container in a Kubernetes cluster.

OUT=resources.csv
NAMESPACE=--all-namespaces
QUITE=false
HEADERS=true
CONSOLE_ONLY=false
SCRIPT_NAME=$0

######### Functions #########

errorExit () {
    echo -e "\nERROR: $1\n"
    exit 1
}

usage () {
    cat << END_USAGE

${SCRIPT_NAME} - Extract resource requests and limits in a Kubernetes cluster for a selected namespace or all namespaces in a CSV format

Usage: ${SCRIPT_NAME} <options>

-n | --namespace <name>                : Namespace to analyse.    Default: --all-namespaces
-o | --output <name>                   : Output file.             Default: ${OUT}
-q | --quite                           : Don't output to stdout.  Default: Output to stdout
-h | --help                            : Show this usage
--no-headers                           : Don't print headers line
--console-only                         : Output to stdout only (don't write to file)

Examples:
========
Get all:                                                  $ ${SCRIPT_NAME}
Get for namespace foo:                                    $ ${SCRIPT_NAME} --namespace foo
Get for namespace foo and use output file bar.csv :       $ ${SCRIPT_NAME} --namespace foo --output bar.csv

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
            -o | --output)
                OUT=$2
                shift 2
            ;;
            -q | --quite)
                QUITE=true
                shift 1
            ;;
            --no-headers)
                HEADERS=false
                shift 1
            ;;
            --console-only)
                CONSOLE_ONLY=true
                OUT=/dev/null
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
}

# Test connection to a cluster by kubectl
testConnection () {
    kubectl cluster-info > /dev/null || errorExit "Connection to cluster failed"
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

getRequestsAndLimits () {
    local data=
    local namespace=
    local pod=
    local container=
    local cpu_request=
    local mem_request=
    local cpu_limit=
    local mem_limit=
    local cpu_usage=
    local memory_usage=
    local line=
    local final_line=

    data=$(kubectl get pods ${NAMESPACE} -o json | jq -r '.items[] | .metadata.namespace + "," + .metadata.name + "," + (.spec.containers[] | .name + "," + .resources.requests.cpu + "," + .resources.requests.memory + "," + .resources.limits.cpu + "," + .resources.limits.memory)')

    # Backup OUT file if already exists
    [ -f "${OUT}" ] && [ "$CONSOLE_ONLY" == "false" ] && cp -f "${OUT}" "${OUT}.$(date +"%Y-%m-%d_%H:%M:%S")"

    # Prepare header for output CSV
    if [ "${HEADERS}" == true ]; then
        echo "Namespace,Pod,Container,CPU request,CPU Usage,Memory request,Memory Usage,CPU limit,Memory limit" | tee "${OUT}"
    else
        echo -n "" > "${OUT}"
    fi

    local OLD_IFS=${IFS}
    IFS=$'\n'
    for l in ${data}; do
        namespace=$(echo "${l}" | awk -F, '{print $1}')
        pod=$(echo "${l}" | awk -F, '{print $2}')
        container=$(echo "${l}" | awk -F, '{print $3}')
        cpu_request=$(formatCpu "$(echo "${l}" | awk -F, '{print $4}')")
        mem_request=$(formatMemory "$(echo "${l}" | awk -F, '{print $5}')")
        cpu_limit=$(formatCpu "$(echo "${l}" | awk -F, '{print $6}')")
        mem_limit=$(formatMemory "$(echo "${l}" | awk -F, '{print $7}')")

        # Adding pod and container actual usage with pod top data
        line=$(kubectl top pod -n ${namespace} ${pod} --containers --use-protocol-buffers | grep " ${container} ")

        cpu_usage=$(formatCpu "$(echo "${line}" | awk '{print $3}')")
        memory_usage=$(formatMemory "$(echo "${line}" | awk '{print $4}')")

        final_line=${namespace},${pod},${container},${cpu_request},${cpu_usage},${mem_request},${memory_usage},${cpu_limit},${mem_limit}
        if [ "${QUITE}" == true ]; then
            echo "${final_line}" >> "${OUT}"
        else
            echo "${final_line}" | tee -a "${OUT}"
        fi
    done
    IFS=${OLD_IFS}
}

main () {
    processOptions "$@"
    [ "${QUITE}" == true ] || echo "Getting pods resource requests and limits"
    testConnection
    getRequestsAndLimits
}

######### Main #########

main "$@"
