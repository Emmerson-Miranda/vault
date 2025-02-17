#!/usr/bin/env bash

function check_hostname(){
    param_hostname="$1"
    cat /etc/hosts | grep $param_hostname
    if [ $? -eq 0 ]; then
        echo 'argocd.owl.com present in /etc/hosts'
    else
        echo "*********************************************************************************"
        echo "ERROR: Pre-requisite not satisfied!"
        echo "Add the hostname $param_hostname in /etc/hosts pointing out to your IP 192.168.x.y"
        echo "*********************************************************************************"
        exit -1
    fi
}

function check_file_exist(){
    filename="$1"
    echo "Checking file exists $filename"
    if ! test -f "$filename"; then
        echo "*********************************************************************************"
        echo "ERROR: Required file does not exists: $filename"
        echo "*********************************************************************************"
        exit -1
    fi
}

function kubectl_wait_pod(){
    param_namespace="$1"
    param_selector="$2"
    param_type="$3"
    default_type="Ready"
    type="${param_type:-$default_type}"
    
    jsonpath="jsonpath={..status.conditions[?(@.type==\"$type\")].status}"
    #echo "$jsonpath"
    counter=0
    while [[ $(kubectl -n $param_namespace get pods -l $param_selector -o $jsonpath) != "True" ]]; do
        let counter++
        echo "Waiting for pod $param_selector to be $type - Try number: $counter"
        sleep 2
    done
}

# Create a KinD cluster to deploy ArgoCD
function create_cluster(){
    cluster_name_expected="$1"
    param_folder="$2"
    echo "------------------------ create_cluster $cluster_name_expected ---------------------------------------------------"
    cluster=$(kubectl config current-context)
    
    if [ "$cluster" = "kind-$cluster_name_expected" ]; then
        echo "Cluster $cluster already present."
        return
    else
        echo "Creating KinD cluster."
    fi

    currentfolder=$(pwd)
    basefolder="${param_folder:-$currentfolder}"
    echo "KinD configuration base folder: $basefolder"

    # Creating KinD cluster
    check_file_exist $basefolder/kind/kind-cluster.yaml
    kind create cluster --config $basefolder/kind/kind-cluster.yaml > /dev/null

    # Deploying KinD ingress
    echo "Creating Ingress Controller."
    check_file_exist $basefolder/kind/nginx-ingress-kind-deploy.yaml
    kubectl apply -f $basefolder/kind/nginx-ingress-kind-deploy.yaml > /dev/null
    kubectl_wait_pod "ingress-nginx" "app.kubernetes.io/component=controller"
    
}

function install_hashicorp_vault(){
    echo "--------------------- install_hashicorp_vault ------------------------------------------------------"
    param_folder="$1"
    currentfolder=$(pwd)
    basefolder="${param_folder:-$currentfolder}"
    mkdir -p $basefolder
    #echo "Base folder: $basefolder"

    phase=$(kubectl -n vault get po vault-0 -o=jsonpath={.status.phase})
    if [ "$phase" = "Running" ]; then
        roottoken=$(cat $basefolder/tmp/root-token-vault.txt)
        #echo "Hashicorp Vault already present. Admin Token: $roottoken"
        echo $roottoken
    else
        #echo "Deploying Hashicorp Vault ..."

        helm repo add hashicorp https://helm.releases.hashicorp.com
        helm repo update > /dev/null
        check_file_exist $basefolder/values/hashicorp-vault-values.yaml
        helm upgrade vault hashicorp/vault -i -n vault -f $basefolder/values/hashicorp-vault-values.yaml --create-namespace

        kubectl_wait_pod "vault" "app.kubernetes.io/name=vault" "PodReadyToStartContainers"
        sleep 5

        kubectl -n vault exec vault-0 -- vault operator init > $basefolder/tmp/vault-operator-init.txt
        key1=$(cat $basefolder/tmp/vault-operator-init.txt | grep "Unseal Key 1" | cut -d' ' -f4-)
        key2=$(cat $basefolder/tmp/vault-operator-init.txt | grep "Unseal Key 2" | cut -d' ' -f4-)
        key3=$(cat $basefolder/tmp/vault-operator-init.txt | grep "Unseal Key 3" | cut -d' ' -f4-)
        roottoken=$(cat $basefolder/tmp/vault-operator-init.txt | grep "Initial Root Token:" | cut -d' ' -f4-)
        echo $roottoken > $basefolder/tmp/root-token-vault.txt

        kubectl -n vault exec vault-0 -- vault operator unseal $key1 
        kubectl -n vault exec vault-0 -- vault operator unseal $key2
        kubectl -n vault exec vault-0 -- vault operator unseal $key3
        kubectl -n vault exec vault-0 -- vault login $roottoken

        kubectl -n vault exec vault-0 -- vault secrets enable kv-v2
        kubectl -n vault exec vault-0 -- vault secrets list
        kubectl -n vault exec vault-0 -- vault kv put kv-v2/my-secrets/secret1 username=emmerson1 password=mypassword1
        kubectl -n vault exec vault-0 -- vault kv put kv-v2/my-secrets/secret2 username=emmerson2 password=mypassword2
        kubectl -n vault exec vault-0 -- vault kv put kv-v2/my-secrets/secret3 username=emmerson3 password=mypassword3
        echo $roottoken
    fi
}
