#!/bin/bash
set -e

function cat_file_or_empty() {
  if [ -e "$1" ]; then
    cat "$1"
  else
    echo ""
  fi
}

# create directories if dont exist
mkdir -p contracts
mkdir -p hashes
mkdir -p certs

# remove old files
rm contracts/* || true
rm hashes/* || true
rm certs/* || true

# build out the entire script
echo -e "\033[1;34m Building Contracts \033[0m"
# aiken build
aiken build --keep-traces

# the starter token policy id
pid=$(jq -r '.starterPid' start_info.json)
pid_cbor=$(python ./convert_to_cbor.py ${pid})

# the starter token asset name
tkn=$(jq -r '.starterTkn' start_info.json)
tkn_cbor=$(python ./convert_to_cbor.py ${tkn})

echo -e "\033[1;33m\nConvert DAO Contract \033[0m"
aiken blueprint apply -o plutus.json -v dao.params "${pid_cbor}" .
aiken blueprint apply -o plutus.json -v dao.params "${tkn_cbor}" .
aiken blueprint convert -v dao.params > contracts/dao_contract.plutus
cardano-cli transaction policyid --script-file contracts/dao_contract.plutus > hashes/dao_contract.hash

# reference hash
dao_hash=$(cat hashes/dao_contract.hash)
dao_hash_cbor=$(python ./convert_to_cbor.py ${dao_hash})
echo The DAO Contract Hash: ${dao_hash}

# # build the stake contract

# The pool to stake at
poolId=$(jq -r '.poolId' start_info.json)

# a random string for stake key generation
ran=$(jq -r '.random' start_info.json)
ran_cbor=$(python ./convert_to_cbor.py ${ran})

echo -e "\033[1;33m\nConvert Stake Contract \033[0m"
aiken blueprint apply -o plutus.json -v stake.params "${pid_cbor}" .
aiken blueprint apply -o plutus.json -v stake.params "${tkn_cbor}" .
aiken blueprint apply -o plutus.json -v stake.params "${dao_hash_cbor}" .
aiken blueprint apply -o plutus.json -v stake.params "${ran_cbor}" .
aiken blueprint convert -v stake.params > contracts/stake_contract.plutus
cardano-cli transaction policyid --script-file contracts/stake_contract.plutus > hashes/stake_contract.hash
cardano-cli stake-address registration-certificate --stake-script-file contracts/stake_contract.plutus --out-file certs/stake.cert
cardano-cli stake-address deregistration-certificate --stake-script-file contracts/stake_contract.plutus --out-file certs/de-stake.cert
cardano-cli stake-address delegation-certificate --stake-script-file contracts/stake_contract.plutus --stake-pool-id ${poolId} --out-file certs/deleg.cert

# Update Staking Redeemer
echo -e "\033[1;33m Updating Stake Redeemer \033[0m"
stakeHash=$(cat_file_or_empty ./hashes/stake_contract.hash)
jq \
--arg stakeHash "$stakeHash" \
'.fields[0].fields[0].bytes=$stakeHash' \
./scripts/data/stake/delegate-redeemer.json | sponge ./scripts/data/stake/delegate-redeemer.json

stake_hash=$(cat hashes/stake_contract.hash)
echo The Stake Contract Hash: ${stake_hash}

echo -e "\033[1;33m\nConvert Mint Contract \033[0m"
aiken blueprint apply -o plutus.json -v mint.params "${pid_cbor}" .
aiken blueprint apply -o plutus.json -v mint.params "${tkn_cbor}" .
aiken blueprint apply -o plutus.json -v mint.params "${dao_hash_cbor}" .
aiken blueprint convert -v mint.params > contracts/mint_contract.plutus
cardano-cli transaction policyid --script-file contracts/mint_contract.plutus > hashes/mint_contract.hash

mirror_policy=$(cat hashes/mint_contract.hash)
echo The Mint Contract Hash: ${mirror_policy}
mirror_policy_cbor=$(python ./convert_to_cbor.py ${mirror_policy})

echo -e "\033[1;33m\nConvert Lock Contract \033[0m"
aiken blueprint apply -o plutus.json -v lock.params "${mirror_policy_cbor}" .
aiken blueprint convert -v lock.params > contracts/lock_contract.plutus
cardano-cli transaction policyid --script-file contracts/lock_contract.plutus > hashes/lock_contract.hash

lock_hash=$(cat hashes/lock_contract.hash)
echo The Lock Contract Hash: ${lock_hash}

echo -e "\033[1;33m\nConvert Vault Contract \033[0m"
aiken blueprint apply -o plutus.json -v vault.params "${pid_cbor}" .
aiken blueprint apply -o plutus.json -v vault.params "${tkn_cbor}" .
aiken blueprint apply -o plutus.json -v vault.params "${dao_hash_cbor}" .
aiken blueprint convert -v vault.params > contracts/vault_contract.plutus
cardano-cli transaction policyid --script-file contracts/vault_contract.plutus > hashes/vault_contract.hash

vault_hash=$(cat hashes/vault_contract.hash)
echo The Vault Contract Hash: ${vault_hash}

echo -e "\033[1;33m\nConvert Threshold NFT Contract \033[0m"
aiken blueprint apply -o plutus.json -v nft.params "${pid_cbor}" .
aiken blueprint apply -o plutus.json -v nft.params "${tkn_cbor}" .
aiken blueprint apply -o plutus.json -v nft.params "${dao_hash_cbor}" .
aiken blueprint apply -o plutus.json -v nft.params "${mirror_policy_cbor}" .
aiken blueprint convert -v nft.params > contracts/nft_contract.plutus
cardano-cli transaction policyid --script-file contracts/nft_contract.plutus > hashes/nft_contract.hash

nft_policy=$(cat hashes/nft_contract.hash)
echo The NFT Contract Hash: ${nft_policy}

echo -e "\033[1;33m\nConvert Mediation Contract \033[0m"
aiken blueprint apply -o plutus.json -v mediator.params "${mirror_policy_cbor}" .
aiken blueprint convert -v lock.params > contracts/mediator_contract.plutus
cardano-cli transaction policyid --script-file contracts/mediator_contract.plutus > hashes/mediator_contract.hash

mediator_hash=$(cat hashes/mediator_contract.hash)
echo The Mediator Contract Hash: ${mediator_hash}

# update datum information

jq -r \
--arg poolId "$poolId" \
--arg stake "$stake_hash" \
--arg lock "$lock_hash" \
--arg vault "$vault_hash" \
--arg mpid "$mirror_policy" \
--arg npid "$nft_policy" \
'.fields[1].map[0].v.fields[0].bytes=$poolId |
.fields[1].map[3].v.map[0].v.bytes=$mpid |
.fields[1].map[3].v.map[1].v.bytes=$npid |
.fields[1].map[1].v.map[0].v.bytes=$stake |
.fields[1].map[1].v.map[1].v.bytes=$lock |
.fields[1].map[1].v.map[2].v.bytes=$vault' \
./scripts/data/dao/updated-dao-datum.json | sponge ./scripts/data/dao/updated-dao-datum.json

# end of build
echo -e "\033[1;32m Building Complete! \033[0m"