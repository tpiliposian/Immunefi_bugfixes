# Immunefi Bug Fixes

This repository documents research on critical bug fixes identified on Immunefi in 2023-2024, highlighting how these vulnerabilities were exploited, their impact on projects, and the subsequent fixes implemented. The goal is to provide insights into common pitfalls, remediation strategies, and lessons learned from real-world bug bounty reports.

# 1. Raydium - Tick Manipulation

Reported by: @riproprip

Protocol: Raydium

Date: January 10, 2024

Bounty: $505,000 in RAY tokens

Raydium is an AMM with an integrated central order book system. Users can provide liquidity, perform swaps on the exchange, and stake the RAY token for additional yield.
A fundamental aspect of Raydium is the Concentrated Liquidity Market Maker (CLMM).

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



# 2. Yield Protocol - Logic Error

Reported by: @Paludo0x

Protocol: Yield

Date: April 28th, 2023

Bounty: $95,000 USDC

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
