#!/bin/bash
set -e

export CARDANO_NODE_SOCKET_PATH=$(cat ../data/path_to_socket.sh)
cli=$(cat ../data/path_to_cli.sh)
testnet_magic=$(cat ../data/testnet.magic)

# get params
${cli} query protocol-parameters --testnet-magic ${testnet_magic} --out-file ../tmp/protocol.json

# staking contract
stake_script_path="../../contracts/stake_contract.plutus"

#
delegator_address=$(cat ../wallets/delegator-wallet/payment.addr)
delegator_pkh=$(${cli} address key-hash --payment-verification-key-file ../wallets/delegator-wallet/payment.vkey)

#
collat_address=$(cat ../wallets/collat-wallet/payment.addr)
collat_pkh=$(${cli} address key-hash --payment-verification-key-file ../wallets/collat-wallet/payment.vkey)

# the minting script policy
policy_id=$(cat ../../hashes/nft_contract.hash)

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

echo "Delegator UTxO:" $delegator_tx_in
first_utxo=$(jq -r 'keys[0]' ../tmp/delegator_utxo.json)
string=${first_utxo}
IFS='#' read -ra array <<< "$string"

prefix_dao="7e44414f"

nft_name=$(python3 -c "import sys; sys.path.append('../../lib/py/'); from getTokenName import token_name; token_name('${array[0]}', ${array[1]}, '${prefix_dao}')")

echo -n $nft_name > ../tmp/nft.token

MINT_ASSET="1 ${policy_id}.${nft_name}"

UTXO_VALUE=$(${cli} transaction calculate-min-required-utxo \
    --babbage-era \
    --protocol-params-file ../tmp/protocol.json \
    --tx-out="${delegator_address} + 5000000 + ${MINT_ASSET}" | tr -dc '0-9')
delegator_address_out="${delegator_address} + ${UTXO_VALUE} + ${MINT_ASSET}"

echo "Delegator Mint OUTPUT:" ${delegator_address_out}
#
# exit
#
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

script_ref_utxo=$(${cli} transaction txid --tx-file ../tmp/nft-reference-utxo.signed)
data_ref_utxo=$(${cli} transaction txid --tx-file ../tmp/referenceable-tx.signed )

# update the add_amt
variable=1; jq --argjson variable "$variable" '.fields[0].int=$variable' ../data/mint/mint-to-lock.json > ../data/mint/mint-to-lock.json-new.json
mv ../data/mint/mint-to-lock.json-new.json ../data/mint/mint-to-lock.json

# Add metadata to this build function for nfts with data
echo -e "\033[0;36m Building Tx \033[0m"
FEE=$(${cli} transaction build \
    --babbage-era \
    --out-file ../tmp/tx.draft \
    --change-address ${delegator_address} \
    --tx-in-collateral="${collat_utxo}" \
    --read-only-tx-in-reference="${data_ref_utxo}#0" \
    --tx-in ${delegator_tx_in} \
    --tx-out="${delegator_address_out}" \
    --required-signer-hash ${collat_pkh} \
    --required-signer-hash ${delegator_pkh} \
    --mint="${MINT_ASSET}" \
    --mint-tx-in-reference="${script_ref_utxo}#1" \
    --mint-plutus-script-v2 \
    --policy-id="${policy_id}" \
    --mint-reference-tx-in-redeemer-file ../data/mint/mint-to-lock.json \
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