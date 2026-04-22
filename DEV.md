
# Cartouche Development Doc

## Generating Cartouche contracts

* `i_console.ex`
  * `mix cartouche.gen --prefix cartouche/contract ./sol/out/IConsole.sol/IConsole.json`
* `sleuth.ex`
  * Clone [sleuth](https://github.com/compound-finance/sleuth) and 
  * `mix cartouche.gen --prefix cartouche/contract ../sleuth/out/Sleuth.sol/Sleuth.json`
* `test/support/{block_number,ierc20,rock}.ex`
  * `mix cartouche.gen --prefix cartouche/contract --out ./test/support/ ./test/abi/*.json`
