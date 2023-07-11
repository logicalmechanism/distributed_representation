use aiken/bytearray
use aiken/dict.{Dict}
use aiken/hash.{Blake2b_224, Hash}
use aiken/list
use aiken/transaction/credential.{PoolId, Script, VerificationKey}
use aiken/transaction/value.{Value}

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
pub type PolicyIds =
  Dict<ByteArray, ByteArray>

// find a threshold by some key inside the thresholds dictionary.
pub fn find_policy_id(policy_ids: PolicyIds, key: ByteArray) -> ByteArray {
  when dict.get(policy_ids, key) is {
    Some(policy_id) -> policy_id
    None -> error @"Policy ID Not Found"
  }
}

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
  UpdateData { lovelace: Int, direction: Int }
  Petition { lovelace: Int, direction: Int }
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

// Mediator Information
pub type TimeData {
  start: Int,
  end: Int,
  delta: Int,
}

pub fn check_valid_time_data(t: TimeData) -> Bool {
  t.start <= t.end && t.start + t.delta == t.end
}

pub fn check_valid_time_change(t1: TimeData, t2: TimeData) -> Bool {
  list.and(
    [
      check_valid_time_data(t1),
      check_valid_time_data(t2),
      t1.delta == t2.delta,
      t1.end + t1.delta == t2.start,
    ],
  )
}

// Member type
pub type MemberData =
  Dict<PublicKeyHash, Value>

// find a data structure by a title inside the DAOData dictionary.
pub fn find_member(members: MemberData, key: PublicKeyHash) -> Value {
  when dict.get(members, key) is {
    Some(value) -> value
    None -> error @"Member Not Found"
  }
}

pub fn total_member_value(self: MemberData) -> Value {
  dict.foldl(self, value.zero(), fn(_k, v, r) { value.merge(r, v) })
}

pub type MediatorDatum {
  members: MemberData,
  // zero = entry, one = mediation, two = dispute, three = exit
  state: Int,
  time_lock: TimeData,
  // a threshold for the mirror token that is locally defined and not dao defined
  threshold: Int,
  // a sig threshold for mediation but not in the dao data
  sig_threshold: Int,
}

pub fn remove_member_check(
  a: MediatorDatum,
  b: MediatorDatum,
  member: PublicKeyHash,
) -> Bool {
  let member_value = find_member(b.members, member)
  list.and(
    [
      a.state == b.state,
      a.threshold == b.threshold,
      a.time_lock == b.time_lock,
      member_value == value.zero(),
    ],
  )
}

pub fn update_member_check(
  a: MediatorDatum,
  b: MediatorDatum,
  member: PublicKeyHash,
  value: Value,
) -> Bool {
  let new_members =
    dict.insert(
      self: a.members,
      key: member,
      value: value,
      compare: bytearray.compare,
    )
  list.and(
    [
      a.state == b.state,
      a.threshold == b.threshold,
      a.time_lock == b.time_lock,
      new_members == b.members,
    ],
  )
}

test similar_lists1() {
  let x =
    [1, 2, 3]
  let y =
    [3, 2, 1]
  list.and(list.map(x, fn(n) { list.has(y, n) }))
}

test similar_lists2() {
  let x =
    []
  let y =
    []
  list.and(list.map(x, fn(n) { list.has(y, n) }))
}

test similar_dicts1() {
  let left_dict =
    dict.from_list([(#"ab", 100), (#"cd", 200)], bytearray.compare)
  let right_dict =
    dict.from_list([(#"ab", 150), (#"cd", 300)], bytearray.compare)

  let result =
    dict.union_with(
      left_dict,
      right_dict,
      fn(_k, _v1, v2) { Some(v2) },
      bytearray.compare,
    )
  result == right_dict
}

test similar_dicts2() {
  let left_dict =
    dict.from_list([(#"ab", 100), (#"cd", 200)], bytearray.compare)
  let right_dict =
    dict.from_list([(#"ad", 150), (#"cd", 300)], bytearray.compare)

  let result =
    dict.union_with(
      left_dict,
      right_dict,
      fn(_k, _v1, v2) { Some(v2) },
      bytearray.compare,
    )
  result != right_dict
}

pub fn value_change_check(a: MemberData, b: MemberData) -> Bool {
  let a_keys = dict.keys(a)
  let b_keys = dict.keys(b)
  list.and(
    [
      // check if all the keys remain in the member list
      list.and(list.map(a_keys, fn(k) { list.has(b_keys, k) })),
      // the values may change but the total remains conserved
      total_member_value(a) == total_member_value(b),
    ],
  )
}

pub fn advance_state_check(a: MediatorDatum, b: MediatorDatum) -> Bool {
  let member_check =
    if a.state == 1 {
      // this may be cheaper?
      // let result =
      //   dict.union_with(
      //     a.members,
      //     b.members,
      //     fn(_k, _v1, v2) { Some(v2) },
      //     bytearray.compare,
      //   )
      // list.and(
      //   [
      //     // check if all the keys remain in the member list
      //     result == b.members,
      //     // the values may change but the total remains conserved
      //     total_member_value(a.members) == total_member_value(b.members),
      //   ],
      // )
      // let a_keys = dict.keys(a.members)
      // let b_keys = dict.keys(b.members)
      // list.and(
      //   [
      //     // check if all the keys remain in the member list
      //     list.and(list.map(a_keys, fn(k) { list.has(b_keys, k) })),
      //     // the values may change but the total remains conserved
      //     total_member_value(a.members) == total_member_value(b.members),
      //   ],
      // )
      value_change_check(a.members, b.members)
    } else {
      a.members == b.members
    }
  list.and(
    [
      a.state + 1 == b.state,
      a.threshold == b.threshold,
      check_valid_time_change(a.time_lock, b.time_lock),
      member_check,
    ],
  )
}

pub type MediatorRedeemer {
  UpdateMemberValue { member: PublicKeyHash, value: Value }
  RemoveMemberValue { member: PublicKeyHash }
  AdvanceMediationState
  DisputeMediation
  EndMediation
}
