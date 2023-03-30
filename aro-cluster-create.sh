#!/bin/bash

echo "Please ensure that Azure CLI is installed...."

read -p "Do you want to proceed? (yes/no) " yn

case $yn in 
	yes ) echo ok, we will proceed;;
	no ) echo exiting...;
		exit;;
	* ) echo invalid response;
		exit 1;;

esac

echo "Let's check you weren't lying...."

az login

echo "Please provide the following details before continuing:"

echo ""

read -p "Provide Azure Resource Location e.g: eastus: " AZR_RESOURCE_LOCATION

read -p "Provide Azure Resource Group - (already created by RHDPS): " AZR_RESOURCE_GROUP

read -p "Provide Cluster Name: " AZR_CLUSTER

read -p "Provide Redhat Pull Secret (text-only): " AZR_PULL_SECRET

echo "Creating a Virtual Network for the cluster....."

az network vnet create   --address-prefixes 10.0.0.0/22   --name "$AZR_CLUSTER-aro-vnet-$AZR_RESOURCE_LOCATION"   --resource-group $AZR_RESOURCE_GROUP

echo "Creating Control Plane Subnet...."

az network vnet subnet create   --resource-group $AZR_RESOURCE_GROUP   --vnet-name "$AZR_CLUSTER-aro-vnet-$AZR_RESOURCE_LOCATION"   --name "$AZR_CLUSTER-aro-control-subnet-$AZR_RESOURCE_LOCATION"   --address-prefixes 10.0.0.0/23   --service-endpoints Microsoft.ContainerRegistry

echo "Creating Machine Subnet...."

az network vnet subnet create   --resource-group $AZR_RESOURCE_GROUP   --vnet-name "$AZR_CLUSTER-aro-vnet-$AZR_RESOURCE_LOCATION"   --name "$AZR_CLUSTER-aro-machine-subnet-$AZR_RESOURCE_LOCATION"   --address-prefixes 10.0.2.0/23   --service-endpoints Microsoft.ContainerRegistry

echo "Disable Network Policies on the Control Plane Subnet...."

az network vnet subnet update \
  --name "$AZR_CLUSTER-aro-control-subnet-$AZR_RESOURCE_LOCATION" \
  --resource-group $AZR_RESOURCE_GROUP \
  --vnet-name "$AZR_CLUSTER-aro-vnet-$AZR_RESOURCE_LOCATION" \
  --disable-private-link-service-network-policies true

echo "Creating the cluster....(30-45 mins)....."

az aro create \
  --resource-group $AZR_RESOURCE_GROUP \
  --name $AZR_CLUSTER \
  --vnet "$AZR_CLUSTER-aro-vnet-$AZR_RESOURCE_LOCATION" \
  --master-subnet "$AZR_CLUSTER-aro-control-subnet-$AZR_RESOURCE_LOCATION" \
  --worker-subnet "$AZR_CLUSTER-aro-machine-subnet-$AZR_RESOURCE_LOCATION" \
  --pull-secret "$AZR_PULL_SECRET"

echo "Logging into the ARO cluster..."
apiServer=$(az aro show -g $AZURE_RESOURCE_GROUP -n $AZURE_ARC_CLUSTER_RESOURCE_NAME --query apiserverProfile.url -o tsv)
oc login $apiServer -u kubeadmin -p $kubcepass
# Openshift prep before connecting
oc adm policy add-scc-to-user privileged system:serviceaccount:azure-arc:azure-arc-kube-aad-proxy-sa
echo ""

apiServerURI="${apiServer#https://}"
clusterName="${apiServerURI//[.]/-}"
user="kube:admin"
context="default/$clusterName$user"

oc get nodes