#!/bin/bash
set -e

export CARDANO_NODE_SOCKET_PATH=$(cat ../data/path_to_socket.sh)
cli=$(cat ../data/path_to_cli.sh)
testnet_magic=$(cat ../data/testnet.magic)

# stake contract
stake_script_path="../../contracts/stake_contract.plutus"
stake_address=$(${cli} stake-address build --stake-script-file ${stake_script_path} --testnet-magic ${testnet_magic})

echo "Stake Address: " $stake_address

# collat
collat_address=$(cat ../wallets/collat-wallet/payment.addr)
collat_pkh=$(${cli} address key-hash --payment-verification-key-file ../wallets/collat-wallet/payment.vkey)

# reward fee payer
starter_address=$(cat ../wallets/starter-wallet/payment.addr)

# vault holds the rewards
vault_script_path="../../contracts/vault_contract.plutus"
vault_address=$(${cli} address build --payment-script-file ${vault_script_path} --stake-script-file ${stake_script_path} --testnet-magic ${testnet_magic})

# get script utxo
echo -e "\033[0;36m Gathering Script UTxO Information  \033[0m"
${cli} query utxo \
    --address ${vault_address} \
    --testnet-magic ${testnet_magic} \
    --out-file ../tmp/script_utxo.json
TXNS=$(jq length ../tmp/script_utxo.json)
if [ "${TXNS}" -eq "0" ]; then
   echo -e "\n \033[0;31m NO UTxOs Found At ${vault_address} \033[0m \n";
   exit;
fi
alltxin=""
TXIN=$(jq -r --arg alltxin "" 'to_entries[] | .key | . + $alltxin + " --tx-in"' ../tmp/script_utxo.json)
vault_tx_in=${TXIN::-8}

echo Vault TxId: $vault_tx_in
lovelace_value=$(jq -r '.[].value.lovelace' ../tmp/script_utxo.json)

# find rewards
rewardBalance=$(${cli} query stake-address-info \
    --testnet-magic ${testnet_magic} \
    --address ${stake_address} | jq -r ".[0].rewardAccountBalance")
echo rewardBalance: $rewardBalance

if [ "$rewardBalance" -eq 0 ]; then
   echo -e "\n \033[0;31m No Rewards Found At ${stake_address} \033[0m \n";
fi

min_utxo=$((${lovelace_value} + ${rewardBalance}))

# update the add_amt
variable=${rewardBalance}; jq --argjson variable "$variable" '.fields[0].int=$variable' ../data/vault/add-to-vault.json > ../data/vault/add-to-vault.json-new.json
mv ../data/vault/add-to-vault.json-new.json ../data/vault/add-to-vault.json

withdrawalString="${stake_address}+${rewardBalance}"
vault_address_out="${vault_address} + ${min_utxo}"
echo "Vault OUTPUT: "${vault_address_out}
#
# exit
#
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
TXIN=$(jq -r --arg alltxin "" 'to_entries[] | select(.value.value | length < 2) | .key | . + $alltxin + " --tx-in"' ../tmp/starter_utxo.json)
starter_tx_in=${TXIN::-8}

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
collat_utxo=$(jq -r 'keys[0]' ../tmp/collat_utxo.json)

script_ref_utxo=$(${cli} transaction txid --tx-file ../tmp/stake-reference-utxo.signed)
vault_ref_utxo=$(${cli} transaction txid --tx-file ../tmp/vault-reference-utxo.signed )
data_ref_utxo=$(${cli} transaction txid --tx-file ../tmp/referenceable-tx.signed )

echo -e "\033[0;36m Building Tx \033[0m"
FEE=$(${cli} transaction build \
    --babbage-era \
    --out-file ../tmp/tx.draft \
    --change-address ${starter_address} \
    --read-only-tx-in-reference="${data_ref_utxo}#0" \
    --tx-in-collateral="${collat_utxo}" \
    --tx-in ${starter_tx_in} \
    --tx-in ${vault_tx_in} \
    --spending-tx-in-reference="${vault_ref_utxo}#1" \
    --spending-plutus-script-v2 \
    --spending-reference-tx-in-inline-datum-present \
    --spending-reference-tx-in-redeemer-file ../data/vault/add-to-vault.json \
    --tx-out="${vault_address_out}" \
    --tx-out-inline-datum-file ../data/vault/vault-datum.json \
    --withdrawal ${withdrawalString} \
    --withdrawal-tx-in-reference="${script_ref_utxo}#1" \
    --withdrawal-plutus-script-v2 \
    --withdrawal-reference-tx-in-redeemer-file ../data/stake/withdraw-redeemer.json \
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
    --signing-key-file ../wallets/starter-wallet/payment.skey \
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