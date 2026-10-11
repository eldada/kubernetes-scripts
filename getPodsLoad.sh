#!/usr/bin/env bash

# Get formatted results of the pods underlying node's load average (using cat /proc/loadavg)

# UNCOMMENT this line to enable debugging
# set -xv

NAMESPACE=default
INCLUDE_FILTER=.*
SCRIPT_NAME=$(basename "$0")

######### Functions #########

errorExit () {
    echo -e "\nERROR: $1\n" >&2
    exit 1
}

usage () {
    cat << END_USAGE

${SCRIPT_NAME} - Get formatted results of the pods underlying node's load average (using cat /proc/loadavg).
                 Runs a command in the pods, so it needs permission to 'exec' in them.

Usage: ${SCRIPT_NAME} <options>

-n | --namespace <name>      : Namespace to use.                                      Default: ${NAMESPACE}
-i | --include <regex>       : Include only pods with names matching this regex.      Default: all pods
-h | --help                  : Show this usage

Examples:
========
# Get load form pods in namespace bar:
${SCRIPT_NAME} --namespace bar

# Get only specific pods in namespace
${SCRIPT_NAME} --namespace bar --include artifactory

END_USAGE
}

# Make sure an option has a value
requireValue () {
    [[ $# -ge 2 && -n "$2" ]] || errorExit "Option $1 requires a value"
}

# Process command line options. See usage above for supported options
processOptions () {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -n | --namespace)
                requireValue "$@"
                NAMESPACE="$2"
                shift 2
            ;;
            -i | --include)
                requireValue "$@"
                INCLUDE_FILTER="$2"
                shift 2
            ;;
            -h | --help)
                usage
                exit 0
            ;;
            *)
                usage >&2
                exit 1
            ;;
        esac
    done
}

# Test kubectl is installed, the connection to a cluster and that there are pods in the namespace
testConnection () {
    command -v kubectl > /dev/null || errorExit "kubectl not found in PATH"
    kubectl cluster-info > /dev/null 2>&1 || errorExit "Connection to cluster failed"
    kubectl get ns "${NAMESPACE}" > /dev/null 2>&1 || errorExit "Namespace ${NAMESPACE} does not exist"
}

getPodsLoad () {
    local load1
    local load5
    local load15
    local dummy
    local pods
    local p

    # Get list of pods
    pods=$(kubectl get pods -n "${NAMESPACE}" --no-headers -o=custom-columns=NAME:.metadata.name) || errorExit "Failed getting the pods list"
    [[ -n "${pods}" ]] || errorExit "Namespace ${NAMESPACE} has no pods"

    # Print header
    echo "Pod,Load 1,Load 5,Load 15"

    # Go over the pods and extract data
    for p in ${pods}; do
        if [[ ${p} =~ ${INCLUDE_FILTER} ]]; then
            read -r load1 load5 load15 dummy <<< "$(kubectl exec -n "${NAMESPACE}" "${p}" -- sh -c "cat /proc/loadavg" 2> /dev/null)"
            if [[ -z "${load1}" ]]; then
                echo "WARNING: Failed getting load from pod ${p}" >&2
                echo "${p},-,-,-"
            else
                echo "${p},${load1},${load5},${load15}"
            fi
        fi
    done
}

main () {
    processOptions "$@"
    testConnection
    getPodsLoad
}

######### Main #########

main "$@"
