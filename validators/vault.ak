//// This stores profit for the casino
//// This handles locking ada for the casino

use aiken/list
use aiken/transaction.{ScriptContext, Spend}
use aiken/transaction/credential
use aiken/transaction/value
use assist/count
use assist/data
use assist/find
use assist/payout
use assist/signing
use assist/values
use distributed_representation/types.{
  AddToVault, DAODatum, SubFromVault, VaultRedeemer,
}

validator(starter_pid: ByteArray, starter_tkn: ByteArray, dao_hash_data: Data) {
  fn params(
    datum: Void,
    redeemer: VaultRedeemer,
    context: ScriptContext,
  ) -> Bool {
    when context.purpose is {
      Spend(output_reference) -> {
        // tx being validated
        let tx = context.transaction
        let this_input = find.input_by_ref(tx.inputs, output_reference)
        let this_value = this_input.output.value
        let this_addr = this_input.output.address
        // the datum going back to the vault
        expect cont_datum: Void =
          find.output_datum_by_addr(tx.outputs, this_addr)
        when redeemer is {
          AddToVault { add_amt } -> {
            let cont_value =
              value.add(
                this_value,
                value.ada_policy_id,
                value.ada_asset_name,
                add_amt,
              )
            list.and(
              [
                (datum == cont_datum)?,
                // add ada to the utxo
                payout.exact(this_addr, cont_value, tx.outputs)?,
                // single script input
                count.inputs_by_addr(tx.inputs, this_addr, 1)?,
                // single script output
                count.outputs_by_addr(tx.outputs, this_addr, 1)?,
              ],
            )
          }

          SubFromVault { sub_amt } -> {
            let cont_value =
              value.add(
                this_value,
                value.ada_policy_id,
                value.ada_asset_name,
                -sub_amt,
              )
            // get reference utxo
            expect dao_hash: ByteArray = dao_hash_data
            let dao_addr = credential.from_script(dao_hash)
            let dao_input = find.input_by_addr(tx.reference_inputs, dao_addr)
            // check if the ref input has the correct starter token
            let dao_value_check =
              values.prove_exact_nft(
                starter_pid,
                starter_tkn,
                dao_input.output.value,
              )
            // get the house datum
            expect dao_datum: DAODatum = data.input_datum(dao_input)
            list.and(
              [
                // hold right token
                dao_value_check,
                // datum doesnt change
                datum == cont_datum,
                // add ada to the utxo
                payout.exact(this_addr, cont_value, tx.outputs),
                // single script input
                count.inputs_by_addr(tx.inputs, this_addr, 1),
                // single script output
                count.outputs_by_addr(tx.outputs, this_addr, 1),
                // valid multisig
                signing.verify_multisig(
                  tx.extra_signatories,
                  dao_datum.management.pkhs,
                  dao_datum.management.threshold,
                ),
              ],
            )
          }
        }
      }
      // anything else fails
      _ -> False
    }
  }
}
