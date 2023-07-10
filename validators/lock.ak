use aiken/list
use aiken/transaction.{ScriptContext, Spend}
use aiken/transaction/value
use assist/count
use assist/find
use distributed_representation/types

fn is_minting(
  flat: List<(ByteArray, ByteArray, Int)>,
  pid: ByteArray,
  tkn: ByteArray,
) -> Bool {
  when flat is {
    // loop the minted value
    [(policy, token_name, _), ..rest] ->
      if list.and([policy == pid, token_name == tkn]) == True {
        True
      } else {
        is_minting(rest, pid, tkn)
      }
    // something wasn't found
    [] -> error @"Not Minting"
  }
}

validator(mirror_pid: ByteArray) {
  fn params(_datum: Void, _redeemer: Void, context: ScriptContext) -> Bool {
    when context.purpose is {
      Spend(output_reference) -> {
        // tx being validated
        let tx = context.transaction
        let this_input = find.input_by_ref(tx.inputs, output_reference)
        let this_addr = this_input.output.address
        let mint =
          tx.mint
            |> value.from_minted_value()
            |> value.flatten()
        list.and(
          [
            is_minting(mint, mirror_pid, types.token_name),
            // single script input
            count.inputs_by_addr(tx.inputs, this_addr, 1),
            // single script output
            count.outputs_by_addr(tx.outputs, this_addr, 1),
          ],
        )
      }
      // can only spend
      _ -> False
    }
  }
}
