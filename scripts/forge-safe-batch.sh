#!/usr/bin/env bash

# Read the RPC URL
source .env

# Run the script
echo Running Script: $1...

# Run the script with interactive inputs
FOUNDRY_PROFILE=deploy-mainnet forge script $1 \
    --rpc-url $RPC_URL \
    --broadcast \
    -vvvv \
    --sender $SIGNER_ADDRESS \
    --account $ACCOUNT \
    --password $PASSWORD \
    --sig "$2(bool)()" \
    $3