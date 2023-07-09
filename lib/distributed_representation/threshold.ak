use aiken/list
use aiken/transaction.{
  InlineDatum, Input, Output, OutputReference, TransactionId,
}
use aiken/transaction/value
use assist/addresses
use distributed_representation/types

/// Count how many tokens are inside the inputs by a specific pid. The token
/// name is assumed to be the mirror token name defined in types.
///
pub fn count_token_by_pid(
  inputs: List<Input>,
  pid: ByteArray,
  counter: Int,
) -> Int {
  when inputs is {
    [input, ..rest] -> {
      let amt = value.quantity_of(input.output.value, pid, types.token_name)
      count_token_by_pid(rest, pid, counter + amt)
    }
    [] -> counter
  }
}

/// A fake input used for testing.
fn test_inputs(amt: Int) -> List<Input> {
  let input =
    Input {
      output_reference: OutputReference {
        transaction_id: TransactionId { hash: #"acab" },
        output_index: 0,
      },
      output: Output {
        address: addresses.create_address(#"acab", #""),
        value: value.from_asset(#"acab", types.token_name, 100),
        datum: InlineDatum(#""),
        reference_script: None,
      },
    }
  list.repeat(input, amt)
}

test count_pid1() {
  let amt = 1
  let inputs = test_inputs(amt)
  count_token_by_pid(inputs, #"acab", 0) == amt * 100
}

test count_pid2() {
  let amt = 2
  let inputs = test_inputs(amt)
  count_token_by_pid(inputs, #"acab", 0) == amt * 100
}

test count_pid3() {
  let amt = 4
  let inputs = test_inputs(amt)
  count_token_by_pid(inputs, #"acab", 0) == amt * 100
}

test count_pid4() {
  let amt = 8
  let inputs = test_inputs(amt)
  count_token_by_pid(inputs, #"acab", 0) == amt * 100
}

test count_pid5() {
  let amt = 16
  let inputs = test_inputs(amt)
  count_token_by_pid(inputs, #"acab", 0) == amt * 100
}
