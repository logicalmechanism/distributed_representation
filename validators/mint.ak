//// This handles tokens for the casino

use aiken/list
use aiken/transaction.{Mint, ScriptContext}
use aiken/transaction/credential
use aiken/transaction/value
use assist/addresses
use assist/data
use assist/find
use assist/minting
use assist/payout
use assist/values
use distributed_representation/keys
use distributed_representation/types.{
  BurnTokens, Contracts, DAODatum, MintRedeemer, MintTokens,
}

validator(starter_pid: ByteArray, starter_tkn: ByteArray, dao_hash_data: Data) {
  fn params(redeemer: MintRedeemer, context: ScriptContext) -> Bool {
    // the transaction being validated
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
    // searcht he contracts for the bank lock and stake
    expect contract_data: Contracts =
      types.find_data(dao_datum.data, keys.contracts)
    let lock_contract = types.find_contract(contract_data, keys.lock)
    let stake_contract = types.find_contract(contract_data, keys.staking)
    // build the address
    let lock_addr =
      addresses.create_script_address(lock_contract, stake_contract)
    // find the input being spent from it
    let lock_input = find.input_by_addr(tx.inputs, lock_addr)
    let lock_value = lock_input.output.value
    // expect correct datum from spent lock input
    // this will error if nothing is found
    expect lock_datum: Void = data.input_datum(lock_input)
    expect cont_lock_datum: Void =
      find.output_datum_by_addr(tx.outputs, lock_addr)
    // what is being minted or burned in this transaction
    let mint =
      tx.mint
        |> value.from_minted_value()
        |> value.flatten()
    when context.purpose is {
      // Mint 1 to 1 tokens
      Mint(own_currency_symbol) ->
        when redeemer is {
          MintTokens { mint_amt } -> {
            let cont_value =
              value.add(
                lock_value,
                value.ada_policy_id,
                value.ada_asset_name,
                mint_amt,
              )
            list.and(
              [
                // datum dont change
                lock_datum == cont_lock_datum,
                // make sure the bank lock is being spent from
                payout.exact(lock_addr, cont_value, tx.outputs),
                // must mint 1 reference token
                minting.exact(
                  mint,
                  own_currency_symbol,
                  types.token_name,
                  mint_amt,
                ),
                // data reference must be holding correct token
                dao_value_check,
              ],
            )
          }
          BurnTokens { burn_amt } -> {
            let cont_value =
              value.add(
                lock_value,
                value.ada_policy_id,
                value.ada_asset_name,
                -burn_amt,
              )
            list.and(
              [
                // datum dont change
                lock_datum == cont_lock_datum,
                // make sure the bank lock is being spent from
                payout.exact(lock_addr, cont_value, tx.outputs),
                // burn only 1 ref token
                minting.exact(
                  mint,
                  own_currency_symbol,
                  types.token_name,
                  -burn_amt,
                ),
                // data reference must be holding correct token
                dao_value_check,
              ],
            )
          }
        }
      // Minting Only
      _ -> False
    }
  }
}
