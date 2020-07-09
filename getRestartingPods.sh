#!/bin/bash

## Get all pods with restarting containers and sum the values

OUT=restarting.csv
NAMESPACE=--all-namespaces
QUITE=false
HEADERS=true
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
-q | --quite                           : Don't output to screen.  Default: Output to screen
-h | --help                            : Show this usage
--no-headers                           : Don't print headers line

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
                NAMESPACE="-n $2"
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

addValues () {
    values_str=$1

    [ -z "${values_str}" ] && echo -n 0

    values_sum=0
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

    data=$(kubectl get pod ${NAMESPACE} -o=jsonpath='{range .items[*]}{.metadata.namespace},{.metadata.name},{.status.containerStatuses[*].restartCount}{"\n"}')

    # Backup OUT file if already exists
    [ -f "${OUT}" ] && cp -f "${OUT}" "${OUT}.$(date +"%Y-%m-%d_%H:%M:%S")"

    # Prepare header for output CSV
    if [ "${HEADERS}" == true ]; then
        echo "Namespace,Pod,Total restarts" > "${OUT}"
    else
        echo -n "" > "${OUT}"
    fi

    OLD_IFS=${IFS}
    IFS=$'\n'
    for l in ${data}; do
#        echo "Line: $l"

        namespace=$(echo "${l}" | awk -F, '{print $1}')
        pod=$(echo "${l}" | awk -F, '{print $2}')
        restarts=$(echo "${l}" | awk -F, '{print $3}')

        # Add restarts only if values exist
        if [ -n "${restarts}" ]; then
            # Go over container restart and add them up
            restart_sum=$(addValues "${restarts}")
#            echo "Sum: $restart_sum"

            if [ $restart_sum -gt 0 ]; then
                final_line=${namespace},${pod},${restart_sum}
                if [ "${QUITE}" == true ]; then
                    echo "${final_line}" >> "${OUT}"
                else
                    echo "${final_line}" | tee -a "${OUT}"
                fi
            fi
        fi
    done
    IFS=${OLD_IFS}
}

main () {
    processOptions "$@"
    [ "${QUITE}" == true ] || echo "Getting Kubernetes cluster pods restarts"
    testConnection
    getRestartingPods
}

######### Main #########

main "$@"
