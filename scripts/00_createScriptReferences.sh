#!/bin/bash
set -e

# SET UP VARS HERE
export CARDANO_NODE_SOCKET_PATH=$(cat ./data/path_to_socket.sh)
cli=$(cat ./data/path_to_cli.sh)
testnet_magic=$(cat ./data/testnet.magic)

mkdir -p ./tmp
${cli} query protocol-parameters --testnet-magic ${testnet_magic} --out-file ./tmp/protocol.json

# contract path
dao_script_path="../contracts/dao_contract.plutus"
stake_script_path="../contracts/stake_contract.plutus"
mint_script_path="../contracts/mint_contract.plutus"
lock_script_path="../contracts/lock_contract.plutus"
vault_script_path="../contracts/vault_contract.plutus"
nft_script_path="../contracts/nft_contract.plutus"


# Addresses
reference_address=$(cat ./wallets/reference-wallet/payment.addr)
script_reference_address=$(cat ./wallets/reference-wallet/payment.addr)

#
# exit
#
echo -e "\033[0;35m\nGathering UTxO Information  \033[0m"
${cli} query utxo \
    --testnet-magic ${testnet_magic} \
    --address ${reference_address} \
    --out-file ./tmp/reference_utxo.json

TXNS=$(jq length ./tmp/reference_utxo.json)
if [ "${TXNS}" -eq "0" ]; then
   echo -e "\n \033[0;31m NO UTxOs Found At ${reference_address} \033[0m \n";
   exit;
fi
alltxin=""
TXIN=$(jq -r --arg alltxin "" 'to_entries[] | select(.value.value | length < 2) | .key | . + $alltxin + " --tx-in"' ./tmp/reference_utxo.json)
vault_tx_in=${TXIN::-8}
#
# exit
#
###############################################################################
# chain second set of reference scripts to the first
echo -e "\033[0;33m\nStart Building Tx Chain \033[0m"
echo -e "\033[0;36m Building Tx \033[0m"
starting_reference_lovelace=$(jq '[.. | objects | .lovelace] | add' ./tmp/reference_utxo.json)

dao_min_utxo=$(${cli} transaction calculate-min-required-utxo \
    --babbage-era \
    --protocol-params-file ./tmp/protocol.json \
    --tx-out-reference-script-file ${dao_script_path} \
    --tx-out="${script_reference_address} + 1000000" | tr -dc '0-9')

dao_value=$((${dao_min_utxo}))
dao_script_reference_utxo="${script_reference_address} + ${dao_value}"

echo -e "\nCreating DAO Script:\n" ${dao_script_reference_utxo}

${cli} transaction build-raw \
    --babbage-era \
    --protocol-params-file ./tmp/protocol.json \
    --out-file ./tmp/tx.draft \
    --tx-in ${vault_tx_in} \
    --tx-out="${reference_address} + ${starting_reference_lovelace}" \
    --tx-out="${dao_script_reference_utxo}" \
    --tx-out-reference-script-file ${dao_script_path} \
    --fee 900000

FEE=$(cardano-cli transaction calculate-min-fee --tx-body-file ./tmp/tx.draft --testnet-magic ${testnet_magic} --protocol-params-file ./tmp/protocol.json --tx-in-count 0 --tx-out-count 0 --witness-count 1)
# echo $FEE
fee=$(echo $FEE | rev | cut -c 9- | rev)

#
firstReturn=$((${starting_reference_lovelace} - ${dao_value} - ${fee}))

${cli} transaction build-raw \
    --babbage-era \
    --protocol-params-file ./tmp/protocol.json \
    --out-file ./tmp/tx.draft \
    --tx-in ${vault_tx_in} \
    --tx-out="${reference_address} + ${firstReturn}" \
    --tx-out="${dao_script_reference_utxo}" \
    --tx-out-reference-script-file ${dao_script_path} \
    --fee ${fee}

echo -e "\033[0;36m Signing \033[0m"
${cli} transaction sign \
    --signing-key-file ./wallets/reference-wallet/payment.skey \
    --tx-body-file ./tmp/tx.draft \
    --out-file ./tmp/tx-1.signed \
    --testnet-magic ${testnet_magic}

###############################################################################

nextUTxO=$(${cli} transaction txid --tx-body-file ./tmp/tx.draft)
echo "First in the tx chain" $nextUTxO

stake_min_utxo=$(${cli} transaction calculate-min-required-utxo \
    --babbage-era \
    --protocol-params-file ./tmp/protocol.json \
    --tx-out-reference-script-file ${stake_script_path} \
    --tx-out="${script_reference_address} + 1000000" | tr -dc '0-9')

stake_value=$((${stake_min_utxo}))
stake_script_reference_utxo="${script_reference_address} + ${stake_value}"
echo -e "\nCreating Stake Script:\n" ${stake_script_reference_utxo}

echo -e "\033[0;36m Building Tx \033[0m"
${cli} transaction build-raw \
    --babbage-era \
    --protocol-params-file ./tmp/protocol.json \
    --out-file ./tmp/tx.draft \
    --tx-in="${nextUTxO}#0" \
    --tx-out="${reference_address} + ${firstReturn}" \
    --tx-out="${stake_script_reference_utxo}" \
    --tx-out-reference-script-file ${stake_script_path} \
    --fee 900000

FEE=$(${cli} transaction calculate-min-fee --tx-body-file ./tmp/tx.draft --testnet-magic ${testnet_magic} --protocol-params-file ./tmp/protocol.json --tx-in-count 0 --tx-out-count 0 --witness-count 1)
# echo $FEE
fee=$(echo $FEE | rev | cut -c 9- | rev)

#
secondReturn=$((${firstReturn} - ${stake_value} - ${fee}))

${cli} transaction build-raw \
    --babbage-era \
    --protocol-params-file ./tmp/protocol.json \
    --out-file ./tmp/tx.draft \
    --tx-in="${nextUTxO}#0" \
    --tx-out="${reference_address} + ${secondReturn}" \
    --tx-out="${stake_script_reference_utxo}" \
    --tx-out-reference-script-file ${stake_script_path} \
    --fee ${fee}
#
echo -e "\033[0;36m Signing \033[0m"
${cli} transaction sign \
    --signing-key-file ./wallets/reference-wallet/payment.skey \
    --tx-body-file ./tmp/tx.draft \
    --out-file ./tmp/tx-2.signed \
    --testnet-magic ${testnet_magic}

###############################################################################

nextUTxO=$(${cli} transaction txid --tx-body-file ./tmp/tx.draft)
echo "Third in the tx chain" $nextUTxO

mint_min_utxo=$(${cli} transaction calculate-min-required-utxo \
    --babbage-era \
    --protocol-params-file ./tmp/protocol.json \
    --tx-out-reference-script-file ${mint_script_path} \
    --tx-out="${script_reference_address} + 1000000" | tr -dc '0-9')

mint_value=$((${mint_min_utxo}))
mint_script_reference_utxo="${script_reference_address} + ${mint_value}"
echo -e "\nCreating Mint Script:\n" ${mint_script_reference_utxo}

echo -e "\033[0;36m Building Tx \033[0m"
${cli} transaction build-raw \
    --babbage-era \
    --protocol-params-file ./tmp/protocol.json \
    --out-file ./tmp/tx.draft \
    --tx-in="${nextUTxO}#0" \
    --tx-out="${reference_address} + ${secondReturn}" \
    --tx-out="${mint_script_reference_utxo}" \
    --tx-out-reference-script-file ${mint_script_path} \
    --fee 900000

FEE=$(${cli} transaction calculate-min-fee --tx-body-file ./tmp/tx.draft --testnet-magic ${testnet_magic} --protocol-params-file ./tmp/protocol.json --tx-in-count 0 --tx-out-count 0 --witness-count 1)
# echo $FEE
fee=$(echo $FEE | rev | cut -c 9- | rev)

thirdReturn=$((${secondReturn} - ${mint_value} - ${fee}))

${cli} transaction build-raw \
    --babbage-era \
    --protocol-params-file ./tmp/protocol.json \
    --out-file ./tmp/tx.draft \
    --tx-in="${nextUTxO}#0" \
    --tx-out="${reference_address} + ${thirdReturn}" \
    --tx-out="${mint_script_reference_utxo}" \
    --tx-out-reference-script-file ${mint_script_path} \
    --fee ${fee}

echo -e "\033[0;36m Signing \033[0m"
${cli} transaction sign \
    --signing-key-file ./wallets/reference-wallet/payment.skey \
    --tx-body-file ./tmp/tx.draft \
    --out-file ./tmp/tx-3.signed \
    --testnet-magic ${testnet_magic}

###############################################################################

nextUTxO=$(${cli} transaction txid --tx-body-file ./tmp/tx.draft)
echo "Fourth in the tx chain" $nextUTxO

lock_min_utxo=$(${cli} transaction calculate-min-required-utxo \
    --babbage-era \
    --protocol-params-file ./tmp/protocol.json \
    --tx-out-reference-script-file ${lock_script_path} \
    --tx-out="${script_reference_address} + 1000000" | tr -dc '0-9')

lock_value=$((${lock_min_utxo}))
lock_script_reference_utxo="${script_reference_address} + ${lock_value}"
echo -e "\nCreating Lock Script:\n" ${lock_script_reference_utxo}

echo -e "\033[0;36m Building Tx \033[0m"
${cli} transaction build-raw \
    --babbage-era \
    --protocol-params-file ./tmp/protocol.json \
    --out-file ./tmp/tx.draft \
    --tx-in="${nextUTxO}#0" \
    --tx-out="${reference_address} + ${thirdReturn}" \
    --tx-out="${lock_script_reference_utxo}" \
    --tx-out-reference-script-file ${lock_script_path} \
    --fee 900000

FEE=$(${cli} transaction calculate-min-fee --tx-body-file ./tmp/tx.draft --testnet-magic ${testnet_magic} --protocol-params-file ./tmp/protocol.json --tx-in-count 0 --tx-out-count 0 --witness-count 1)
# echo $FEE
fee=$(echo $FEE | rev | cut -c 9- | rev)

fourthReturn=$((${thirdReturn} - ${lock_value} - ${fee}))

${cli} transaction build-raw \
    --babbage-era \
    --protocol-params-file ./tmp/protocol.json \
    --out-file ./tmp/tx.draft \
    --tx-in="${nextUTxO}#0" \
    --tx-out="${reference_address} + ${fourthReturn}" \
    --tx-out="${lock_script_reference_utxo}" \
    --tx-out-reference-script-file ${lock_script_path} \
    --fee ${fee}

echo -e "\033[0;36m Signing \033[0m"
${cli} transaction sign \
    --signing-key-file ./wallets/reference-wallet/payment.skey \
    --tx-body-file ./tmp/tx.draft \
    --out-file ./tmp/tx-4.signed \
    --testnet-magic ${testnet_magic}

###############################################################################

nextUTxO=$(${cli} transaction txid --tx-body-file ./tmp/tx.draft)
echo "Fourth in the tx chain" $nextUTxO

vault_min_utxo=$(${cli} transaction calculate-min-required-utxo \
    --babbage-era \
    --protocol-params-file ./tmp/protocol.json \
    --tx-out-reference-script-file ${vault_script_path} \
    --tx-out="${script_reference_address} + 1000000" | tr -dc '0-9')

vault_value=$((${vault_min_utxo}))
vault_script_reference_utxo="${script_reference_address} + ${vault_value}"
echo -e "\nCreating Lock Script:\n" ${vault_script_reference_utxo}

echo -e "\033[0;36m Building Tx \033[0m"
${cli} transaction build-raw \
    --babbage-era \
    --protocol-params-file ./tmp/protocol.json \
    --out-file ./tmp/tx.draft \
    --tx-in="${nextUTxO}#0" \
    --tx-out="${reference_address} + ${fourthReturn}" \
    --tx-out="${vault_script_reference_utxo}" \
    --tx-out-reference-script-file ${vault_script_path} \
    --fee 900000

FEE=$(${cli} transaction calculate-min-fee --tx-body-file ./tmp/tx.draft --testnet-magic ${testnet_magic} --protocol-params-file ./tmp/protocol.json --tx-in-count 0 --tx-out-count 0 --witness-count 1)
# echo $FEE
fee=$(echo $FEE | rev | cut -c 9- | rev)

fifthReturn=$((${fourthReturn} - ${vault_value} - ${fee}))

${cli} transaction build-raw \
    --babbage-era \
    --protocol-params-file ./tmp/protocol.json \
    --out-file ./tmp/tx.draft \
    --tx-in="${nextUTxO}#0" \
    --tx-out="${reference_address} + ${fifthReturn}" \
    --tx-out="${vault_script_reference_utxo}" \
    --tx-out-reference-script-file ${vault_script_path} \
    --fee ${fee}

echo -e "\033[0;36m Signing \033[0m"
${cli} transaction sign \
    --signing-key-file ./wallets/reference-wallet/payment.skey \
    --tx-body-file ./tmp/tx.draft \
    --out-file ./tmp/tx-5.signed \
    --testnet-magic ${testnet_magic}

###############################################################################

nextUTxO=$(${cli} transaction txid --tx-body-file ./tmp/tx.draft)
echo "Fourth in the tx chain" $nextUTxO

nft_min_utxo=$(${cli} transaction calculate-min-required-utxo \
    --babbage-era \
    --protocol-params-file ./tmp/protocol.json \
    --tx-out-reference-script-file ${nft_script_path} \
    --tx-out="${script_reference_address} + 1000000" | tr -dc '0-9')

nft_value=$((${nft_min_utxo}))
nft_script_reference_utxo="${script_reference_address} + ${nft_value}"
echo -e "\nCreating Lock Script:\n" ${nft_script_reference_utxo}

echo -e "\033[0;36m Building Tx \033[0m"
${cli} transaction build-raw \
    --babbage-era \
    --protocol-params-file ./tmp/protocol.json \
    --out-file ./tmp/tx.draft \
    --tx-in="${nextUTxO}#0" \
    --tx-out="${reference_address} + ${fifthReturn}" \
    --tx-out="${nft_script_reference_utxo}" \
    --tx-out-reference-script-file ${nft_script_path} \
    --fee 900000

FEE=$(${cli} transaction calculate-min-fee --tx-body-file ./tmp/tx.draft --testnet-magic ${testnet_magic} --protocol-params-file ./tmp/protocol.json --tx-in-count 0 --tx-out-count 0 --witness-count 1)
# echo $FEE
fee=$(echo $FEE | rev | cut -c 9- | rev)

sixthReturn=$((${fifthReturn} - ${nft_value} - ${fee}))

${cli} transaction build-raw \
    --babbage-era \
    --protocol-params-file ./tmp/protocol.json \
    --out-file ./tmp/tx.draft \
    --tx-in="${nextUTxO}#0" \
    --tx-out="${reference_address} + ${sixthReturn}" \
    --tx-out="${nft_script_reference_utxo}" \
    --tx-out-reference-script-file ${nft_script_path} \
    --fee ${fee}

echo -e "\033[0;36m Signing \033[0m"
${cli} transaction sign \
    --signing-key-file ./wallets/reference-wallet/payment.skey \
    --tx-body-file ./tmp/tx.draft \
    --out-file ./tmp/tx-6.signed \
    --testnet-magic ${testnet_magic}

###############################################################################

#
# exit
#
echo -e "\033[0;34m\nSubmitting \033[0m"
${cli} transaction submit \
    --testnet-magic ${testnet_magic} \
    --tx-file ./tmp/tx-1.signed

${cli} transaction submit \
    --testnet-magic ${testnet_magic} \
    --tx-file ./tmp/tx-2.signed

${cli} transaction submit \
    --testnet-magic ${testnet_magic} \
    --tx-file ./tmp/tx-3.signed

${cli} transaction submit \
    --testnet-magic ${testnet_magic} \
    --tx-file ./tmp/tx-4.signed

${cli} transaction submit \
    --testnet-magic ${testnet_magic} \
    --tx-file ./tmp/tx-5.signed

${cli} transaction submit \
    --testnet-magic ${testnet_magic} \
    --tx-file ./tmp/tx-6.signed

#

cp ./tmp/tx-1.signed ./tmp/dao-reference-utxo.signed
cp ./tmp/tx-2.signed ./tmp/stake-reference-utxo.signed
cp ./tmp/tx-3.signed ./tmp/mint-reference-utxo.signed
cp ./tmp/tx-4.signed ./tmp/lock-reference-utxo.signed
cp ./tmp/tx-5.signed ./tmp/vault-reference-utxo.signed
cp ./tmp/tx-6.signed ./tmp/nft-reference-utxo.signed

echo -e "\033[0;32m\nDone! \033[0m"
