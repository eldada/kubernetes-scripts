#!/usr/bin/env bash

# Go over all namespaces in a cluster and check if they are empty of workloads and controller objects

# UNCOMMENT this line to enable debugging
# set -xv

# All workload objects to search for
OBJECTS=pods,jobs,cronjobs,deployments,daemonsets,statefulsets
SCRIPT_NAME=$(basename "$0")

######### Functions #########

errorExit () {
    echo -e "\nERROR: $1\n" >&2
    exit 1
}

usage () {
    cat << END_USAGE

${SCRIPT_NAME} - Find namespaces that have no workloads (${OBJECTS}) in them

Usage: ${SCRIPT_NAME} <options>

-h | --help                            : Show this usage

Examples:
========
$ ${SCRIPT_NAME}

END_USAGE
}

# Process command line options. See usage above for supported options
processOptions () {
    while [[ $# -gt 0 ]]; do
        case "$1" in
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

# Test kubectl is installed and the connection to a cluster
testConnection () {
    command -v kubectl > /dev/null || errorExit "kubectl not found in PATH"
    kubectl cluster-info > /dev/null 2>&1 || errorExit "Connection to cluster failed"
}

findEmptyNamespaces () {
    local ns_all
    local ns_wl

    # Temp files for the comparison later on. Removed on exit
    ns_all=$(mktemp) || errorExit "Failed creating a temp file"
    ns_wl=$(mktemp) || errorExit "Failed creating a temp file"
    trap 'rm -f "${ns_all}" "${ns_wl}"' EXIT

    # Get list of all namespaces
    kubectl get ns --no-headers -o=custom-columns=NAME:.metadata.name | sort -u > "${ns_all}" || errorExit "Failed getting the namespaces list"

    # Get list of all namespaces with any workload in them
    kubectl get ${OBJECTS} --no-headers --all-namespaces -o=custom-columns=NAMESPACE:.metadata.namespace | sort -u > "${ns_wl}" || errorExit "Failed getting the workloads list"

    # Find all values in ns_all that are not in ns_wl (these are empty namespaces).
    # Whole line, fixed string match, so namespace 'foo' is not matched by 'foo-bar'
    grep -vxFf "${ns_wl}" "${ns_all}"

    # grep exits with 1 when nothing is printed, which here just means there are no empty namespaces
    return 0
}

main () {
    processOptions "$@"
    testConnection
    findEmptyNamespaces
}

######### Main #########

main "$@"
