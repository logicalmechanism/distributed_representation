//// This handles tokens for the casino

use aiken/list
use aiken/transaction.{Mint, ScriptContext}
use aiken/transaction/credential
use aiken/transaction/value
use assist/data
use assist/find
use assist/minting
use assist/values
use distributed_representation/keys
use distributed_representation/threshold
use distributed_representation/types.{
  BurnTokens, DAODatum, MintRedeemer, MintTokens, Thresholds,
}

validator(
  starter_pid: ByteArray,
  starter_tkn: ByteArray,
  dao_hash_data: Data,
  mirror_pid: ByteArray,
) {
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
    // create the token name
    // get tx info
    let first_index = find.first_input_index(tx.inputs)
    let first_tx_hash = find.first_input_txid(tx.inputs)
    // use the token prefix
    let tkn =
      values.unique_token_name(first_tx_hash, first_index, types.token_prefix)
    // searcht he contracts for the bank lock and stake
    expect threshold_data: Thresholds =
      types.find_data(dao_datum.data, keys.thresholds)
    // must have this must mirror token to mint
    let mint_threshold =
      types.find_threshold(threshold_data, keys.mint_threshold)
    // how much they have inside the tx
    let enough_for_threshold =
      threshold.count_token_by_pid(tx.inputs, mirror_pid, 0) >= mint_threshold
    // what is being minted or burned in this transaction
    let mint =
      tx.mint
        |> value.from_minted_value()
        |> value.flatten()
    when context.purpose is {
      // Mint 1 to 1 tokens
      Mint(own_currency_symbol) ->
        when redeemer is {
          MintTokens { mint_amt } ->
            list.and(
              [
                // must have enough mirror token
                enough_for_threshold,
                // nft only
                mint_amt == 1,
                // must mint 1 reference token
                minting.exact(mint, own_currency_symbol, tkn, mint_amt),
                // data reference must be holding correct token
                dao_value_check,
              ],
            )
          BurnTokens { burn_amt } ->
            list.and(
              [
                // must have enough mirror token
                enough_for_threshold,
                // nft only
                burn_amt == 1,
                // burn only 1 ref token
                minting.by_prefix(
                  mint,
                  own_currency_symbol,
                  types.token_prefix,
                  -burn_amt,
                ),
                // data reference must be holding correct token
                dao_value_check,
              ],
            )
        }
      // Minting Only
      _ -> False
    }
  }
}
