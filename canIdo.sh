#!/bin/bash

# Go over all resources in the Kubernetes cluster and check if current user can run an action on them
NAMESPACE=default
ACTIONS="get list watch create update patch delete"
RESOURCES=all
SCRIPT_NAME=$0

######### Functions #########

errorExit () {
    echo -e "\nERROR: $1\n"
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
            -a | --actions)
                ACTIONS="$(echo $2 | tr ',' ' ')"
                shift 2
            ;;
            -r | --resources)
                RESOURCES="$(echo $2 | tr ',' ' ')"
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
    echo "Testing connection to cluster"
    kubectl cluster-info > /dev/null || errorExit "Connection to cluster failed"
}

canIdo () {
    local resource
    local action
    local resource_list

    if [[ ${RESOURCES} =~ all ]]; then
        resource_list="$(kubectl api-resources --verbs=list --namespaced -o name)"
    else
        resource_list=${RESOURCES}
    fi

#    echo "List of resources:"
#    echo "${resource_list}"

    for resource in ${resource_list}; do
        for action in ${ACTIONS}; do
            echo -n "--- Checking ${action} on '${resource}': "
            kubectl auth can-i "${action}" "${resource}" --namespace="${NAMESPACE}"
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
