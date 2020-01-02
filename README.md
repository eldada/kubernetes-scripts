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
