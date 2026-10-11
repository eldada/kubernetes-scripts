#!/usr/bin/env bash

# Count number of pods and containers per node in a kubernetes cluster and write a CSV formatted output

# UNCOMMENT this line to enable debugging
# set -xv

SCRIPT_NAME=$(basename "$0")

######### Functions #########

errorExit () {
    echo -e "\nERROR: $1\n" >&2
    exit 1
}

usage () {
    cat << END_USAGE

${SCRIPT_NAME} - Count number of pods and containers per node in a Kubernetes cluster. Output in CSV format.

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

countPodsAndContainers () {
    local nodes
    local node
    local pods
    local containers

    nodes=$(kubectl get nodes -o jsonpath="{.items[*].metadata.name}") || errorExit "Failed getting the nodes list"

    # Header for CSV
    echo "Node,Pods count,Containers count"

    for node in ${nodes}; do
        pods=$(kubectl get pods -A -o jsonpath="{.items[*].metadata.name}" --field-selector spec.nodeName="${node}") || errorExit "Failed getting pods on node ${node}"
        containers=$(kubectl get pods -A -o jsonpath="{.items[*].spec.containers[*].name}" --field-selector spec.nodeName="${node}") || errorExit "Failed getting containers on node ${node}"

        echo "${node},$(echo "${pods}" | wc -w | tr -d ' '),$(echo "${containers}" | wc -w | tr -d ' ')"
    done
}

main () {
    processOptions "$@"
    testConnection
    countPodsAndContainers
}

######### Main #########

main "$@"
