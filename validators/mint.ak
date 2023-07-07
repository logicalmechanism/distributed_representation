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

validator(
  starter_pid: ByteArray,
  starter_tkn: ByteArray,
  house_hash_data: Data,
) {
  fn params(redeemer: MintRedeemer, context: ScriptContext) -> Bool {
    // the transaction being validated
    let tx = context.transaction
    // get reference utxo
    expect house_hash: ByteArray = house_hash_data
    let house_addr = credential.from_script(house_hash)
    let house_input = find.input_by_addr(tx.reference_inputs, house_addr)
    // check if the ref input has the correct starter token
    let house_value_check =
      values.prove_exact_nft(starter_pid, starter_tkn, house_input.output.value)
    // get the reference datum
    expect house_datum: DAODatum = data.input_datum(house_input)
    // searcht he contracts for the bank lock and stake
    expect contract_data: Contracts =
      types.find_data(house_datum.data, keys.contracts)
    let bank_contract = types.find_contract(contract_data, keys.bank_lock)
    let stake_contract = types.find_contract(contract_data, keys.staking)
    // build the address
    let bank_lock_addr =
      addresses.create_script_address(bank_contract, stake_contract)
    // find the input being spent from it
    let bank_input = find.input_by_addr(tx.inputs, bank_lock_addr)
    let bank_value = bank_input.output.value
    // expect correct datum from spent bank input
    // this will error if nothing is found
    expect bank_datum: Void = data.input_datum(bank_input)
    expect cont_bank_datum: Void =
      find.output_datum_by_addr(tx.outputs, bank_lock_addr)
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
                bank_value,
                value.ada_policy_id,
                value.ada_asset_name,
                mint_amt,
              )
            list.and(
              [
                // datum dont change
                bank_datum == cont_bank_datum,
                // make sure the bank lock is being spent from
                payout.exact(bank_lock_addr, cont_value, tx.outputs),
                // must mint 1 reference token
                minting.exact(
                  mint,
                  own_currency_symbol,
                  types.token_name,
                  mint_amt,
                ),
                // data reference must be holding correct token
                house_value_check,
              ],
            )
          }
          BurnTokens { burn_amt } -> {
            let cont_value =
              value.add(
                bank_value,
                value.ada_policy_id,
                value.ada_asset_name,
                -burn_amt,
              )
            list.and(
              [
                // datum dont change
                bank_datum == cont_bank_datum,
                // make sure the bank lock is being spent from
                payout.exact(bank_lock_addr, cont_value, tx.outputs),
                // burn only 1 ref token
                minting.exact(
                  mint,
                  own_currency_symbol,
                  types.token_name,
                  -burn_amt,
                ),
                // data reference must be holding correct token
                house_value_check,
              ],
            )
          }
        }
      // Minting Only
      _ -> False
    }
  }
}
