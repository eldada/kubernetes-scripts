#!/usr/bin/env bash

# UNCOMMENT this line to enable debugging
# set -xv

## Node and cluster CPU and memory requests, limits, and optional utilization.
## Inspired by https://github.com/robscott/kube-capacity

NAMESPACE=
SHOW_UTIL=false
SHOW_TOTAL=false
SCRIPT_NAME=$(basename "$0")

######### Functions #########

errorExit () {
    echo -e "\nERROR: $1\n" >&2
    exit 1
}

usage () {
    cat << END_USAGE

${SCRIPT_NAME} - Show CPU and memory requests and limits for each node, as a share of allocatable.
                 CPU is in millicores and memory is in MiB (rounded up). Requires 'jq'.
                 With more than one node, the first row (*) is the cluster total.
                 --total prints only that row.
                 Succeeded and Failed pods are skipped. Requests and limits follow the scheduler:
                 sum of containers, sidecars included, other init containers as a max, plus pod overhead.
                 Inspired by https://github.com/robscott/kube-capacity

Usage: ${SCRIPT_NAME} <options>

-n | --namespace <name>                : Only count pods in this namespace. Allocatable stays the whole node.
                                         With --util, usage is the sum of those pods instead of the node total.
                                         Default: all namespaces
-u | --util                            : Add CPU UTIL and MEMORY UTIL. Requires metrics-server and
                                         permission to list nodes.metrics.k8s.io (pods.metrics.k8s.io
                                         when --namespace is set).
                                         Node usage includes everything metrics-server reports for the node,
                                         so it is not the sum of the pods.
-t | --total                           : Print only the cluster total (*)
-h | --help                            : Show this usage

Examples:
========
Requests and limits:                                  $ ${SCRIPT_NAME}
Add live usage:                                       $ ${SCRIPT_NAME} --util
Cluster total only:                                   $ ${SCRIPT_NAME} --total
One namespace:                                        $ ${SCRIPT_NAME} --namespace kube-system --util

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
            -u | --util)
                SHOW_UTIL=true
                shift 1
            ;;
            -t | --total)
                SHOW_TOTAL=true
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
}

# Test kubectl and jq are installed and the connection to a cluster
testConnection () {
    command -v kubectl > /dev/null || errorExit "kubectl not found in PATH"
    command -v jq > /dev/null || errorExit "jq not found in PATH"
    kubectl cluster-info > /dev/null 2>&1 || errorExit "Connection to cluster failed"
}

# Stop before the metrics call when the current user cannot list them.
# 'kubectl auth can-i' prints yes or no. Any other failure is a warning, and the call proceeds.
requireAccess () {
    local verb="$1"
    local resource="$2"
    local why="$3"
    shift 3
    local answer err_file rc

    err_file=$(mktemp "${TMPDIR:-/tmp}/kapacity-cani.XXXXXX") || errorExit "Failed creating a temp file"
    answer=$(kubectl auth can-i "${verb}" "${resource}" "$@" 2>"${err_file}")
    rc=$?
    if [[ "${rc}" -eq 0 && "${answer}" == "yes" ]]; then
        rm -f "${err_file}"
        return 0
    fi
    if [[ "${answer}" == "no" ]]; then
        rm -f "${err_file}"
        errorExit "${why}"
    fi
    echo "WARNING: Could not check whether the current user can ${verb} ${resource}. Continuing." >&2
    if [[ -s "${err_file}" ]]; then
        cat "${err_file}" >&2
    fi
    rm -f "${err_file}"
    return 0
}

# Sum pod requests and limits onto each node's allocatable and print the table.
# Utilization comes from the metrics API (metrics.k8s.io), which is what kube-capacity reads.
reportCapacity () {
    local workdir nodes_file pods_file metrics_file rows_file
    local pod_args metrics_path util_scope util_flag total_flag

    # Fail before listing the cluster when --util needs a permission this user does not have.
    if [[ "${SHOW_UTIL}" == true ]]; then
        if [[ -n "${NAMESPACE}" ]]; then
            requireAccess list pods.metrics.k8s.io \
                "Current user cannot list pods.metrics.k8s.io in namespace ${NAMESPACE}, which --util needs.\nAsk for get and list on pods in API group metrics.k8s.io in that namespace." \
                --namespace "${NAMESPACE}"
        else
            requireAccess list nodes.metrics.k8s.io \
                "Current user cannot list nodes.metrics.k8s.io, which --util needs.\nThis is the same permission as 'kubectl top nodes'.\nAsk for get and list on nodes in API group metrics.k8s.io."
        fi
    fi

    workdir=$(mktemp -d "${TMPDIR:-/tmp}/kapacity.XXXXXX") || errorExit "Failed creating a temp directory"
    # Expand the path now. A local variable is gone by the time the EXIT trap runs.
    trap 'rm -rf "'"${workdir}"'"' EXIT
    nodes_file="${workdir}/nodes.json"
    pods_file="${workdir}/pods.json"
    metrics_file="${workdir}/metrics.json"
    rows_file="${workdir}/rows.tsv"

    pod_args=(--all-namespaces)
    if [[ -n "${NAMESPACE}" ]]; then
        pod_args=(--namespace "${NAMESPACE}")
    fi

    kubectl get nodes -o json > "${nodes_file}" || errorExit "Failed getting the nodes list"
    kubectl get pods "${pod_args[@]}" -o json > "${pods_file}" || errorExit "Failed getting the pods list"

    # "off" leaves utilization at zero and the formatter omits those columns.
    util_scope=off
    echo '{"items":[]}' > "${metrics_file}"
    if [[ "${SHOW_UTIL}" == true ]]; then
        if [[ -n "${NAMESPACE}" ]]; then
            metrics_path="/apis/metrics.k8s.io/v1beta1/namespaces/${NAMESPACE}/pods"
            util_scope=pods
        else
            metrics_path="/apis/metrics.k8s.io/v1beta1/nodes"
            util_scope=nodes
        fi
        kubectl get --raw "${metrics_path}" > "${metrics_file}" \
            || errorExit "Failed getting metrics (is metrics-server installed and ready, and can this identity read metrics.k8s.io?)"
    fi

    # One TSV row per node. CPU is nanocores and memory is bytes, summed exactly.
    # The table rounds CPU up to millicores and memory up to MiB, once per cell,
    # including the cluster total (not as a sum of already rounded node cells).
    jq -nr \
        --slurpfile nodes "${nodes_file}" \
        --slurpfile pods "${pods_file}" \
        --slurpfile metrics "${metrics_file}" \
        --arg util_scope "${util_scope}" \
        -f /dev/stdin > "${rows_file}" <<'KAPACITY_JQ' || errorExit "Failed calculating capacity"

# Ceil for positive values. Used for memory, where Quantity.Value() rounds up to bytes.
def pos_ceil:
    if . <= 0 then 0
    elif . == floor then floor
    else floor + 1
    end;

# Kubernetes quantity to nanocores ("cpu") or bytes ("memory").
# CPU is not rounded here. MilliValue() rounds the sum, at display time.
def parse_qty($kind):
    if . == null then 0
    else
        tostring as $raw |
        if ($raw == "" or $raw == "<none>" or $raw == "<unknown>" or $raw == "-") then 0
        else
            (try ($raw | capture("^(?<n>[+-]?(?:[0-9]+(?:[.][0-9]*)?|[.][0-9]+)(?:[eE][+-]?[0-9]+)?)(?<u>[A-Za-z]*)$")) catch null) as $p |
            if $p == null then error("Cannot parse \($kind) quantity '\($raw)'")
            else
                ($p.n | tonumber) as $n |
                (
                    if $kind == "cpu" then
                        if $p.u == "n" then $n
                        elif $p.u == "u" then $n * 1000
                        elif $p.u == "m" then $n * 1000000
                        elif $p.u == "" then $n * 1000000000
                        else error("Cannot parse cpu quantity '\($raw)'")
                        end
                    else
                        if $p.u == "Ki" then $n * 1024
                        elif $p.u == "Mi" then $n * 1048576
                        elif $p.u == "Gi" then $n * 1073741824
                        elif $p.u == "Ti" then $n * 1099511627776
                        elif $p.u == "Pi" then $n * 1125899906842624
                        elif $p.u == "Ei" then $n * 1152921504606846976
                        elif ($p.u == "k" or $p.u == "K") then $n * 1000
                        elif $p.u == "M" then $n * 1000000
                        elif $p.u == "G" then $n * 1000000000
                        elif $p.u == "T" then $n * 1000000000000
                        elif $p.u == "P" then $n * 1000000000000000
                        elif $p.u == "E" then $n * 1000000000000000000
                        elif $p.u == "m" then $n / 1000
                        elif $p.u == "u" then $n / 1000000
                        elif $p.u == "n" then $n / 1000000000
                        elif $p.u == "" then $n
                        else error("Cannot parse memory quantity '\($raw)'")
                        end
                    end
                ) | if $kind == "memory" then pos_ceil else . end
            end
        end
    end;

def zero:
    {cpu_req: 0, mem_req: 0, cpu_lim: 0, mem_lim: 0};

def add($a; $b):
    {
        cpu_req: ($a.cpu_req + $b.cpu_req),
        mem_req: ($a.mem_req + $b.mem_req),
        cpu_lim: ($a.cpu_lim + $b.cpu_lim),
        mem_lim: ($a.mem_lim + $b.mem_lim)
    };

def rmax($a; $b):
    {
        cpu_req: (if $b.cpu_req > $a.cpu_req then $b.cpu_req else $a.cpu_req end),
        mem_req: (if $b.mem_req > $a.mem_req then $b.mem_req else $a.mem_req end),
        cpu_lim: (if $b.cpu_lim > $a.cpu_lim then $b.cpu_lim else $a.cpu_lim end),
        mem_lim: (if $b.mem_lim > $a.mem_lim then $b.mem_lim else $a.mem_lim end)
    };

def res($c):
    {
        cpu_req: ($c.resources.requests.cpu | parse_qty("cpu")),
        mem_req: ($c.resources.requests.memory | parse_qty("memory")),
        cpu_lim: ($c.resources.limits.cpu | parse_qty("cpu")),
        mem_lim: ($c.resources.limits.memory | parse_qty("memory"))
    };

# Same rules as kubectl's PodRequestsAndLimits (Kubernetes 1.29):
# sum app containers, add sidecars (init containers with restartPolicy Always)
# in list order, take the max against the other init containers, then add overhead.
# Overhead is added to a limit only when that limit is already non-zero.
# In-place resize (status.allocatedResources) is not applied.
def pod_resources:
    . as $pod |
    (reduce ($pod.spec.containers // [])[] as $c (zero; add(.; res($c)))) as $apps |
    (reduce ($pod.spec.initContainers // [])[] as $c (
        {reqs: $apps, side: zero, init: zero};
        if $c.restartPolicy == "Always" then
            .reqs = add(.reqs; res($c)) |
            .side = add(.side; res($c)) |
            .init = rmax(.init; .side)
        else
            .init = rmax(.init; add(res($c); .side))
        end
    )) as $acc |
    (rmax($acc.reqs; $acc.init)) as $base |
    ($pod.spec.overhead.cpu | parse_qty("cpu")) as $oc |
    ($pod.spec.overhead.memory | parse_qty("memory")) as $om |
    {
        cpu_req: ($base.cpu_req + $oc),
        mem_req: ($base.mem_req + $om),
        cpu_lim: (if $base.cpu_lim > 0 then $base.cpu_lim + $oc else 0 end),
        mem_lim: (if $base.mem_lim > 0 then $base.mem_lim + $om else 0 end)
    };

($nodes[0].items // []) as $node_items |
($pods[0].items // []) as $pod_items |
($metrics[0] // {}) as $metrics_doc |
(if $util_scope != "off" and (($metrics_doc.items // null) | type) != "array" then
    error("Metrics response has no items")
else
    ($metrics_doc.items // [])
end) as $metric_items |

($node_items | map({
    name: .metadata.name,
    cpu_alloc: (.status.allocatable.cpu | parse_qty("cpu")),
    mem_alloc: (.status.allocatable.memory | parse_qty("memory"))
}) | sort_by(.name)) as $node_list |

($node_list | map({key: .name, value: true}) | from_entries) as $node_set |

([ $pod_items[] |
    select(.status.phase != "Succeeded" and .status.phase != "Failed") |
    select((.spec.nodeName // "") != "") |
    select($node_set[.spec.nodeName] == true) |
    . as $p |
    ($p | pod_resources) as $r |
    ($r + {node: $p.spec.nodeName, name: $p.metadata.name})
]) as $counted |

($counted | group_by(.node) | map({
    key: .[0].node,
    value: (reduce .[] as $p (zero; add(.; $p)))
}) | from_entries) as $by_node |

(if $util_scope == "nodes" then
    [ $metric_items[] | {
        key: .metadata.name,
        value: {
            cpu: (.usage.cpu | parse_qty("cpu")),
            mem: (.usage.memory | parse_qty("memory"))
        }
    } ] | from_entries
elif $util_scope == "pods" then
    ($counted | map({key: .name, value: .node}) | from_entries) as $pod_node |
    [ $metric_items[] |
        select($pod_node[.metadata.name] != null) |
        {
            node: $pod_node[.metadata.name],
            cpu: (reduce (.containers // [])[] as $c (0; . + ($c.usage.cpu | parse_qty("cpu")))),
            mem: (reduce (.containers // [])[] as $c (0; . + ($c.usage.memory | parse_qty("memory"))))
        }
    ] | group_by(.node) | map({
        key: .[0].node,
        value: {cpu: (map(.cpu) | add), mem: (map(.mem) | add)}
    }) | from_entries
else
    {}
end) as $util |

$node_list[] |
    .name as $n |
    ($by_node[$n] // zero) as $s |
    ($util[$n] // {cpu: 0, mem: 0}) as $u |
    [ $n,
      (.cpu_alloc | tostring),
      (.mem_alloc | tostring),
      ($s.cpu_req | tostring),
      ($s.mem_req | tostring),
      ($s.cpu_lim | tostring),
      ($s.mem_lim | tostring),
      ($u.cpu | tostring),
      ($u.mem | tostring)
    ] | @tsv
KAPACITY_JQ

    util_flag=0
    total_flag=0
    [[ "${SHOW_UTIL}" == true ]] && util_flag=1
    [[ "${SHOW_TOTAL}" == true ]] && total_flag=1

    awk -v show_util="${util_flag}" -v total="${total_flag}" -f /dev/stdin "${rows_file}" <<'KAPACITY_AWK' || errorExit "Failed formatting the table"
BEGIN { FS = "\t" }

function pct(part, whole) {
    if (whole <= 0) return 0
    return int((part / whole) * 100)
}

# Quantity.MilliValue is ceil(nanocores / 1e6).
function cpu_milli(nanos,    milli) {
    if (nanos <= 0) return 0
    milli = int(nanos / 1000000)
    if (nanos - (milli * 1000000) > 0.000001) return milli + 1
    return milli
}

# Match kube-capacity: round memory up to the next mebibyte.
function mi_ceil(bytes,    mi, whole, frac) {
    mi = 1048576
    if (bytes <= 0) return 0
    whole = int(bytes / mi)
    frac = bytes - (whole * mi)
    if (frac > 0.000001) return whole + 1
    return whole
}

function fmt_int(n) {
    return sprintf("%.0f", n)
}

function cpu_cell(used_n, alloc_n,    used_m, alloc_m) {
    used_m = cpu_milli(used_n)
    alloc_m = cpu_milli(alloc_n)
    return fmt_int(used_m) "m (" pct(used_m, alloc_m) "%)"
}

function mem_cell(used, alloc,    used_mi) {
    used_mi = mi_ceil(used)
    return fmt_int(used_mi) "Mi (" pct(used, alloc) "%)"
}

# Extra parameters are local in awk.
function add_line(node, cr, cl, cu, mr, ml, mu,    col) {
    rows++
    col = 1
    cell[rows, col++] = node
    cell[rows, col++] = cr
    cell[rows, col++] = cl
    if (show_util) cell[rows, col++] = cu
    cell[rows, col++] = mr
    cell[rows, col++] = ml
    if (show_util) cell[rows, col++] = mu
    ncols = col - 1
}

function print_table(    r, c, val, line, gap) {
    gap = "  "
    for (c = 1; c <= ncols; c++) {
        width[c] = 0
        for (r = 1; r <= rows; r++) {
            if (length(cell[r, c]) > width[c]) width[c] = length(cell[r, c])
        }
    }
    for (r = 1; r <= rows; r++) {
        line = ""
        for (c = 1; c <= ncols; c++) {
            val = cell[r, c]
            if (c < ncols) {
                while (length(val) < width[c]) val = val " "
            }
            if (c > 1) line = line gap
            line = line val
        }
        print line
    }
}

{
    if ($1 == "") next
    count++
    nm[count] = $1
    cpu_a[count] = $2 + 0
    mem_a[count] = $3 + 0
    cpu_r[count] = $4 + 0
    mem_r[count] = $5 + 0
    cpu_l[count] = $6 + 0
    mem_l[count] = $7 + 0
    cpu_u[count] = $8 + 0
    mem_u[count] = $9 + 0
    t_cpu_a += $2
    t_mem_a += $3
    t_cpu_r += $4
    t_mem_r += $5
    t_cpu_l += $6
    t_mem_l += $7
    t_cpu_u += $8
    t_mem_u += $9
}

END {
    add_line("NODE", "CPU REQUESTS", "CPU LIMITS", "CPU UTIL", "MEMORY REQUESTS", "MEMORY LIMITS", "MEMORY UTIL")
    # --total always prints the cluster row, including a cluster with one node.
    if (total || count > 1) {
        add_line("*",
            cpu_cell(t_cpu_r, t_cpu_a),
            cpu_cell(t_cpu_l, t_cpu_a),
            cpu_cell(t_cpu_u, t_cpu_a),
            mem_cell(t_mem_r, t_mem_a),
            mem_cell(t_mem_l, t_mem_a),
            mem_cell(t_mem_u, t_mem_a))
    }
    if (!total) {
        for (i = 1; i <= count; i++) {
            add_line(nm[i],
                cpu_cell(cpu_r[i], cpu_a[i]),
                cpu_cell(cpu_l[i], cpu_a[i]),
                cpu_cell(cpu_u[i], cpu_a[i]),
                mem_cell(mem_r[i], mem_a[i]),
                mem_cell(mem_l[i], mem_a[i]),
                mem_cell(mem_u[i], mem_a[i]))
        }
    }
    print_table()
}
KAPACITY_AWK
}

main () {
    processOptions "$@"
    testConnection
    reportCapacity
}

######### Main #########

main "$@"
