#!/usr/bin/env bash

# UNCOMMENT this line to enable debugging
# set -xv

## Get all pods with restarting containers sorted as csv output

NAMESPACE_ARGS=(--all-namespaces)
SCRIPT_NAME=$(basename "$0")

######### Functions #########

errorExit () {
    echo -e "\nERROR: $1\n" >&2
    exit 1
}

usage () {
    cat << END_USAGE

${SCRIPT_NAME} - Get all pods with restarting containers in a Kubernetes cluster for a selected namespace or all namespaces.
                 Output is in a CSV format, sorted by the total restarts count.

Usage: ${SCRIPT_NAME} <options>

-n | --namespace <name>                : Namespace to analyse.    Default: all namespaces
-h | --help                            : Show this usage

Examples:
========
Get all:                                                  $ ${SCRIPT_NAME}
Get for namespace foo:                                    $ ${SCRIPT_NAME} --namespace foo

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
                NAMESPACE_ARGS=(--namespace "$2")
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

# Test kubectl is installed and the connection to a cluster
testConnection () {
    command -v kubectl > /dev/null || errorExit "kubectl not found in PATH"
    kubectl cluster-info > /dev/null 2>&1 || errorExit "Connection to cluster failed"
}

# Add up a space separated list of numbers
addValues () {
    local v
    local values_sum=0

    for v in $1; do
        values_sum=$(( values_sum + v ))
    done

    echo -n "${values_sum}"
}

getRestartingPods () {
    local data
    local namespace_and_pod
    local restarts
    local restart_sum
    local out_temp

    data=$(kubectl get pod "${NAMESPACE_ARGS[@]}" -o=jsonpath='{range .items[*]}{.metadata.namespace},{.metadata.name} {.status.containerStatuses[*].restartCount}{"\n"}{end}') || errorExit "Failed getting the pods list"

    out_temp=$(mktemp) || errorExit "Failed creating a temp file"
    trap 'rm -f "${out_temp}"' EXIT

    while read -r namespace_and_pod restarts; do
        [[ -n "${namespace_and_pod}" ]] || continue

        # Go over container restart and add them up
        restart_sum=$(addValues "${restarts}")

        if [[ "${restart_sum}" -gt 0 ]]; then
            echo "${namespace_and_pod},${restart_sum}" >> "${out_temp}"
        fi
    done <<< "${data}"

    # Print sorted output
    echo "Namespace,Pod,Total restarts"
    sort -t , -n -k 3 -r "${out_temp}"
}

main () {
    processOptions "$@"
    testConnection
    getRestartingPods
}

######### Main #########

main "$@"
