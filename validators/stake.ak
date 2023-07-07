//// This handles staking for the casino

use aiken/list
use aiken/transaction.{Publish, ScriptContext, WithdrawFrom}
use aiken/transaction/certificate.{CredentialDelegation}
use aiken/transaction/credential.{Inline, ScriptCredential}
use aiken/transaction/value
use assist/addresses
use assist/data
use assist/find
use assist/payout
use assist/values
use distributed_representation/keys
use distributed_representation/types.{
  DAODatum, Delegate, StakePoolData, StakeRedeemer, Withdraw,
}

// random_string is for initilizing different stake keys attached to the same starter token
validator(
  starter_pid: ByteArray,
  starter_tkn: ByteArray,
  dao_hash_data: Data,
  _random_string: ByteArray,
) {
  fn params(redeemer: StakeRedeemer, context: ScriptContext) -> Bool {
    let tx = context.transaction
    // get reference utxo
    expect dao_hash: ByteArray = dao_hash_data
    let dao_addr = credential.from_script(dao_hash)
    let dao_input = find.input_by_addr(tx.reference_inputs, dao_addr)
    // check if the ref input has the correct starter token
    let dao_value_check =
      values.prove_exact_nft(starter_pid, starter_tkn, dao_input.output.value)
    // get the reference datum
    expect dao_datum: DAODatum = data.input_datum(dao_input)
    expect stake_pool_data: StakePoolData =
      types.find_data(dao_datum.data, keys.staking)
    when context.purpose is {
      // handle all withdrawals
      WithdrawFrom(stake_credential) -> {
        // get the vault information
        let reward_addr =
          addresses.create_address(
            stake_pool_data.reward_pkh,
            stake_pool_data.reward_sc,
          )
        let reward = find.stake_reward_by_sc(tx.withdrawals, stake_credential)
        when redeemer is {
          // can only withdraw
          Withdraw ->
            list.and(
              [
                // data reference must hold correct token
                dao_value_check,
                // reward address must be paid the exact reward
                payout.at_least(
                  reward_addr,
                  value.from_lovelace(reward),
                  tx.outputs,
                ),
              ],
            )
          // all else fails
          _ -> False
        }
      }
      // handle all delegation certs
      Publish(certificate) ->
        when redeemer is {
          // only delegate to secific pool
          Delegate(sd) -> {
            let new_delegation =
              CredentialDelegation {
                delegator: Inline(ScriptCredential(sd.stake_cred)),
                delegatee: stake_pool_data.pool_id,
              }
            list.and(
              [
                // this may need to have a multisig from management
                // data reference must hold correct token
                dao_value_check,
                // The only cert is for new delegation
                certificate == new_delegation,
              ],
            )
          }
          // deregistration fails and anything else but changing delegation
          _ -> False
        }
      // no other script purposes
      _ -> False
    }
  }
}
