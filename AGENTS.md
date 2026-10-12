# Agent guide

This repo is a kubectl toolkit. Prefer the scripts below over ad-hoc kubectl for the tasks they cover. [README.md](README.md) is the catalog and the command cookbook for everything else.

Run scripts from the repo root. Read flags with `<script> --help` before calling one. Pass every value with its flag.

## Before any cluster call

1. Run `kubectl config current-context` and name that cluster before you call kubectl or a script.
2. Stay on that context. Switch context or namespace only when the user names the target.
3. Show the exact command, namespace, and context before any script that execs into pods, and before `kubectl apply`, `delete`, `rollout`, or `debug`.

The README examples that iterate `kubectl ctx` are for a person at the keyboard. Leave the current context in place.

## How scripts behave

- `--help` prints usage to stdout and exits 0. An unknown option prints usage to stderr and exits 1.
- Data goes to stdout. Progress, warnings, and errors go to stderr.
- CSV CPU values are cores. CSV memory values are GiB.
- `jq` is required for `getResourcesCSV.sh` and `kapacity.sh`. Scripts that call `kubectl top`, and `kapacity.sh --util`, need metrics-server.
- `podReady.sh` exits 0 when the pod is Running and every container is ready, and 1 otherwise.

Cluster-wide scripts default to all namespaces. Scripts that act on specific pods default to the `default` namespace. `runCommandOnPods.sh` requires `--namespace`.

## Which script to run

| Task | Command |
|---|---|
| Requests, limits, and live usage per container | `./getResourcesCSV.sh --console-only` |
| Node and cluster requests, limits, and live usage | `./kapacity.sh` or `./kapacity.sh --util` |
| Sample one pod's CPU and memory | `./getPodsTopCSV.sh --namespace <ns> --pod <pod> --duration <seconds>` |
| Pods with container restarts | `./getRestartingPods.sh` |
| Whether a pod is actually ready | `./podReady.sh --namespace <ns> --pod <pod>` |
| Namespaces with no workloads | `./findEmptyNamespaces.sh` |
| Pod and container counts per node | `./countPodsAndContainerPerNodeCSV.sh` |
| Node load average and CPU count | `./getNodesLoadCSV.sh` |
| Load of the node a set of pods sits on | `./getPodsLoad.sh --namespace <ns>` |
| What the current identity can do | `./canIdo.sh --namespace <ns>` |
| One command on many pods | `./runCommandOnPods.sh --namespace <ns> --exec "<cmd>"` |

Narrow a cluster script with `--namespace` when the user names one. `canIdo.sh` defaults to namespace `default` and to every verb from `get` through `delete`. It only checks; it does not perform those verbs. Pass `--actions` and `--resources` to narrow it.

`getPodsTopCSV.sh` samples until `--duration` seconds have elapsed. Duration `0` (the default) loops until you stop it, so always pass `--duration`. It also writes a CSV. Set `--output` to a path the user asked for, or under `/tmp`, so a timestamped file is not left in the repo.

`getResourcesCSV.sh` writes `resources.csv` in the working directory. Pass `--console-only` unless the user asked for a file.

`kapacity.sh` prints a table. CPU is millicores and memory is MiB. `--util` reads the metrics API. With more than one node, the first row `*` is the cluster total. `--total` prints only that row. Narrow it with `--namespace`. It is inspired by https://github.com/robscott/kube-capacity.

`getNodesLoadCSV.sh` execs into the `kube-proxy` pods in `kube-system`. `getPodsLoad.sh` execs `cat /proc/loadavg` into the selected pods (default namespace `default`; limit them with `--include`). `runCommandOnPods.sh` runs `--exec` directly, not through a shell. Pipes need `--exec "sh -c '...'"`; limit pods with `--pods <regex>`.

`findEmptyNamespaces.sh` treats a namespace as empty when it has no pods, jobs, cronjobs, deployments, daemonsets, or statefulsets.

For a task with no script, use kubectl. The Commands section of the README is the cookbook.

## Manifests

| File | Use |
|---|---|
| `yaml/kind-config.yaml` | Local Kind cluster with three workers |
| `yaml/metrics-server-patch.yaml` | metrics-server on Docker Desktop or Kind. Prefer the JSON patch in the README, which adds only `--kubelet-insecure-tls`. Use that flag on local clusters. |
| `yaml/podWithTools.yaml` | Debug pod with `vi` and `curl` |
| `yaml/memory.yaml` | Hold a block of memory for a fixed time |

Apply `yaml/superPod.yaml`, `yaml/podWithHostFS.yaml`, or `yaml/podmanPod.yaml` only after the user explicitly asks, and only on a cluster they have called disposable. Delete the pod when the task is done. These run privileged and mount the node. Anyone who can exec into them has root on that node.

`memory.yaml` uses `ubuntu:26.04`, installs `curl` and `vim` at startup, and downloads a script pinned to a commit. `podWithHostFS.yaml` also downloads pinned scripts. `superPod.yaml` pulls from `eldada.jfrog.io`; replace that image when it does not pull.

Decode or copy a secret only when the user asks for that secret.

## Editing these scripts

Keep them compatible with bash 3.2 (macOS). Follow the existing `usage` and `errorExit` functions. Keep data on stdout and errors on stderr. Leave `set -xv` commented.
