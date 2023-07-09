# Distributed Representation For Catalyst Voting

A proof of concept that models a semi-liquid `mint-lock-stake` DAO designed to collect Lovelace for threshold based actions. The semi-liquid nature allows the purchasing power of the token, given to the delegator, to still be used as if it was lovelace as it represents a one-to-one lovelace connection.

# Building

The dao data contract assumes a starter NFT will be provided at compile time. This information is contained in the `start_info.json` file.

```json
{
  "__comment1__": "This is the starter token for the data reference contract.",
  "starterPid": "d71d15d49f1cb409d0f3863188909af20da621b8e2baa7caae722d0e",
  "starterTkn": "9877cd0707f500970050fb0216090b080862ad16c421a3212d6f6350602beda6",
  "__comment2__": "The stake will delegate to this pool id.",
  "poolId": "8ffb4c8e648c0662f2a91157c92feaa95f1a3d2728eaea8257b3d8d9",
  "__comment3__": "A random string to use for stake key generation.",
  "random": "acab"
}
```

Update rust and aiken, remove the old build folder, then run the complete build script.

```bash
rustup update
aikup
rm -fr build/ || true
./complete_build.sh
```

# Set Up

The `scripts` folder provides a happy path to follow as well as all the wallet and datum / redeemer information. The test scripts will allow the DAO to update the multisig and data, the stake to be delegated and rewarded, and the ability to mint and burn tokens. There can only be one DAO data UTxO by design but there can be many stake and lock contracts, allowing for sharding for greater efficiency.

## Wallets

The happy path assumes there are specific wallets that exist and are funded with enough lovelace to pay for the transaction fees.

```bash
./create_wallet.sh wallets/collat-wallet
./create_wallet.sh wallets/delegator-wallet
./create_wallet.sh wallets/keeper1-wallet
./create_wallet.sh wallets/keeper2-wallet
./create_wallet.sh wallets/keeper3-wallet
./create_wallet.sh wallets/reference-wallet
./create_wallet.sh wallets/reward-wallet
./create_wallet.sh wallets/starter-wallet
```

The balances can be viewed with `./all_balances.sh`.

## Reference Scripts

After the wallets are funded, the reference wallet will need to pay to create the script references for the happy path.

```bash
./00_createScriptReferences.sh
```

This will auto chain all the script references together.


## Data Contract

Inside the `dao` folder are all the scripts for updating the mutlisig and data. The scripts update from the `data/dao/update-dao-datum.json` file so any changes will need to made to that file for dao updates.

Use the `starter` wallet and create the dao UTxO.

```bash
./01_createDAOUTxO.sh
```

The multisig is updated with `02_updateManagement.sh` and the data is updated with `03_updateData.json`.

## Stake Contract

Inside the `stake` folder are all the scripts for registering, delegating, and withdrawing from the stake contract. The stake contract can only be delegated to the pool id and be rewarded to the reward address inside the dao data.

Use the `starter` wallet and register the stake contract.

```bash
./01_registerStake.sh
```

The stake can be delegated with `02_delegateStake.sh` and rewards can be withdrawn with `03_withdrawStakeRewards.json`.

## Vault Contract

Inside the `vault` folder are all the scripts for creating, adding, and subtracting from the vault contract. The vault is design to accumulate rewards and profit for the dao.

Use the `starter` wallet and register the stake contract.

```bash
./01_createVaultUTxO.sh
```

The stake can be delegated with `02_addToVault.sh` and rewards can be withdrawn with `03_subFromVault.json`.

## Minting Tokens

Inside the `mint` folder are all the scripts for creating the lock UTxO and minting and burning tokens. There can be any number of lock UTxOs but only one is needed for the happy path.

Use the `starter` wallet and start the lock contract.

```bash
./01_createLockUTxO.sh
```

The `delegator` wallet can be used to mint and burn tokens. The tokens are one-to-one with lovelace.

For example the delegator can mint 123456789 "lovelace" into their wallet and will lock 123456789 lovelace into the lock contract.

```bash
./02_mintTokens.sh 123456789
```

The delegator may also burn their tokens and get their lovelace back.

```bash
./03_burnTokens.sh 123456789
```

This will burn 123456789 "lovelace" from their wallet and will unlock 123456789 lovelace from the lock contract.

Now with many lock contracts, many delegators may place their ada into the lock contract in exchange for the token. The DAO will now control the staking power of the locked lovelace but the delegators control their buying power with their "lovelace" token. At any time, delegators may return to retrieve their lovelace from the contract and regain control of their staking power.

# Threshold-Based Actions

Now that users have the "lovelace", they may act on the behalf of the DAO with the available threshold-based actions. Each action requires a certain amount of the "lovelace" to be inside the transaction, proving that the user(s) has/have enough contribution to the DAO to be able to act. This system allows for many different actions to be built and added to the ecosystem without any required hardforks to the original data or mint/lock contract as these contracts depend solely on policy id of "lovelace". But each new action will require an update to the dao data as each action has its own threshold requirement.

## NFT Minting

An NFT is allowed to be minted or burned if and only if the transaction contains inputs that hold a minimum amount of "lovelace". The user(s) that create this transaction may do as they please with the NFT. Each NFT is prefixed with "~DAO".

This will mint an NFT into the delegator wallet if and only if the delegator has enough "lovelace".

```bash
./01_mintNFT.sh
```

This will burn an NFT from the delegator wallet if and only if the delegator has enough "lovelace".

```bash
./02_burnNFT.sh
```