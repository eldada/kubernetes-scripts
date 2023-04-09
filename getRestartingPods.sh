#!/bin/bash

# UNCOMMENT this line to enable debugging
# set -xv

## Get all pods with restarting containers sorted as csv output

NAMESPACE=--all-namespaces
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
-h | --help                            : Show this usage

Examples:
========
Get all:                                                  $ ${SCRIPT_NAME}
Get for namespace foo:                                    $ ${SCRIPT_NAME} --namespace foo

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
            -h | --help)
                usage
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

addValues () {
    local values_str=$1

    [ -z "${values_str}" ] && echo -n 0

    local values_sum=0
    OLD_IFS=${IFS}
    IFS=' '
    for v in ${values_str}; do
        values_sum=$(( values_sum + v ))
    done
    IFS=${OLD_IFS}

    echo -n ${values_sum}
}

getRestartingPods () {
    local data=
    local namespace_and_pod=
    local restarts=
    local restart_sum=
    local out_temp=

    out_temp=$(mktemp)

    data=$(kubectl get pod ${NAMESPACE} -o=jsonpath='{range .items[*]}{.metadata.namespace},{.metadata.name} {.status.containerStatuses[*].restartCount}{"\n"}{end}')

    OLD_IFS=${IFS}
    IFS=$'\n'
    for l in ${data}; do
        # Extract the fields so the restarts can be added up later
        IFS=${OLD_IFS}; read -r namespace_and_pod restarts <<< "${l}"; OLD_IFS=${IFS}; IFS=$'\n'

        # Go over container restart and add them up
        restart_sum=$(addValues "${restarts}")

        if [ "${restart_sum}" -gt 0 ]; then
            local final_line=${namespace_and_pod},${restart_sum}
            echo "${final_line}" >> "${out_temp}"
        fi
    done
    IFS=${OLD_IFS}

    # Print sorted output
    echo "Namespace,Pod,Total restarts"
    sort -t , -n -k 3 -r "${out_temp}"

    # Cleanup
    rm -f "${out_temp}"
}

main () {
    processOptions "$@"
    testConnection
    getRestartingPods
}

######### Main #########

main "$@"
