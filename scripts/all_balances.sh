#!/usr/bin/bash
set -e
#
export CARDANO_NODE_SOCKET_PATH=$(cat ./data/path_to_socket.sh)
cli=$(cat ./data/path_to_cli.sh)
testnet_magic=$(cat ./data/testnet.magic)

# staking contract
stake_script_path="../contracts/stake_contract.plutus"

# dao contract
dao_script_path="../contracts/dao_contract.plutus"
dao_script_address=$(${cli} address build --payment-script-file ${dao_script_path} --testnet-magic ${testnet_magic})

# lock contract
lock_script_path="../contracts/lock_contract.plutus"
lock_script_address=$(${cli} address build --payment-script-file ${lock_script_path} --stake-script-file ${stake_script_path} --testnet-magic ${testnet_magic})

# vault contract
vault_script_path="../contracts/vault_contract.plutus"
vault_script_address=$(${cli} address build --payment-script-file ${vault_script_path} --stake-script-file ${stake_script_path} --testnet-magic ${testnet_magic})


${cli} query protocol-parameters --testnet-magic ${testnet_magic} --out-file ./tmp/protocol.json
${cli} query tip --testnet-magic ${testnet_magic} | jq
${cli} query tx-mempool info --testnet-magic ${testnet_magic} | jq

#
#
echo -e "\033[1;35m\nDAO Script Address: \033[0m" 
echo -e "\n \033[1;32m ${dao_script_address} \033[0m \n";
${cli} query utxo --address ${dao_script_address} --testnet-magic ${testnet_magic}
#
echo -e "\033[1;35m\nLock Script Address: \033[0m" 
echo -e "\n \033[1;32m ${lock_script_address} \033[0m \n";
${cli} query utxo --address ${lock_script_address} --testnet-magic ${testnet_magic}
#

# Loop through each -wallet folder
for wallet_folder in wallets/*-wallet; do
    # Check if payment.addr file exists in the folder
    if [ -f "${wallet_folder}/payment.addr" ]; then
        addr=$(cat ${wallet_folder}/payment.addr)
        echo
        
        echo -e "\033[1;37m --------------------------------------------------------------------------------\033[0m"
        echo -e "\033[1;34m $wallet_folder\033[0m\n\n\033[1;32m $addr\033[0m"

        echo -e "\033[1;33m"
        # Run the cardano-cli command with the reference address and testnet magic
        ${cli} query utxo --address ${addr} --testnet-magic ${testnet_magic}
        ${cli} query utxo --address ${addr} --testnet-magic ${testnet_magic} --out-file ./tmp/"${addr}.json"

        baseLovelace=$(jq '[.. | objects | .lovelace] | add' ./tmp/"${addr}.json")
        echo -e "\033[0m"

        echo -e "\033[1;36m"
        ada=$(echo "scale = 6;${baseLovelace} / 1000000" | bc -l)
        echo -e "TOTAL ADA:" ${ada}
        echo -e "\033[0m"
    fi
done