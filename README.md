# Kubernetes Scripts
A collection of scripts and commands for various tasks in [Kubernetes](https://kubernetes.io/).<br>
These were all written during my work with Kubernetes on various project. Enjoy and share. Contributions are more than welcome!

## For agents
Coding agents working in this repo should follow [AGENTS.md](AGENTS.md).
It says which script to run, and which manifests to apply only after an explicit ask.
This file stays the catalog and the command cookbook.

## Requirements
* `bash` (3.2 or higher, so works on macOS out of the box)
* [`kubectl`](https://kubernetes.io/docs/tasks/tools/) configured with access to your cluster
* `jq` (for [getResourcesCSV.sh](getResourcesCSV.sh) and [kapacity.sh](kapacity.sh))
* [metrics-server](https://github.com/kubernetes-sigs/metrics-server) in the cluster (only for the scripts using `kubectl top`, and for `kapacity.sh --util`)

## Usage
Each script has a `usage` function. See usage with
```shell script
<script> --help
```

All scripts behave the same way:
* `--help` prints the usage to stdout and exits with `0`. An unknown option prints the usage to stderr and exits with `1`.
* Errors are printed to stderr and the script exits with `1`. [podReady.sh](podReady.sh) also exits with `1` when the pod is not ready.
* Data (CSV and results) is printed to stdout. Progress and warning messages go to stderr, so output can be piped safely.
* CPU is reported in cores and memory in GiB in all the CSV outputs.
* Namespace is selected with `-n | --namespace`. Scripts that report on a cluster default to all namespaces,
  and scripts acting on specific pods default to the `default` namespace (except [runCommandOnPods.sh](runCommandOnPods.sh), which requires it explicitly).

## Scripts
* [countPodsAndContainerPerNodeCSV.sh](countPodsAndContainerPerNodeCSV.sh): Count number of pods and containers per node. Print in CSV format.
* [findEmptyNamespaces.sh](findEmptyNamespaces.sh): Loop over all namespaces in a cluster and find empty ones.
* [getPodsLoad.sh](getPodsLoad.sh): Get formatted results of pods in a namespace underlying node's load average (using cat /proc/loadavg).
* [getPodsTopCSV.sh](getPodsTopCSV.sh): Get a pod's cpu and memory usage (optionally per container) written as CSV formatted file.
* [getResourcesCSV.sh](getResourcesCSV.sh): Get all pods resources requests, limits and actual usage per container in a CSV format with values normalized.
* [kapacity.sh](kapacity.sh): Node and cluster CPU and memory requests, limits, and (with `--util`) live usage, as a table. CPU is in millicores and memory is in MiB. Inspired by [kube-capacity](https://github.com/robscott/kube-capacity).
* [getRestartingPods.sh](getRestartingPods.sh): Get all pods (all or single namespace) that have restarts detected in one or more containers. Formatted in CSV.
* [podReady.sh](podReady.sh): Simple script to check if pod is really ready. Check status is 'Running' and that all containers are ready. Returns 0 if ready. Returns 1 if not ready.
* [getNodesLoadCSV.sh](getNodesLoadCSV.sh): Traverse over the `kube-proxy` pods to get the nodes load average and number of CPUs in a CSV format. Will also mark high load node with big `YES` in the output.
* [runCommandOnPods.sh](runCommandOnPods.sh): Run a command on a list of pods (selected by a regex on the pod name).
* [canIdo.sh](canIdo.sh): Check all or some permissions current user has in a namespace on all or some resources using the `kubectl auth can-i` command.

## YAML
* [memory.yaml](yaml/memory.yaml): A pod using a given block of memory for a given time.<br>
* [podWithTools.yaml](yaml/podWithTools.yaml): A pod with some basic tools (`vi` and `curl`) for easy debugging.<br>
* [podWithHostFS.yaml](yaml/podWithHostFS.yaml): A pod with the host root file system mounted into it.<br>
* [podmanPod.yaml](yaml/podmanPod.yaml): A pod with [podman](https://podman.io/) in it.<br>
* [superPod.yaml](yaml/superPod.yaml): A pod with the host file system and process IDs mounted for allowing to manipulate the host system and restarting kubelet.<br>
  **WARNING:** There is danger of corrupting your Kubernetes host. Use with extra care!
* [kind-config.yaml](yaml/kind-config.yaml): An example [kind](https://kind.sigs.k8s.io/) configuration for a multi node K8s cluster
* [metrics-server-patch.yaml](yaml/metrics-server-patch.yaml): A patch for running `metrics-server` on Docker Desktop or Kind. See [Metrics Server](#metrics-server-in-kubernetes-on-docker-desktop-or-kind-for-mac).

## Security
* `podWithHostFS.yaml`, `superPod.yaml` and `podmanPod.yaml` run **privileged** pods, with access to the node (host file system, host PID namespace).
  Anyone who can `exec` into them has root on the node and can reach the kubelet credentials and the secrets of all pods on it.
  Use them only on disposable or development clusters, and delete them as soon as you are done.
  Clusters enforcing [Pod Security Standards](https://kubernetes.io/docs/concepts/security/pod-security-standards/) will (and should) reject them.
* `memory.yaml` uses `ubuntu:26.04` and installs `curl` and `vim` at startup, then downloads a script from GitHub. `podWithHostFS.yaml` also downloads scripts at startup. The URLs are pinned to a commit. Review the scripts before moving the pin.
  `podWithTools.yaml` runs the JFrog CLI installer with `curl | sh`.
* `runCommandOnPods.sh`, `getPodsLoad.sh` and `getNodesLoadCSV.sh` use `kubectl exec`, so they run commands inside your pods. Double check the namespace and the cluster context first.
* `canIdo.sh` and the other read scripts are read-only, but their CSV output (names of namespaces, pods and images) may be sensitive. Mind where you store it.
* Secrets: commands below that print or copy secrets leave values in your terminal scrollback and shell history. Avoid them on shared machines.
* `--kubelet-insecure-tls` (metrics-server section) disables the verification of kubelet certificates. Use only on local clusters.
* `superPod.yaml` pulls an image from `eldada.jfrog.io`, a personal mirror that is not versioned in this repo. Replace it with an image you trust (and pin by tag or digest) for your own use.

## Commands
### Kubectl
#### See all cluster nodes load (top)
```shell script
kubectl top nodes
```

#### Get cluster events
```shell script
# All cluster
kubectl get events

# Specific namespace events
kubectl get events --namespace=kube-system
```

#### Get all cluster nodes IPs and names
```shell script
# Single call to K8s API
kubectl get nodes -o wide

# A loop for more flexibility
for n in $(kubectl get nodes -o name); do \
  echo -e "\nNode ${n}"; \
  kubectl get "${n}" -o jsonpath='{.status.addresses}'; \
done
```

#### See all cluster nodes CPU and Memory requests and limits
```shell script
# With node names
kubectl describe nodes | grep -A 3 "Name:\|Resource .*Requests .*Limits" | grep -v "Roles:"

# Just the resources
kubectl describe nodes | grep -A 3 "Resource .*Requests .*Limits"
``` 

##### Using kapacity.sh
[kapacity.sh](kapacity.sh) is inspired by [kube-capacity](https://github.com/robscott/kube-capacity). It prints that project's basic node table with kubectl, so there is nothing extra to install. CPU is in millicores and memory is in MiB. Percentages are of allocatable. With more than one node, the first row (`*`) is the cluster total. `--total` prints only that row.
```shell script
# Requests and limits
./kapacity.sh

# Requests, limits, and live usage (needs metrics-server)
./kapacity.sh --util

# Cluster total only
./kapacity.sh --total

# Roll over all clusters in your kubectl contexts
for a in $(kubectl ctx); do echo -e "\n---$a"; kubectl ctx $a; ./kapacity.sh; done

# Cluster total for each context
for a in $(kubectl ctx); do echo -e "\n---$a"; kubectl ctx $a; ./kapacity.sh --total; done
```
The upstream `kube-capacity` CLI still adds `--available`, pod and container rows, sorting, and label or taint filters. Install it from that project if you need those.

#### Get all labels attached to all pods in a namespace
```shell script
for a in $(kubectl get pods -n namespace1 -o name); do \
  echo -e "\nPod ${a}"; \
  kubectl -n namespace1 describe ${a} | awk '/Labels:/,/Annotations/' | sed '/Annotations/d'; \
done
```

#### Forward local port to a pod or service
```shell script
# Forward localhost port 8080 to a specific pod exposing port 8080
kubectl port-forward -n namespace1 web 8080:8080

# Forward localhost port 8080 to a specific web service exposing port 80
kubectl port-forward -n namespace1 svc/web 8080:80
```

#### Port forwarding
* A great tool for port forwarding all services in a namespace + adding aliases to `/etc/hosts` is [kubefwd](https://github.com/txn2/kubefwd).
Note that this requires root or sudo to allow temporary editing of `/etc/hosts`.
```shell script
# Port forward all service in namespace1
kubefwd svc -n namespace1
```

#### Extract and decode a secret's value
```shell script
# Get the value of the postgresql password
kubectl get secret -n namespace1 my-postgresql -o jsonpath="{.data.postgres-password}" | base64 --decode
```

#### Copy secret from `namespace1` to `namespace2`
Requires `jq`. Removes the namespace and the server generated fields so the secret can be created in the other namespace.
```shell script
kubectl get secret my-secret --namespace namespace1 -o json \
  | jq 'del(.metadata.namespace, .metadata.uid, .metadata.resourceVersion, .metadata.creationTimestamp, .metadata.ownerReferences, .metadata.managedFields)' \
  | kubectl apply --namespace=namespace2 -f -
```

#### Create an Ubuntu pod
A one liner to create an Ubuntu pod that will just wait forever. 
```shell script
# Create the pod
cat <<ZZZ | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: my-ubuntu-pod
spec:
  containers:
  - name: my-ubuntu-container
    image: ubuntu:24.04
    command:
    - 'bash'
    - '-c'
    - 'while true; do date; sleep 60; done'
ZZZ

# Shell into the pod
kubectl exec -it my-ubuntu-pod -- bash

# Delete the pod once done
kubectl delete pod my-ubuntu-pod
```

#### Start a shell in a temporary pod
Note - Pod will terminate once exited
```shell script
# Ubuntu
kubectl run my-ubuntu --rm -i -t --restart=Never --image ubuntu:24.04 -- bash

# Rocky Linux (CentOS replacement)
kubectl run my-rocky --rm -i -t --restart=Never --image rockylinux:9 -- bash

# Alpine
kubectl run my-alpine --rm -i -t --restart=Never --image alpine -- sh

# Busybox
kubectl run my-busybox --rm -i -t --restart=Never --image busybox -- sh
```

#### Get formatted list of containers and container images
Useful for listing all running containers in your cluster
```shell script
# Example 1 - just the container names
kubectl get pods -A -o jsonpath='{..containers[*].name}' | tr -s ' ' '\n'
# With sorting and unique names
kubectl get pods -A -o jsonpath='{..containers[*].name}' | tr -s ' ' '\n' | sort | uniq

# Example 2 - container images and tags
kubectl get pods -A -o=jsonpath='{..containers[*].image}' | tr -s ' ' '\n'
# With sorting and unique names
kubectl get pods -A -o=jsonpath='{..containers[*].image}' | tr -s ' ' '\n' | sort | uniq

# Example 3 - pod and its container images
kubectl get pods -A -o=jsonpath='{range .items[*]}{"\n"}{.metadata.name}{":\n"}{range .spec.containers[*]}{.name},{.image}{"\n"}{end}{end}'

# Example 4 - pod and its container images with their resources requests (cpu and memory)
kubectl get pods -A -o=jsonpath='{range .items[*]}{"\n"}{.metadata.name}{":\n"}{range .spec.containers[*]}{.name},{.image}{.resources.requests.cpu},{.resources.requests.memory}{"\n"}{end}{end}'

```
Look into [a few more examples](https://kubernetes.io/docs/tasks/access-application-cluster/list-all-running-container-images) of listing containers

#### Get list of pods sorted by restart count
* Option 1 for all pods (Taken from [kubectl cheatsheet](https://kubernetes.io/docs/reference/kubectl/cheatsheet/#viewing-finding-resources))
```shell script
kubectl get pods -A --sort-by='.status.containerStatuses[0].restartCount'
```

* Option 2 with a filter, and a CSV friendly output
```shell script
kubectl get pods -A | grep my-app | awk '{print $5 ", " $1 ", " $6}'  | sort -n -r
```

#### Get current replica count on all HPAs (Horizontal Pod Autoscaling)
```shell script
kubectl get hpa -A -o=custom-columns=NAME:.metadata.name,REPLICAS:.status.currentReplicas | sort -k2 -n -r
```

#### List non-running pods
```shell script
kubectl get pods -A --no-headers | grep -v Running | grep -v Completed
```

#### Top Pods by CPU or memory usage
```shell script
# Top 20 pods by highest CPU usage
kubectl top pods -A --sort-by=cpu | head -20

# Top 20 pods by highest memory usage
kubectl top pods -A --sort-by=memory | head -20

# Roll over all kubectl contexts and get top 20 CPU users
for a in $(kubectl ctx); do echo -e "\n---$a"; kubectl ctx $a; kubectl top pods -A --sort-by=cpu | head -20; done
```

#### Debugging Pods and Nodes
This section is based on [debugging pods using ephemeral containers](https://kubernetes.io/docs/tasks/debug/debug-application/debug-running-pod/#ephemeral-container-example)
and [kubectl node debug](https://kubernetes.io/docs/tasks/debug/debug-cluster/kubectl-node-debug/)

##### Pod Debugging
```shell script
# Attach an ephemeral container to an existing container in a pod for debugging
kubectl debug -it my-pod --image=ubuntu:24.04 --target=my-container
```

##### Node Debugging
```shell script
# Debug a node with a new pod attached to it
# IMPORTANT to delete the pods after exiting it. It will not be deleted automatically (although it will be in the "Completed" state)
kubectl debug node/<mynode> -it --image=ubuntu:24.04
# The node root file system is mounted in the pod at /host
```
### Helm

#### Helm template
View the templates generated by `helm install`. Useful for seeing the actual templates generated by helm before deploying.<br>
Can also be used for deploying the generated templates with `kubectl apply` (for example, when you can't run `helm install`)
```shell script
helm template <chart>
```

#### Debug helm install
* Debug a `helm install`. Useful for seeing the actual values resolved by helm before deploying
```shell script
helm install --debug --dry-run <chart>
```

### Rolling restarts
Roll a restart across all resources managed by a Deployment, DaemonSet or StatefulSet with **zero downtime**<br>
**IMPORTANT**: For a Deployment or StatefulSet, a zero downtime is possible only if initial replica count is **higher than 1**!
```shell script
# Deployment
kubectl -n <namespace> rollout restart deployment <deployment-name>

# DaemonSet
kubectl -n <namespace> rollout restart daemonset <daemonset-name>

# StatefulSet
kubectl -n <namespace> rollout restart statefulsets <statefulset-name>
```

### Mark Nodes with some roles for visibility (ex. EKS nodes marked with the LifeCycle,NodeType)
* Most use of it can be gained with some GUI client (Lens), still "k get nodes" shows ROLE fields as well
```shell
for n in $(kubectl get nodes -o 'jsonpath={.items[*].metadata.name}') ; do
  lb=""
  for a in $(kubectl label --list nodes $n | sort | grep -e NodeType -e lifecycle | cut -d= -f 2); do
    lb="${lb}$a"
  done
  kubectl label nodes $n node-role.kubernetes.io/$lb=
done
```

## A Multi Node Kubernetes cluster in Mac with Kind
To run a multi node Kubernetes cluster in Mac with [Kind](https://kind.sigs.k8s.io/), do the following (assuming Docker Desktop is already installed)
- Install `kind` as described in [kind installation](https://kind.sigs.k8s.io/docs/user/quick-start/#installation)
- Start a local, three worker nodes cluster using the [kind-config.yaml](yaml/kind-config.yaml) config file
```shell
kind create cluster --config yaml/kind-config.yaml --name demo
```

Delete the cluster with
```shell
kind delete cluster --name demo
```

## Metrics Server in Kubernetes on Docker Desktop or Kind for Mac
To get around issue with certificates in your local Docker Desktop or Kind Kubernetes

Install a `metrics-server`
```shell
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
```

Add the `--kubelet-insecure-tls` argument to the `metrics-server` Deployment. This adds just one argument and keeps all the rest as shipped with the installed version (recommended)
```shell
kubectl patch deployment metrics-server -n kube-system --type=json \
  -p '[{"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--kubelet-insecure-tls"}]'
```

**OR** Replace the whole `args` list with [metrics-server-patch.yaml](yaml/metrics-server-patch.yaml). This must match the args of the installed version (`--secure-port` is `10250` since metrics-server v0.7)
```shell
kubectl patch deployment metrics-server -n kube-system --patch-file yaml/metrics-server-patch.yaml
```

**WARNING:** `--kubelet-insecure-tls` disables the verification of the kubelet certificates. Use it only in local, development clusters.

Verify it works
```shell
kubectl top nodes
```

### Resources
Most of the code above is self experimenting and reading the docs. Some are copied and modified to my needs from other resources...
* https://kubernetes.io/docs/reference/kubectl/cheatsheet/
* https://medium.com/flant-com/kubectl-commands-and-tips-7b33de0c5476
* https://github.com/robscott/kube-capacity
