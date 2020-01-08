# Kubernetes Scripts
A collection of scripts for various tasks in [Kubernetes](https://kubernetes.io/).

## Usage
Each script has a `usage` function. See usage with
```shell script
$ <script> --help
```

## Scripts
* [getResourcesCSV.sh](getResourcesCSV.sh): Get all pods resources requests and limits per container in a CSV format with values normalized. 
CSV format is very automation friendly and is great for pasting in an Excel or Google sheet for further processing.
* [getRestartingPods.sh](getRestartingPods.sh): Get all pods (all or single namespace) that have restarts detected in one or more containers. Formatted in CSV.
* [podReady](podReady.sh): Simple script to check if pod is really ready. Check status is 'Running' and that all containers are ready.
Return 1 is not ready. Return 0 is ready.