#!/usr/bin/env bash

# UNCOMMENT this line to enable debugging
# set -xv

## Get resources requests and limits per container in a Kubernetes cluster.

OUT=resources.csv
NAMESPACE_ARGS=(--all-namespaces)
NAMESPACE=
SKIP_USAGE=false
QUIET=false
HEADERS=true
CONSOLE_ONLY=false
SCRIPT_NAME=$(basename "$0")

######### Functions #########

errorExit () {
    echo -e "\nERROR: $1\n" >&2
    exit 1
}

usage () {
    cat << END_USAGE

${SCRIPT_NAME} - Extract resource requests, limits and actual usage in a Kubernetes cluster for a selected namespace or all namespaces in a CSV format.
                 CPU is in cores and memory is in GiB. Requires 'jq'.

Usage: ${SCRIPT_NAME} <options>

-n | --namespace <name>                : Namespace to analyse.    Default: all namespaces
-o | --output <name>                   : Output file.             Default: ${OUT}
-s | --skip-usage                      : Don't get usage (kubectl top)
-q | --quiet                           : Don't output to stdout. Write the CSV file only.  Default: Output to stdout and to the file
-h | --help                            : Show this usage
--no-headers                           : Don't print headers line
--console-only                         : Output to stdout only (don't write to file). Can't be combined with --quiet

Examples:
========
Get all:                                                  $ ${SCRIPT_NAME}
Get for namespace foo:                                    $ ${SCRIPT_NAME} --namespace foo
Get for namespace foo and use output file bar.csv :       $ ${SCRIPT_NAME} --namespace foo --output bar.csv

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
                NAMESPACE_ARGS=(--namespace "$2")
                shift 2
            ;;
            -o | --output)
                requireValue "$@"
                OUT="$2"
                shift 2
            ;;
            -s | --skip-usage)
                SKIP_USAGE=true
                shift 1
            ;;
            -q | --quiet | --quite)
                QUIET=true
                shift 1
            ;;
            --no-headers)
                HEADERS=false
                shift 1
            ;;
            --console-only)
                CONSOLE_ONLY=true
                shift 1
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

    if [[ "${CONSOLE_ONLY}" == true && "${QUIET}" == true ]]; then
        errorExit "--console-only and --quiet cannot be used together"
    fi
}

# Test kubectl and jq are installed and the connection to a cluster
testConnection () {
    command -v kubectl > /dev/null || errorExit "kubectl not found in PATH"
    command -v jq > /dev/null || errorExit "jq not found in PATH"
    kubectl cluster-info > /dev/null 2>&1 || errorExit "Connection to cluster failed"
}

# Convert a CPU value (100m, 250000n, 1) to cores
formatCpu () {
    awk -v v="$1" 'BEGIN {
        if (v == "" || v == "-") { print "-"; exit }
        n = v + 0
        if (v ~ /n$/) n /= 1e9
        else if (v ~ /u$/) n /= 1e6
        else if (v ~ /m$/) n /= 1e3
        printf "%.3f\n", n
    }'
}

# Convert a memory value (Ki, Mi, Gi, Ti, k, M, G, T, m, plain bytes) to GiB
formatMemory () {
    awk -v v="$1" 'BEGIN {
        if (v == "" || v == "-") { print "-"; exit }
        n = v + 0
        if (v ~ /Ki$/) n *= 1024
        else if (v ~ /Mi$/) n *= 1024 ^ 2
        else if (v ~ /Gi$/) n *= 1024 ^ 3
        else if (v ~ /Ti$/) n *= 1024 ^ 4
        else if (v ~ /k$/) n *= 1e3
        else if (v ~ /M$/) n *= 1e6
        else if (v ~ /G$/) n *= 1e9
        else if (v ~ /T$/) n *= 1e12
        else if (v ~ /m$/) n /= 1e3
        printf "%.3f\n", n / (1024 ^ 3)
    }'
}

# Write a CSV line to stdout, the output file, or both
emit () {
    if [[ "${CONSOLE_ONLY}" == true ]]; then
        echo "$1"
    elif [[ "${QUIET}" == true ]]; then
        echo "$1" >> "${OUT}"
    else
        echo "$1" | tee -a "${OUT}"
    fi
}

getRequestsAndLimits () {
    local data
    local top_file=
    local namespace pod container
    local cpu_request mem_request cpu_limit mem_limit
    local cpu_usage memory_usage
    local usage_line

    data=$(kubectl get pods "${NAMESPACE_ARGS[@]}" -o json | jq -r '.items[] | .metadata.namespace as $ns | .metadata.name as $pod | .spec.containers[] | [$ns, $pod, .name, (.resources.requests.cpu // "-"), (.resources.requests.memory // "-"), (.resources.limits.cpu // "-"), (.resources.limits.memory // "-")] | @tsv') || errorExit "Failed getting the pods list"

    # Get the usage of all containers in a single call, as lines of: <namespace> <pod> <container> <cpu> <memory>
    if [[ "${SKIP_USAGE}" == false ]]; then
        top_file=$(mktemp) || errorExit "Failed creating a temp file"
        trap 'rm -f "${top_file}"' EXIT
        if ! kubectl top pod "${NAMESPACE_ARGS[@]}" --containers --no-headers 2> /dev/null | awk -v ns="${NAMESPACE}" 'ns != "" {print ns, $0; next} {print}' > "${top_file}" || [[ ! -s "${top_file}" ]]; then
            echo "WARNING: Failed getting usage with 'kubectl top' (is metrics-server installed and ready?). Usage will be empty" >&2
        fi
    fi

    # Backup OUT file if already exists, then start a new one. --console-only never touches a file.
    if [[ "${CONSOLE_ONLY}" == false ]]; then
        if [[ -f "${OUT}" ]]; then
            cp -f "${OUT}" "${OUT}.$(date +"%Y-%m-%d_%H:%M:%S")" || errorExit "Failed backing up ${OUT}"
        fi
        : > "${OUT}" || errorExit "Can't write to output file ${OUT}"
    fi
    [[ "${HEADERS}" == true ]] && emit "Namespace,Pod,Container,CPU request,CPU Usage,Memory request,Memory Usage,CPU limit,Memory limit"

    while IFS=$'\t' read -r namespace pod container cpu_request mem_request cpu_limit mem_limit; do
        [[ -n "${namespace}" ]] || continue

        # Adding pod and container actual usage with pod top data
        cpu_usage="-"
        memory_usage="-"
        if [[ -n "${top_file}" ]]; then
            usage_line=$(awk -v ns="${namespace}" -v p="${pod}" -v c="${container}" '$1 == ns && $2 == p && $3 == c {print $4, $5; exit}' "${top_file}")
            if [[ -n "${usage_line}" ]]; then
                cpu_usage=$(formatCpu "${usage_line% *}")
                memory_usage=$(formatMemory "${usage_line#* }")
            fi
        fi

        emit "${namespace},${pod},${container},$(formatCpu "${cpu_request}"),${cpu_usage},$(formatMemory "${mem_request}"),${memory_usage},$(formatCpu "${cpu_limit}"),$(formatMemory "${mem_limit}")"
    done <<< "${data}"
}

main () {
    processOptions "$@"
    [[ "${QUIET}" == true ]] || echo "Getting pods resource requests and limits" >&2
    testConnection
    getRequestsAndLimits
}

######### Main #########

main "$@"
