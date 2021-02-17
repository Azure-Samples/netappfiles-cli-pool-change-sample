#!/bin/bash
set -euo pipefail

# Mandatory variables for ANF resources
# Change variables according to your environment 
SUBSCRIPTION_ID="Subscription ID"
LOCATION="CentralUS"
RESOURCEGROUP_NAME="My-rg"
VNET_NAME="sourcevnet"
SUBNET_NAME="sourcesubnet"
NETAPP_ACCOUNT_NAME="netapptestaccount"
PRIMARY_NETAPP_POOL_NAME="pool1"
PRIMARY_SERVICE_LEVEL="Premium"
SECONDARY_NETAPP_POOL_NAME="pool2"
SECONDARY_SERVICE_LEVEL="Standard"
NETAPP_POOL_SIZE_TIB=4
NETAPP_VOLUME_NAME="netappvolume"
NETAPP_VOLUME_SIZE_GIB=100
PROTOCOL_TYPE="NFSv4.1"
SHOULD_CLEANUP="false"

# Exit error code
ERR_ACCOUNT_NOT_FOUND=100

# Utils Functions
display_bash_header()
{
    echo "----------------------------------------------------------------------------------------------------------------------"
    echo "Azure NetApp Files CLI NFS Sample  - Sample Bash script that perform Capacity pool change on Azure NetApp Files Volume - NFSv4.1 protocol"
    echo "----------------------------------------------------------------------------------------------------------------------"
}

display_cleanup_header()
{
    echo "----------------------------------------"
    echo "Cleaning up Azure NetApp Files Resources"
    echo "----------------------------------------"
}

display_message()
{
    time=$(date +"%T")
    message="$time : $1"
    echo $message
}

#----------------------
# ANF CRUD functions
#----------------------

# Create Azure NetApp Files Account
create_or_update_netapp_account()
{    
    local __resultvar=$1
    local _NEW_ACCOUNT_ID=""

    _NEW_ACCOUNT_ID=$(az netappfiles account create --resource-group $RESOURCEGROUP_NAME \
        --name $NETAPP_ACCOUNT_NAME \
        --location $LOCATION | jq -r ".id")

    if [[ "$__resultvar" ]]; then
        eval $__resultvar="'${_NEW_ACCOUNT_ID}'"
    else
        echo "${_NEW_ACCOUNT_ID}"
    fi
}

# Create Azure NetApp Files Capacity Pool
create_or_update_netapp_pool()
{
    local __resultvar=$1
    local _POOL_NAME=$2
    local _SERVICE_LEVEL=$3
    local _NEW_POOL_ID=""

    _NEW_POOL_ID=$(az netappfiles pool create --resource-group $RESOURCEGROUP_NAME \
        --account-name $NETAPP_ACCOUNT_NAME \
        --name $_POOL_NAME \
        --location $LOCATION \
        --size $NETAPP_POOL_SIZE_TIB \
        --service-level $_SERVICE_LEVEL | jq -r ".id")

    if [[ "$__resultvar" ]]; then
        eval $__resultvar="'${_NEW_POOL_ID}'"
    else
        echo "${_NEW_POOL_ID}"
    fi
}

# Create Azure NetApp Files Volume
create_or_update_netapp_volume()
{
    local __resultvar=$1
    local _NEW_VOLUME_ID=""

    _NEW_VOLUME_ID=$(az netappfiles volume create --resource-group $RESOURCEGROUP_NAME \
        --account-name $NETAPP_ACCOUNT_NAME \
        --file-path $NETAPP_VOLUME_NAME \
        --pool-name $PRIMARY_NETAPP_POOL_NAME \
        --name $NETAPP_VOLUME_NAME \
        --location $LOCATION \
        --service-level $PRIMARY_SERVICE_LEVEL \
        --usage-threshold $NETAPP_VOLUME_SIZE_GIB \
        --vnet $VNET_NAME \
        --subnet $SUBNET_NAME \
        --protocol-types $PROTOCOL_TYPE | jq -r ".id")

    if [[ "$__resultvar" ]]; then
        eval $__resultvar="'${_NEW_VOLUME_ID}'"
    else
        echo "${_NEW_VOLUME_ID}"
    fi      
}

# Change pool for Azure NetApp Files Volume
update_netapp_volume_pool()
{
    local _NEW_POOL_ID=$1
    
    az netappfiles volume pool-change --resource-group $RESOURCEGROUP_NAME \
        --account-name $NETAPP_ACCOUNT_NAME \
        --pool-name $PRIMARY_NETAPP_POOL_NAME \
        --name $NETAPP_VOLUME_NAME \
        --new-pool-resource-id $_NEW_POOL_ID
}

#---------------------------
# ANF cleanup functions
#---------------------------

# Delete Azure NetApp Files Account
delete_netapp_account()
{
    az netappfiles account delete --resource-group $RESOURCEGROUP_NAME \
        --name $NETAPP_ACCOUNT_NAME    
}

# Delete both Primary and Secondary Azure NetApp Files Capacity Pool
delete_netapp_pool()
{
    az netappfiles pool delete --resource-group $RESOURCEGROUP_NAME \
        --account-name $NETAPP_ACCOUNT_NAME \
        --name $PRIMARY_NETAPP_POOL_NAME
        
    az netappfiles pool delete --resource-group $RESOURCEGROUP_NAME \
        --account-name $NETAPP_ACCOUNT_NAME \
       --name $SECONDARY_NETAPP_POOL_NAME        
}

# Delete Azure NetApp Files Volume
delete_netapp_volume()
{
    az netappfiles volume delete --resource-group $RESOURCEGROUP_NAME \
        --account-name $NETAPP_ACCOUNT_NAME \
        --pool-name $SECONDARY_NETAPP_POOL_NAME \
        --name $NETAPP_VOLUME_NAME
}

#---------------------------------
# Waiting for resources functions
#---------------------------------

# Wait for resources to succeed 
wait_for_resource()
{
    local _RESOURCE_TYPE=$1
    local _POOL_TYPE=$2

    for number in {1..60}; do
        sleep 10
        if [[ "${_RESOURCE_TYPE}" == "account" ]]; then
            _account_status=$(az netappfiles account show --resource-group $RESOURCEGROUP_NAME --name $NETAPP_ACCOUNT_NAME | jq -r ".provisioningState")
            if [[ "${_account_status,,}" == "succeeded" ]]; then
                break
            fi        
        elif [[ "${_RESOURCE_TYPE}" == "pool" ]]; then
            if [[ "${_POOL_TYPE}" == "primary" ]]; then
                _primary_pool_status=$(az netappfiles pool show --resource-group $RESOURCEGROUP_NAME --account-name $NETAPP_ACCOUNT_NAME --name $PRIMARY_NETAPP_POOL_NAME | jq -r ".provisioningState")
                if [[ "${_primary_pool_status,,}" == "succeeded" ]]; then
                    break
                fi
            else
                _secondary_pool_status=$(az netappfiles pool show --resource-group $RESOURCEGROUP_NAME --account-name $NETAPP_ACCOUNT_NAME --name $SECONDARY_NETAPP_POOL_NAME | jq -r ".provisioningState")
                if [[ "${_secondary_pool_status,,}" == "succeeded" ]]; then
                    break
                fi
            fi                    
        else
            if [[ "${_POOL_TYPE}" == "primary" ]]; then
                _primary_volume_status=$(az netappfiles volume show --resource-group $RESOURCEGROUP_NAME --account-name $NETAPP_ACCOUNT_NAME --pool-name $PRIMARY_NETAPP_POOL_NAME --name $NETAPP_VOLUME_NAME | jq -r ".provisioningState")
                if [[ "${_primary_volume_status,,}" == "succeeded" ]]; then
                    break
                fi
            else
                _secondary_volume_status=$(az netappfiles volume show --resource-group $RESOURCEGROUP_NAME --account-name $NETAPP_ACCOUNT_NAME --pool-name $SECONDARY_NETAPP_POOL_NAME --name $NETAPP_VOLUME_NAME | jq -r ".provisioningState")
                if [[ "${_secondary_volume_status,,}" == "succeeded" ]]; then
                    break
                fi
            fi
        fi        
    done   
}

#Wait for resources to get fully deleted
wait_for_NO_RESOURCE()
{
    local _RESOURCE_TYPE=$1
    local _POOL_TYPE=$2

    for number in {1..60}; do
        sleep 10
        if [[ "${_RESOURCE_TYPE}" == "account" ]]; then
            {
            az netappfiles account delete --resource-group $RESOURCEGROUP_NAME --name $NETAPP_ACCOUNT_NAME
            } || {
                break
            }                    
        elif [[ "${_RESOURCE_TYPE}" == "pool" ]]; then
            if [[ "${_POOL_TYPE}" == "primary" ]]; then
                {
                    az netappfiles pool delete --resource-group $RESOURCEGROUP_NAME \
                        --account-name $NETAPP_ACCOUNT_NAME \
                        --name $PRIMARY_NETAPP_POOL_NAME
                } || {
                    break
                }                
            else
                {
                    az netappfiles pool delete --resource-group $RESOURCEGROUP_NAME \
                        --account-name $NETAPP_ACCOUNT_NAME \
                        --name $SECONDARY_NETAPP_POOL_NAME
                } || {
                    break
                }
            fi                    
        else
            if [[ "${_POOL_TYPE}" == "primary" ]]; then
                {
                    az netappfiles volume delete --resource-group $RESOURCEGROUP_NAME \
                        --account-name $NETAPP_ACCOUNT_NAME \
                        --pool-name $PRIMARY_NETAPP_POOL_NAME \
                        --name $NETAPP_VOLUME_NAME
                } || {
                    break
                }
            else
                {
                    az netappfiles volume delete --resource-group $RESOURCEGROUP_NAME \
                        --account-name $NETAPP_ACCOUNT_NAME \
                        --pool-name $SECONDARY_NETAPP_POOL_NAME \
                        --name $NETAPP_VOLUME_NAME
                } || {
                    break
                }                
            fi
        fi        
    done   
}


#Script Start
#Display Header
display_bash_header

# Login and Authenticate to Azure
display_message "Authenticating into Azure"
az login

# Set the target subscription 
display_message "setting up the target subscription"
az account set --subscription $SUBSCRIPTION_ID

display_message "Creating Azure NetApp Files Account ..."
{    
    NEW_ACCOUNT_ID="";create_or_update_netapp_account NEW_ACCOUNT_ID
    wait_for_resource "account" ""
    display_message "Azure NetApp Files Account was created successfully: $NEW_ACCOUNT_ID"
} || {
    display_message "Failed to create Azure NetApp Files Account"
    exit 1
}

display_message "Creating Azure NetApp Files Primary Pool ..."
{
    NEW_PRIMARY_POOL_ID="";create_or_update_netapp_pool NEW_PRIMARY_POOL_ID $PRIMARY_NETAPP_POOL_NAME $PRIMARY_SERVICE_LEVEL
    wait_for_resource "pool" "primary"
    display_message "Azure NetApp Files primary pool was created successfully: $NEW_PRIMARY_POOL_ID"
} || {
    display_message "Failed to create Azure NetApp Files primary pool"
    exit 1
}

NEW_SECONDARY_POOL_ID=""
display_message "Creating Azure NetApp Files Secondary Pool ..."
{
    create_or_update_netapp_pool NEW_SECONDARY_POOL_ID $SECONDARY_NETAPP_POOL_NAME $SECONDARY_SERVICE_LEVEL
    wait_for_resource "pool" "secondary"
    display_message "Azure NetApp Files Secondary pool was created successfully: $NEW_SECONDARY_POOL_ID"
} || {
    display_message "Failed to create Azure NetApp Files Secondary pool"
    exit 1
}

display_message "Creating Azure NetApp Files Volume..."
{
    NEW_VOLUME_ID="";create_or_update_netapp_volume NEW_VOLUME_ID
    wait_for_resource "volume" "primary"
    display_message "Azure NetApp Files volume was created successfully: $NEW_VOLUME_ID"
} || {
    display_message "Failed to create Azure NetApp Files volume"
    exit 1
}

display_message "Performing pool change for Volume: $NETAPP_VOLUME_NAME ..."
{
    update_netapp_volume_pool $NEW_SECONDARY_POOL_ID
    wait_for_resource "volume" "secondary"
    display_message "Azure NetApp Files volume was moved successfully to : $SECONDARY_NETAPP_POOL_NAME"
} || {
    display_message "Failed to create Azure NetApp Files volume"
    exit 1
}

# Clean up resources
if [[ "$SHOULD_CLEANUP" == true ]]; then
    #Display cleanup header
    display_cleanup_header

    # Delete Volume
    display_message "Deleting Azure NetApp Files Volume..."
    {
        delete_netapp_volume
        wait_for_NO_RESOURCE "volume" "secondary"
        display_message "Azure NetApp Files volume was deleted successfully"
    } || {
        display_message "Failed to delete Azure NetApp Files volume"
        exit 1
    }

    #Delete Capacity Pool
    display_message "Deleting Azure NetApp Files Pool ..."
    {
        delete_netapp_pool
        wait_for_NO_RESOURCE "pool" "secondary"
        display_message "Azure NetApp Files pool was deleted successfully"
    } || {
        display_message "Failed to delete Azure NetApp Files pool"
        exit 1
    }

    #Delete Account
    display_message "Deleting Azure NetApp Files Account ..."
    {
        delete_netapp_account
        display_message "Azure NetApp Files Account was deleted successfully"
    } || {
        display_message "Failed to delete Azure NetApp Files Account"
        exit 1
    }
fi