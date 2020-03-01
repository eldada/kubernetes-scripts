# Kubernetes Scripts
A collection of scripts for various tasks in [Kubernetes](https://kubernetes.io/).

## Usage
Each script has a `usage` function. See usage with
```shell script
$ <script> --help
```

## Scripts
* [getPodsTopCSV.sh](getPodsTopCSV.sh): Get a pod's cpu and memory usage (optionally per container) written as CSV formatted file.
* [getResourcesCSV.sh](getResourcesCSV.sh): Get all pods resources requests and limits per container in a CSV format with values normalized. 
CSV format is very automation friendly and is great for pasting in an Excel or Google sheet for further processing.
* [getRestartingPods.sh](getRestartingPods.sh): Get all pods (all or single namespace) that have restarts detected in one or more containers. Formatted in CSV.
* [podReady](podReady.sh): Simple script to check if pod is really ready. Check status is 'Running' and that all containers are ready.
Returns 0 if ready. Returns 1 if not ready.

## One liners
* Get list of container images in pods. Useful for listing all running containers in your cluster.
```shell script
kubectl get pod --all-namespaces -o=jsonpath='{range .items[*]}{.metadata.namespace}, {.metadata.name}, {.spec.containers[].image}{"\n"}'
```
