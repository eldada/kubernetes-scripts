#!/usr/bin/env bash

# Go over all resources in the Kubernetes cluster and check if current user can run an action on them

# UNCOMMENT this line to enable debugging
# set -xv

NAMESPACE=default
ACTIONS="get list watch create update patch delete"
RESOURCES=all
SCRIPT_NAME=$(basename "$0")

######### Functions #########

errorExit () {
    echo -e "\nERROR: $1\n" >&2
    exit 1
}

usage () {
    cat << END_USAGE

${SCRIPT_NAME} - Check if current user can perform the selected action in a given namespace

Usage: ${SCRIPT_NAME} <options>

-n | --namespace <name>                   : Namespace to check.          Default: ${NAMESPACE}
-a | --actions <comma delimited list>     : List of actions.             Default: (${ACTIONS})
-r | --resources <comma delimited list>   : List of resources to test.   Default: all
-h | --help                               : Show this usage.

Examples:
========
Test all permissions for namespace 'foo':                            $ ${SCRIPT_NAME} --namespace foo
Test 'get' and 'list' permissions for namespace 'bar':               $ ${SCRIPT_NAME} --namespace bar --actions get,list
Test 'get' and 'list' permissions on 'pods' and 'secrets':           $ ${SCRIPT_NAME} --resources pods,secrets --actions get,list

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
            -a | --actions)
                requireValue "$@"
                ACTIONS="${2//,/ }"
                shift 2
            ;;
            -r | --resources)
                requireValue "$@"
                RESOURCES="${2//,/ }"
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

canIdo () {
    local resource
    local action
    local resource_list
    local answer

    if [[ "${RESOURCES}" == all ]]; then
        resource_list="$(kubectl api-resources --verbs=list --namespaced -o name)" || errorExit "Failed getting the list of resources"
    else
        resource_list=${RESOURCES}
    fi

    for resource in ${resource_list}; do
        for action in ${ACTIONS}; do
            # 'kubectl auth can-i' exits with 1 when the answer is 'no', so don't treat that as a failure
            answer=$(kubectl auth can-i "${action}" "${resource}" --namespace="${NAMESPACE}" 2>&1)
            echo "--- Checking ${action} on '${resource}': ${answer}"
        done
    done
}

main () {
    processOptions "$@"
    testConnection

    echo "Testing actions [${ACTIONS}] on [${RESOURCES}] resources in namespace ${NAMESPACE}"

    canIdo
}

######### Main #########

main "$@"
