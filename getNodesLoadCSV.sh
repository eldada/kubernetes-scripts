#!/usr/bin/env bash

# Go over all nodes in a cluster and extract the load average from them by running
#  > cat /proc/loadavg
# in the kube-proxy pods (since they run as a Daemonset).

# UNCOMMENT this line to enable debugging
# set -xv

NAMESPACE=kube-system
SELECTOR=k8s-app=kube-proxy
CONTAINER=kube-proxy
SCRIPT_NAME=$(basename "$0")

######### Functions #########

errorExit () {
    echo -e "\nERROR: $1\n" >&2
    exit 1
}

usage () {
    cat << END_USAGE

${SCRIPT_NAME} - Get the load average and number of CPUs of all nodes in a cluster (CSV format).
                 Runs a command in the kube-proxy pods (in the ${NAMESPACE} namespace), so it needs permission to 'exec' in them.
                 Nodes with a 5 minutes load higher than the number of CPUs are marked as 'YES' in the 'High load' column.

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

getNodesLoad () {
    local pods
    local first_pod
    local line
    local p
    local node
    local alert
    local load1 load5 load15 dummy1 dummy2 cpu

    # Get pod and node name pairs
    pods=$(kubectl get po -n "${NAMESPACE}" -l "${SELECTOR}" -o jsonpath='{range .items[*]}{.metadata.name},{.spec.nodeName}{"\n"}{end}') || errorExit "Failed getting the kube-proxy pods"
    [[ -n "${pods}" ]] || errorExit "No kube-proxy pods found in namespace ${NAMESPACE} (selector ${SELECTOR})"

    # Test on the first pod that the "cat /proc/loadavg; echo ' '; nproc" works (blocked on newer versions of kube-proxy)
    first_pod="${pods%%,*}"
    kubectl exec -n "${NAMESPACE}" "${first_pod}" -c "${CONTAINER}" -- sh -c "cat /proc/loadavg; echo ' '; nproc" > /dev/null 2>&1 || errorExit "Failed to run command on kube-proxy pod. This script cannot be used to get load"

    # Header for the CSV output
    echo "Node,Load 1 min,Load 5 min,Load 15 min,CPU,High load"

    # Go over the pods and extract data
    while IFS=, read -r p node; do
        [[ -n "${p}" ]] || continue
        alert="-"
        line=$(kubectl exec -n "${NAMESPACE}" "${p}" -c "${CONTAINER}" -- sh -c "cat /proc/loadavg; echo ' '; nproc" 2> /dev/null | tr '\n' ' ')
        read -r load1 load5 load15 dummy1 dummy2 cpu <<< "${line}"

        if [[ -z "${load5}" || -z "${cpu}" ]]; then
            echo "WARNING: Failed getting load from pod ${p} (node ${node})" >&2
            echo "${node},-,-,-,-,-"
            continue
        fi

        # If load > number of cpu, it should be marked with YES as "High load"
        if awk -v l="${load5}" -v c="${cpu}" 'BEGIN {exit !(l > c)}'; then alert="YES"; fi

        echo "${node},${load1},${load5},${load15},${cpu},${alert}"
    done <<< "${pods}"
}

main () {
    processOptions "$@"
    testConnection
    getNodesLoad
}

######### Main #########

main "$@"
