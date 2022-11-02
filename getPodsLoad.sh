#!/bin/bash

# UNCOMMENT this line to enable debugging
# set -xv

# Get formatted results of the pods underlying node's load average (using cat /proc/loadavg)
NAMESPACE=default
SCRIPT_NAME=$0

######### Functions #########

errorExit () {
    echo -e "\nERROR: $1\n"
    exit 1
}

usage () {
    cat << END_USAGE

${SCRIPT_NAME} - Get formatted results of the pods underlying node's load average (using cat /proc/loadavg)

Usage: ${SCRIPT_NAME} <options>

-n | --namespace <name>      : Namespace to use. Default: default
-h | --help                  : Show this usage

Examples:
========
Get load form pods in namespace bar:            $ ${SCRIPT_NAME} --namespace bar

END_USAGE

    exit 1
}

# Process command line options. See usage above for supported options
processOptions () {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -n | --namespace)
                NAMESPACE="$2"
                shift 2
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

# Test connection and that there are pods in the namespace
testConnection () {
    kubectl get ns "${NAMESPACE}" > /dev/null || errorExit "Namespace ${NAMESPACE} does not exist"
    [[ $(kubectl get pods -n "${NAMESPACE}" 2> /dev/null| wc -l | tr -d ' ') == '0' ]] && errorExit "Namespace ${NAMESPACE} has no running pods"
}

getPodsLoad () {
    local load1
    local load5
    local load15
    local dummy
    local pods

    # Print header
    echo "Pod, Load 1, Load 5, Load 15"

    # Get list of pods
    pods=$(kubectl get pods -n "${NAMESPACE}" --no-headers -o=custom-columns=NAME:.metadata.name)

    # Go over the pods and extract data
    for p in $pods; do
        read -r load1 load5 load15 dummy <<< $(kubectl exec -n "${NAMESPACE}" "$p" -- sh -c "cat /proc/loadavg" 2> /dev/null)
        echo "$p, $load1, $load5, $load15"
    done
}

main () {
    processOptions "$@"
    testConnection
    getPodsLoad
}

######### Main #########

main "$@"
