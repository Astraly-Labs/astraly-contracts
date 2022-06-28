#!/bin/bash

export STARKNET_NETWORK=alpha-goerli
export STARKNET_WALLET=starkware.starknet.wallets.open_zeppelin.OpenZeppelinAccount
export OWNER_ACCOUNT_NAME=owner
# TODO: Use this only on devnet, otherwise comment next lines
# export STARKNET_GATEWAY_URL=http://127.0.0.1:5000
# export STARKNET_FEEDER_GATEWAY_URL=http://127.0.0.1:5000

SALT=0x1
MAX_FEE=54452800237082000

ALPHA_ROAD_POOL=0x38bd0f8aff67ade736159d373cf3399d15529445b147b6b3348cc96cdf66ad8
# JEDI_SWAP_POOL=0x68f02f0573d85b2d54942eea4c1bf97c38ca0e3e34fe3c974d1a3feef6c33be
XZKP_ADDRESS=0x005ef67d8c38b82ba699f206bf0db59f1828087a710bad48cc4d51a2b0da4c29

################################################################################## COMPILE ##########################################################################################
cd ../
mkdir -p artifacts
echo "Compile contracts"
starknet-compile ./contracts/AMMs/alpha_road/AlphaRoadWrapper.cairo --output ./artifacts/AlphaRoadWrapper.json --abi ./artifacts/AlphaRoadWrapper_abi.json
# starknet-compile ./contracts/AMMs/jedi_swap/JediSwapWrapper.cairo --output ./artifacts/JediSwapWrapper.json --abi ./artifacts/JediSwapWrapper_abi.json

################################################################################## DECLARE ##########################################################################################
cd ./contracts
echo "Declare AlphaRoadWrapper"
starknet declare --contract ../artifacts/AlphaRoadWrapper.json
# echo "Declare JediSwapWrapper"
# starknet declare --contract ../artifacts/JediSwapWrapper.json

################################################################################## DEPLOY ##########################################################################################
echo "Deploy AlphaRoadWrapper"
ALPHA_ROAD_WRAPPER_DEPLOYMENT_RECEIPT=$(starknet deploy --contract ../artifacts/AlphaRoadWrapper.json --inputs ${ALPHA_ROAD_POOL} --salt ${SALT})
echo "${ALPHA_ROAD_WRAPPER_DEPLOYMENT_RECEIPT}"
ALPHA_ROAD_WRAPPER_ADDRESS=$(awk 'NR==2 {print $3}' <<< "${ALPHA_ROAD_WRAPPER_DEPLOYMENT_RECEIPT}")

# echo "Deploy JediSwapWrapper"
# JEDI_SWAP_WRAPPER_DEPLOYMENT_RECEIPT=$(starknet deploy --contract ../artifacts/JediSwapWrapper.json --inputs ${JEDI_SWAP_POOL} --salt ${SALT})
# echo "${JEDI_SWAP_WRAPPER_DEPLOYMENT_RECEIPT}"
# JEDI_SWAP_WRAPPER_ADDRESS=$(awk 'NR==2 {print $3}' <<< "${JEDI_SWAP_WRAPPER_DEPLOYMENT_RECEIPT}")



echo "Add AlphaRoad LP token as whitelisted token"
starknet invoke --address "${XZKP_ADDRESS}" \
    --abi ../artifacts/ZkPadStaking_abi.json \
    --function addWhitelistedToken \
    --inputs ${ALPHA_ROAD_POOL} "${ALPHA_ROAD_WRAPPER_ADDRESS}" 0 \
    --max_fee ${MAX_FEE} \
    --account ${OWNER_ACCOUNT_NAME} \
   

# echo "Add Jedi Swap LP token as whitelisted token"
# starknet invoke --address "${XZKP_ADDRESS}" \
#     --abi ../artifacts/ZkPadStaking_abi.json \
#     --function addWhitelistedToken \
#     --inputs ${JEDI_SWAP_POOL} "${JEDI_SWAP_WRAPPER_ADDRESS}" 0 \
#     --max_fee ${MAX_FEE} \
#     --account ${OWNER_ACCOUNT_NAME} \
   
