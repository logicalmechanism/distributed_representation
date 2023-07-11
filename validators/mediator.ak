use aiken/interval
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
use distributed_representation/threshold
use distributed_representation/types.{
  AdvanceMediationState, DAODatum, DisputeMediation, EndMediation, MediatorDatum,
  MediatorRedeemer, RemoveMemberValue, UpdateMemberValue,
}

validator(
  starter_pid: ByteArray,
  starter_tkn: ByteArray,
  dao_hash_data: Data,
  mirror_pid: ByteArray,
) {
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
          UpdateMemberValue { member, value } -> True
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
                // entry or exit only
                list.or([datum.state == 0, datum.state == 3]),
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
            list.and(
              [
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
            // get the reference datum
            expect dao_datum: DAODatum = data.input_datum(dao_input)
            True
          }
          EndMediation -> True
        }
      }
      // anything else fails
      _ -> False
    }
  }
}
