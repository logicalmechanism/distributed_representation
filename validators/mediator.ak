use aiken/dict
use aiken/interval
use aiken/list
use aiken/transaction.{ScriptContext, Spend}
use aiken/transaction/value
use assist/count
use assist/find
use assist/payout
use assist/signing
use distributed_representation/threshold
use distributed_representation/types.{
  AdvanceMediationState, DisputeMediation, EndMediation, MediatorDatum,
  MediatorRedeemer, RemoveMemberValue, UpdateMemberValue,
}

validator(mirror_pid: ByteArray) {
  fn params(
    datum: MediatorDatum,
    redeemer: MediatorRedeemer,
    context: ScriptContext,
  ) -> Bool {
    when context.purpose is {
      Spend(output_reference) -> {
        // the transaction being validated
        let tx = context.transaction
        let this_input = find.input_by_ref(tx.inputs, output_reference)
        let this_value = this_input.output.value
        let this_addr = this_input.output.address
        when redeemer is {
          UpdateMemberValue { member, value } -> {
            let cont_value = value.merge(this_value, value)
            // the datum going back to the vault
            expect cont_datum: MediatorDatum =
              find.output_datum_by_addr(tx.outputs, this_addr)
            list.and(
              [
                // datum validation
                types.update_member_check(datum, cont_datum, member, value),
                // owner must sign it
                signing.verify_sig(tx.extra_signatories, member),
                // entry state only
                datum.state == 0,
                // add ada to the utxo
                payout.exact(this_addr, cont_value, tx.outputs),
                // single script input
                count.inputs_by_addr(tx.inputs, this_addr, 1),
                // single script output
                count.outputs_by_addr(tx.outputs, this_addr, 1),
              ],
            )
          }
          RemoveMemberValue { member } -> {
            let current_value = types.find_member(datum.members, member)
            let cont_value =
              value.merge(this_value, value.negate(current_value))
            // the datum going back to the vault
            expect cont_datum: MediatorDatum =
              find.output_datum_by_addr(tx.outputs, this_addr)
            list.and(
              [
                // datum validation
                types.remove_member_check(datum, cont_datum, member),
                // owner must sign it
                signing.verify_sig(tx.extra_signatories, member),
                // entry or exit state only
                list.or([datum.state == 0, datum.state >= 3]),
                // add ada to the utxo
                payout.exact(this_addr, cont_value, tx.outputs),
                // single script input
                count.inputs_by_addr(tx.inputs, this_addr, 1),
                // single script output
                count.outputs_by_addr(tx.outputs, this_addr, 1),
              ],
            )
          }
          AdvanceMediationState -> {
            // how much they have inside the tx
            let enough_for_threshold =
              threshold.count_token_by_pid(tx.inputs, mirror_pid, 0) >= datum.threshold
            let validity = tx.validity_range
            let time_lock =
              interval.between(datum.time_lock.start, datum.time_lock.end)
            // the datum going back to the vault
            expect cont_datum: MediatorDatum =
              find.output_datum_by_addr(tx.outputs, this_addr)
            list.and(
              [
                types.advance_state_check(datum, cont_datum),
                // can not be in dispute state
                datum.state != 2,
                // must hold enough tokens
                enough_for_threshold,
                // add ada to the utxo
                payout.exact(this_addr, this_value, tx.outputs),
                // single script input
                count.inputs_by_addr(tx.inputs, this_addr, 1),
                // single script output
                count.outputs_by_addr(tx.outputs, this_addr, 1),
                // can be
                interval.intersection(validity, time_lock)
                  |> interval.is_empty,
              ],
            )
          }
          DisputeMediation -> {
            // the datum going back to the vault
            expect cont_datum: MediatorDatum =
              find.output_datum_by_addr(tx.outputs, this_addr)
            let validity = tx.validity_range
            let time_lock =
              interval.between(datum.time_lock.start, datum.time_lock.end)
            list.and(
              [
                types.value_change_check(datum.members, cont_datum.members),
                // must be in dispute state
                datum.state == 2,
                // a multsig member witness
                signing.verify_multisig(
                  tx.extra_signatories,
                  dict.keys(datum.members),
                  datum.sig_threshold,
                ),
                // add ada to the utxo
                payout.exact(this_addr, this_value, tx.outputs),
                // single script input
                count.inputs_by_addr(tx.inputs, this_addr, 1),
                // single script output
                count.outputs_by_addr(tx.outputs, this_addr, 1),
                // can be spent
                interval.intersection(validity, time_lock)
                  |> interval.is_empty,
              ],
            )
          }
          EndMediation -> {
            // how much they have inside the tx
            let enough_for_threshold =
              threshold.count_token_by_pid(tx.inputs, mirror_pid, 0) >= datum.threshold
            let total_current_value = types.total_member_value(datum.members)
            list.and(
              [
                // needs to be empty
                (total_current_value == value.zero())?,
                // must hold enough tokens
                enough_for_threshold?,
                // single script input
                count.inputs_by_addr(tx.inputs, this_addr, 1),
                // single script output
                count.outputs_by_addr(tx.outputs, this_addr, 0),
                // entry or exit state only
                list.or([datum.state == 0, datum.state >= 3])?,
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
