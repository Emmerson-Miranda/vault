#!/usr/bin/env bash
#ifconfig | grep "192.168" 
mkdir -p tmp

resources=$(cd ./resources; pwd)
source $resources/scripts/cluster-create.sh

cluster_name=$(yq ".name" $resources/kind/kind-cluster.yaml)

create_cluster $cluster_name $resources
install_hashicorp_vault $resources
