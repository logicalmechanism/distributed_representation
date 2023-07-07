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
use assist/signing
use assist/values
use distributed_representation/keys
use distributed_representation/types.{
  AddToVault, Contracts, DAODatum, Delegate, StakePoolData, StakeRedeemer,
  VaultRedeemer, Withdraw,
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
        expect contract_data: Contracts =
          types.find_data(dao_datum.data, keys.contracts)
        let vault_contract = types.find_contract(contract_data, keys.vault)
        let stake_contract = types.find_contract(contract_data, keys.staking)
        // build the vault address
        let vault_addr =
          addresses.create_script_address(vault_contract, stake_contract)
        let vault_input = find.input_by_addr(tx.inputs, vault_addr)
        let vault_value = vault_input.output.value
        let reward = find.stake_reward_by_sc(tx.withdrawals, stake_credential)
        // add reward amount to the vault value
        let cont_value =
          value.add(
            vault_value,
            value.ada_policy_id,
            value.ada_asset_name,
            reward,
          )
        // this should fail for bad redeemer data
        expect vault_redeemer: VaultRedeemer =
          find.redeemer_by_ref(tx.redeemers, vault_input.output_reference)
        let good_redeemer_check =
          when vault_redeemer is {
            // must add to vault
            AddToVault { add_amt: _ } -> True
            _ -> error @"Bad Redeemer"
          }
        when redeemer is {
          // can only withdraw
          Withdraw ->
            list.and(
              [
                // must be calling add to vault
                good_redeemer_check,
                // data reference must hold correct token
                dao_value_check,
                // reward address must be paid the exact reward
                payout.exact(vault_addr, cont_value, tx.outputs),
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
                // valid multisig
                signing.verify_multisig(
                  tx.extra_signatories,
                  dao_datum.management.pkhs,
                  dao_datum.management.threshold,
                ),
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
