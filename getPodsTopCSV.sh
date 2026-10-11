#!/usr/bin/env bash

# UNCOMMENT this line to enable debugging
# set -xv

## Get formatted results of kubectl top pod --containers

OUT=top-$(date +"%Y-%m-%d_%H:%M:%S").csv
NAMESPACE=default
QUIET=false
HEADERS=true
SCRIPT_NAME=$(basename "$0")
DURATION=0
INTERVAL=5
POD=
CONTAINERS=false

######### Functions #########

errorExit () {
    echo -e "\nERROR: $1\n" >&2
    exit 1
}

usage () {
    cat << END_USAGE

${SCRIPT_NAME} - Get formatted results of kubectl top pod in a Kubernetes cluster for a selected namespace and pod in a CSV format.
                 CPU is in cores and memory is in GiB.

Usage: ${SCRIPT_NAME} <options>

-n | --namespace <name>                : Namespace to analyse.      Default: ${NAMESPACE}
-p | --pod <name>                      : Pod to analyse (required).
-d | --duration <seconds>              : Duration of sampling.      Default: ${DURATION} (infinite)
-i | --interval <seconds>              : Interval between samples.  Default: ${INTERVAL}
-o | --output <name>                   : Output file.               Default: top-<timestamp>.csv
-c | --containers                      : Output per container.      Default: off
-q | --quiet                           : Don't output to screen.    Default: Output to screen
-h | --help                            : Show this usage
--no-headers                           : Don't print headers line

Examples:
========
Get for pod foo in namespace bar:                                $ ${SCRIPT_NAME} --namespace bar --pod foo
Get for pod foo in namespace bar and output to file foo.csv :    $ ${SCRIPT_NAME} --namespace bar --pod foo --output foo.csv
Sample pod foo in namespace bar every 10 seconds for 5 minutes:  $ ${SCRIPT_NAME} --namespace bar --pod foo --interval 10 --duration 300

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
            -p | --pod)
                requireValue "$@"
                POD="$2"
                shift 2
            ;;
            -d | --duration)
                requireValue "$@"
                DURATION="$2"
                shift 2
            ;;
            -i | --interval)
                requireValue "$@"
                INTERVAL="$2"
                shift 2
            ;;
            -o | --output)
                requireValue "$@"
                OUT="$2"
                shift 2
            ;;
            -c | --containers)
                CONTAINERS=true
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

    [[ -n "${POD}" ]] || errorExit "Must provide pod name (--pod <POD>)"
    [[ "${DURATION}" =~ ^[0-9]+$ ]] || errorExit "Duration must be a number of seconds"
    [[ "${INTERVAL}" =~ ^[0-9]+$ ]] || errorExit "Interval must be a number of seconds"
}

# Test kubectl is installed and the connection to a cluster
testConnection () {
    command -v kubectl > /dev/null || errorExit "kubectl not found in PATH"
    kubectl cluster-info > /dev/null 2>&1 || errorExit "Connection to cluster failed"
    kubectl get pod -n "${NAMESPACE}" "${POD}" > /dev/null 2>&1 || errorExit "Pod ${POD} not found in namespace ${NAMESPACE}"
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

# Write a line to the output file, and to the screen unless quiet
emit () {
    if [[ "${QUIET}" == true ]]; then
        echo "$1" >> "${OUT}"
    else
        echo "$1" | tee -a "${OUT}"
    fi
}

getPodsTop () {
    local counter=0
    local end_time=0
    local top_args=(top pod -n "${NAMESPACE}" "${POD}" --no-headers)
    local header="Timestamp,Pod,CPU (cores),Memory (GiB)"
    local data
    local time_stamp
    local container
    local cpu
    local memory
    local name

    if [[ "${CONTAINERS}" == true ]]; then
        top_args+=(--containers)
        header="Timestamp,Pod,Container,CPU (cores),Memory (GiB)"
    fi
    [[ "${DURATION}" -gt 0 ]] && end_time=$(( $(date +%s) + DURATION ))

    # Start a new output file, with a header line unless disabled
    : > "${OUT}" || errorExit "Can't write to output file ${OUT}"
    [[ "${HEADERS}" == true ]] && emit "${header}"

    while true; do
        if ! data=$(kubectl "${top_args[@]}"); then
            # Fail on the first sample. Transient failures later on should not stop a long sampling
            [[ ${counter} -eq 0 ]] && errorExit "Failed running 'kubectl top' (is metrics-server installed and ready?)"
            echo "WARNING: 'kubectl top' failed. Skipping this sample" >&2
        else
            time_stamp=$(date +"%Y-%m-%d_%H:%M:%S")

            # Go over all the containers
            while read -r name container cpu memory; do
                [[ -n "${name}" ]] || continue
                if [[ "${CONTAINERS}" == true ]]; then
                    emit "${time_stamp},${POD},${container},$(formatCpu "${cpu}"),$(formatMemory "${memory}")"
                else
                    # No container column in this mode, so the values are shifted
                    emit "${time_stamp},${POD},$(formatCpu "${container}"),$(formatMemory "${cpu}")"
                fi
            done <<< "${data}"
        fi

        counter=$(( counter + 1 ))

        # Done when the duration is over. Duration 0 means sample forever
        if [[ ${end_time} -gt 0 && $(( $(date +%s) + INTERVAL )) -gt ${end_time} ]]; then
            break
        fi
        sleep "${INTERVAL}"
    done
}

main () {
    processOptions "$@"
    [[ "${QUIET}" == true ]] || echo "Getting Pod memory and cpu usage" >&2
    testConnection
    getPodsTop
}

######### Main #########

main "$@"
