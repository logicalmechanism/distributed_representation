#!/bin/bash
set -e

export CARDANO_NODE_SOCKET_PATH=$(cat ../data/path_to_socket.sh)
cli=$(cat ../data/path_to_cli.sh)
testnet_magic=$(cat ../data/testnet.magic)

# staking contract
stake_script_path="../../contracts/stake_contract.plutus"
# bundle sale contract
mediator_script_path="../../contracts/mediator_contract.plutus"
script_address=$(${cli} address build --payment-script-file ${mediator_script_path} --stake-script-file ${stake_script_path} --testnet-magic ${testnet_magic})

# collat, artist, reference
delegator_address=$(cat ../wallets/delegator-wallet/payment.addr)
delegator_pkh=$(${cli} address key-hash --payment-verification-key-file ../wallets/delegator-wallet/payment.vkey)

#
collat_address=$(cat ../wallets/collat-wallet/payment.addr)
collat_pkh=$(${cli} address key-hash --payment-verification-key-file ../wallets/collat-wallet/payment.vkey)

echo -e "\033[0;36m Gathering Script UTxO Information  \033[0m"
${cli} query utxo \
    --address ${script_address} \
    --testnet-magic ${testnet_magic} \
    --out-file ../tmp/script_utxo.json
# transaction variables
TXNS=$(jq length ../tmp/script_utxo.json)
if [ "${TXNS}" -eq "0" ]; then
   echo -e "\n \033[0;31m NO UTxOs Found At ${script_address} \033[0m \n";
   exit;
fi
TXIN=$(jq -r --arg alltxin "" 'keys[] | . + $alltxin + " --tx-in"' ../tmp/script_utxo.json)
script_tx_in=${TXIN::-8}
echo Mediator UTxO: $script_tx_in

data="../tmp/script_utxo.json"
lovelace=$(jq '[.[] | .value."lovelace"] | add' ${data})
echo "Lovelace: " ${lovelace}

assets=$(python3 -c "import sys; sys.path.append('../../lib/py/'); from getAllTokens import concatenate_values; concatenate_values('${data}')")
echo "Assets: " ${assets}

if [ -z "$assets" ]; then  # check if the result is an empty string
    script_address_out="${script_address} + ${lovelace}"
else
    script_address_out="${script_address} + ${lovelace} + ${assets}"
fi
echo "Script OUTPUT: "${script_address_out}
#
# exit
#
echo -e "\033[0;36m Gathering Delegator UTxO Information  \033[0m"
${cli} query utxo \
    --testnet-magic ${testnet_magic} \
    --address ${delegator_address} \
    --out-file ../tmp/delegator_utxo.json
TXNS=$(jq length ../tmp/delegator_utxo.json)
if [ "${TXNS}" -eq "0" ]; then
   echo -e "\n \033[0;31m NO UTxOs Found At ${delegator_address} \033[0m \n";
   exit;
fi
alltxin=""
TXIN=$(jq -r --arg alltxin "" 'keys[] | . + $alltxin + " --tx-in"' ../tmp/delegator_utxo.json)
delegator_tx_in=${TXIN::-8}

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
collat_utxo=$(jq -r 'keys[0]' ../tmp/collat_utxo.json)

script_ref_utxo=$(${cli} transaction txid --tx-file ../tmp/mediator-reference-utxo.signed )

slot=$(${cli} query tip --testnet-magic ${testnet_magic} | jq .slot)
current_slot=$(($slot - 1))
final_slot=$(($slot + 250))

# exit
echo -e "\033[0;36m Building Tx \033[0m"
FEE=$(${cli} transaction build \
    --babbage-era \
    --out-file ../tmp/tx.draft \
    --invalid-before ${current_slot} \
    --invalid-hereafter ${final_slot} \
    --change-address ${delegator_address} \
    --tx-in-collateral="${collat_utxo}" \
    --tx-in ${delegator_tx_in} \
    --tx-in ${script_tx_in} \
    --spending-tx-in-reference="${script_ref_utxo}#1" \
    --spending-plutus-script-v2 \
    --spending-reference-tx-in-inline-datum-present \
    --spending-reference-tx-in-redeemer-file ../data/mediator/dispute-redeemer.json \
    --tx-out="${script_address_out}" \
    --tx-out-inline-datum-file ../data/mediator/updated-mediator-datum.json \
    --required-signer-hash ${collat_pkh} \
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
    --signing-key-file ../wallets/delegator-wallet/payment.skey \
    --signing-key-file ../wallets/collat-wallet/payment.skey \
    --tx-body-file ../tmp/tx.draft \
    --out-file ../tmp/tx.signed \
    --testnet-magic ${testnet_magic}
#    
# exit
#
echo -e "\033[0;36m Submitting \033[0m"
${cli} transaction submit \
    --testnet-magic ${testnet_magic} \
    --tx-file ../tmp/tx.signed

tx=$(cardano-cli transaction txid --tx-file ../tmp/tx.signed)
echo "Tx Hash:" $tx

cp ../data/mediator/updated-mediator-datum.json ../data/mediator/mediator-datum.json