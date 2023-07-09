#!/bin/bash
set -e

export CARDANO_NODE_SOCKET_PATH=$(cat ../data/path_to_socket.sh)
cli=$(cat ../data/path_to_cli.sh)
testnet_magic=$(cat ../data/testnet.magic)

# staked smart contract address
script_path="../../contracts/dao_contract.plutus"
script_address=$(${cli} address build --payment-script-file ${script_path} --testnet-magic ${testnet_magic})

# collat
collat_address=$(cat ../wallets/collat-wallet/payment.addr)
collat_pkh=$(${cli} address key-hash --payment-verification-key-file ../wallets/collat-wallet/payment.vkey)

# starter
starter_address=$(cat ../wallets/starter-wallet/payment.addr)
starter_pkh=$(${cli} address key-hash --payment-verification-key-file ../wallets/starter-wallet/payment.vkey)

# multisig
keeper1_pkh=$(${cli} address key-hash --payment-verification-key-file ../wallets/keeper1-wallet/payment.vkey)
keeper2_pkh=$(${cli} address key-hash --payment-verification-key-file ../wallets/keeper2-wallet/payment.vkey)
keeper3_pkh=$(${cli} address key-hash --payment-verification-key-file ../wallets/keeper3-wallet/payment.vkey)

# asset to trade
policy_id=$(jq -r '.starterPid' ../../start_info.json)
token_name=$(jq -r '.starterTkn' ../../start_info.json)
asset="1 ${policy_id}.${token_name}"

current_min_utxo=$(${cli} transaction calculate-min-required-utxo \
    --babbage-era \
    --protocol-params-file ../tmp/protocol.json \
    --tx-out-inline-datum-file ../data/dao/dao-datum.json \
    --tx-out="${script_address} + 5000000 + ${asset}" | tr -dc '0-9')

updated_min_utxo=$(${cli} transaction calculate-min-required-utxo \
    --babbage-era \
    --protocol-params-file ../tmp/protocol.json \
    --tx-out-inline-datum-file ../data/dao/updated-dao-datum.json \
    --tx-out="${script_address} + 5000000 + ${asset}" | tr -dc '0-9')

difference=$((${updated_min_utxo} - ${current_min_utxo}))

direction=0
if [ "$difference" -eq "0" ]; then
    echo "Minimum ADA is Constant"
    direction=0
elif [ "$difference" -lt "0" ]; then
    positive=$(( -1 * ${difference}))
    echo "Minimum ADA Decreasing by" ${positive}
    direction=1
    difference=$positive
else
    echo "Minimum ADA Increasing by" ${difference}
fi

# assume the min will always be the updated since updated can just be constant
min_utxo=${updated_min_utxo}

# update the difference
variable=${difference}; jq --argjson variable "$variable" '.fields[0].int=$variable' ../data/dao/update-data.json > ../data/dao/update-data-new.json
mv ../data/dao/update-data-new.json ../data/dao/update-data.json

# update the direciton, 0 is increase
variable=${direction}; jq --argjson variable "$variable" '.fields[1].int=$variable' ../data/dao/update-data.json > ../data/dao/update-data-new.json
    mv ../data/dao/update-data-new.json ../data/dao/update-data.json


script_address_out="${script_address} + ${min_utxo} + ${asset}"
echo "Script OUTPUT: "${script_address_out}
#
exit
#
# get deleg utxo
echo -e "\033[0;36m Gathering UTxO Information  \033[0m"
${cli} query utxo \
    --testnet-magic ${testnet_magic} \
    --address ${starter_address} \
    --out-file ../tmp/starter_utxo.json

TXNS=$(jq length ../tmp/starter_utxo.json)
if [ "${TXNS}" -eq "0" ]; then
   echo -e "\n \033[0;31m NO UTxOs Found At ${starter_address} \033[0m \n";
   exit;
fi
alltxin=""
TXIN=$(jq -r --arg alltxin "" 'keys[] | . + $alltxin + " --tx-in"' ../tmp/starter_utxo.json)
starter_tx_in=${TXIN::-8}

# get script utxo
echo -e "\033[0;36m Gathering Script UTxO Information  \033[0m"
${cli} query utxo \
    --address ${script_address} \
    --testnet-magic ${testnet_magic} \
    --out-file ../tmp/script_utxo.json
TXNS=$(jq length ../tmp/script_utxo.json)
if [ "${TXNS}" -eq "0" ]; then
   echo -e "\n \033[0;31m NO UTxOs Found At ${script_address} \033[0m \n";
   exit;
fi
alltxin=""
TXIN=$(jq -r --arg alltxin "" --arg policy_id "$policy_id" --arg token_name "$token_name" 'to_entries[] | select(.value.value[$policy_id][$token_name] == 1) | .key | . + $alltxin + " --tx-in"' ../tmp/script_utxo.json)
script_tx_in=${TXIN::-8}

# collat info
echo -e "\033[0;36m Gathering Collateral UTxO Information  \033[0m"
${cli} query utxo \
    --testnet-magic ${testnet_magic} \
    --address ${collat_address} \
    --out-file ../tmp/collat_utxo.json

TXNS=$(jq length ../tmp/collat_utxo.json)
if [ "${TXNS}" -eq "0" ]; then
   echo -e "\n \033[0;31m NO UTxOs Found At ${collat_address} \033[0m \n";
   exit;
fi
collat_tx_in=$(jq -r 'keys[0]' ../tmp/collat_utxo.json)

# script reference utxo
script_ref_utxo=$(${cli} transaction txid --tx-file ../tmp/dao-reference-utxo.signed )

echo -e "\033[0;36m Building Tx \033[0m"
FEE=$(${cli} transaction build \
    --babbage-era \
    --out-file ../tmp/tx.draft \
    --change-address ${starter_address} \
    --tx-in-collateral ${collat_tx_in} \
    --tx-in ${starter_tx_in} \
    --tx-in ${script_tx_in} \
    --spending-tx-in-reference="${script_ref_utxo}#1" \
    --spending-plutus-script-v2 \
    --spending-reference-tx-in-inline-datum-present \
    --spending-reference-tx-in-redeemer-file ../data/dao/update-data.json \
    --tx-out="${script_address_out}" \
    --tx-out-inline-datum-file ../data/dao/updated-dao-datum.json \
    --required-signer-hash ${starter_pkh} \
    --required-signer-hash ${collat_pkh} \
    --required-signer-hash ${keeper1_pkh} \
    --required-signer-hash ${keeper2_pkh} \
    --required-signer-hash ${keeper3_pkh} \
    --testnet-magic ${testnet_magic})

IFS=':' read -ra VALUE <<< "${FEE}"
IFS=' ' read -ra FEE <<< "${VALUE[1]}"
FEE=${FEE[1]}
echo -e "\033[1;32m Fee: \033[0m" $FEE
#
# exit
#
echo -e "\033[0;36m Signing \033[0m"
${cli} transaction sign \
    --signing-key-file ../wallets/starter-wallet/payment.skey \
    --signing-key-file ../wallets/collat-wallet/payment.skey \
    --signing-key-file ../wallets/keeper1-wallet/payment.skey \
    --signing-key-file ../wallets/keeper2-wallet/payment.skey \
    --signing-key-file ../wallets/keeper3-wallet/payment.skey \
    --tx-body-file ../tmp/tx.draft \
    --out-file ../tmp/referenceable-tx.signed \
    --testnet-magic ${testnet_magic}
#
# exit
#
echo -e "\033[0;36m Submitting \033[0m"
${cli} transaction submit \
    --testnet-magic ${testnet_magic} \
    --tx-file ../tmp/referenceable-tx.signed

tx=$(cardano-cli transaction txid --tx-file ../tmp/referenceable-tx.signed)
echo "Tx Hash:" $tx

cp ../data/dao/updated-dao-datum.json ../data/dao/dao-datum.json