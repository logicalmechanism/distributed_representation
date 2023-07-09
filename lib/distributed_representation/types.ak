///////////////////////////////////////////////////////////////////////////////

use aiken/dict.{Dict}
use aiken/hash.{Blake2b_224, Hash}
use aiken/transaction/credential.{PoolId, Script, VerificationKey}

// General Types

// token_name == lovelace
pub const token_name = #"6c6f76656c616365"

// token_prefix == TheDAO
pub const token_prefix = #"7e44414f"

pub type PublicKeyHash =
  Hash<Blake2b_224, VerificationKey>

// script hash
pub type ValidatorHash =
  Hash<Blake2b_224, Script>

// Contract types
pub type Thresholds =
  Dict<ByteArray, Int>

// find a threshold by some key inside the thresholds dictionary.
pub fn find_threshold(thresholds: Thresholds, key: ByteArray) -> Int {
  when dict.get(thresholds, key) is {
    Some(amt) -> amt
    None -> error @"Threshold Not Found"
  }
}

// Contract types
pub type Contracts =
  Dict<ByteArray, ValidatorHash>

// find a worker by job title inside the worker hot key dictionary.
pub fn find_contract(contracts: Contracts, key: ByteArray) -> ValidatorHash {
  when dict.get(contracts, key) is {
    Some(thing) -> thing
    None -> error @"Contract Not Found"
  }
}

// general data type for the reps data
pub type DAOData =
  Dict<ByteArray, Data>

// find a data structure by a title inside the DAOData dictionary.
pub fn find_data(data: DAOData, key: ByteArray) -> Data {
  when dict.get(data, key) is {
    Some(thing) -> thing
    None -> error @"Data Not Found"
  }
}

// who runs the contract is the multisig
pub type ManagementData {
  pkhs: List<PublicKeyHash>,
  threshold: Int,
}

pub type DAODatum {
  management: ManagementData,
  data: DAOData,
}

// only can remove or update
pub type DAORedeemer {
  UpdateManagement { lovelace: Int, direction: Int }
  UpdateDAOData { lovelace: Int, direction: Int }
}

// Stake Information

// staking info
pub type StakePoolData {
  pool_id: PoolId,
}

pub type StakeData {
  stake_cred: ValidatorHash,
}

pub type StakeRedeemer {
  Withdraw
  Delegate(StakeData)
}

// Mint Information
pub type MintRedeemer {
  MintTokens { mint_amt: Int }
  BurnTokens { burn_amt: Int }
}

// Vault Information
pub type VaultRedeemer {
  AddToVault { add_amt: Int }
  SubFromVault { sub_amt: Int }
}
