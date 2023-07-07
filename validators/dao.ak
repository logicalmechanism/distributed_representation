//// This handles the house for the casino

use aiken/list
use aiken/transaction.{ScriptContext, Spend}
use aiken/transaction/value
use assist/count
use assist/find
use assist/payout
use assist/signing
use assist/values
use distributed_representation/types.{
  DAODatum, DAORedeemer, UpdateDAOData, UpdateManagement,
}

validator(starter_pid: ByteArray, starter_tkn: ByteArray) {
  fn params(
    datum: DAODatum,
    redeemer: DAORedeemer,
    context: ScriptContext,
  ) -> Bool {
    when context.purpose is {
      Spend(output_reference) -> {
        // tx being validated
        let tx = context.transaction
        let this_input = find.input_by_ref(tx.inputs, output_reference)
        // this value
        let this_value = this_input.output.value
        let this_addr = this_input.output.address
        // the datum cont
        expect cont_datum: DAODatum =
          find.output_datum_by_addr(tx.outputs, this_addr)
        // utxo must have starter token
        let starter_token_check =
          values.prove_exact_nft(starter_pid, starter_tkn, this_value)
        when redeemer is {
          UpdateManagement { lovelace, direction } -> {
            // length of new management
            let l = list.length(cont_datum.management.pkhs)
            // threshold of new management
            let t = cont_datum.management.threshold
            // set a direction for add and remove
            let increase_value = value.from_lovelace(lovelace)
            let cont_value =
              when direction is {
                // addition
                0 -> value.merge(this_value, increase_value)
                // subtract
                _ -> value.merge(this_value, value.negate(increase_value))
              }
            // validate for a safe update to the multisig
            list.and(
              [
                // send back to script but a change in the lovelace
                payout.exact(this_addr, cont_value, tx.outputs),
                // single script input
                count.inputs_by_addr(tx.inputs, this_addr, 1),
                // single script output
                count.outputs_by_addr(tx.outputs, this_addr, 1),
                // valid multisig
                signing.verify_multisig(
                  tx.extra_signatories,
                  datum.management.pkhs,
                  datum.management.threshold,
                ),
                // logical thresholds only
                l >= t,
                // Must have at least one
                l > 0,
                // data is constant
                datum.data == cont_datum.data,
                // holding official token
                starter_token_check,
              ],
            )
          }
          UpdateDAOData { lovelace, direction } -> {
            // set a direction for add and remove
            let increase_value = value.from_lovelace(lovelace)
            let cont_value =
              when direction is {
                // add
                0 -> value.merge(this_value, increase_value)
                // subtract
                _ -> value.merge(this_value, value.negate(increase_value))
              }
            // Only update the data for the house
            list.and(
              [
                // send back to script but a change in the lovelace
                payout.exact(this_addr, cont_value, tx.outputs),
                // single script input
                count.inputs_by_addr(tx.inputs, this_addr, 1),
                // single script output
                count.outputs_by_addr(tx.outputs, this_addr, 1),
                // valid multisig
                signing.verify_multisig(
                  tx.extra_signatories,
                  datum.management.pkhs,
                  datum.management.threshold,
                ),
                // data is constant
                datum.management == cont_datum.management,
                // holding official token
                starter_token_check,
              ],
            )
          }
        }
      }
      _ -> False
    }
  }
}
