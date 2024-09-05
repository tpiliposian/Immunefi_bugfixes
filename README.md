# Immunefi Bug Fixes

This repository documents research on critical bug fixes identified on Immunefi in 2023-2024, highlighting how these vulnerabilities were exploited, their impact on projects, and the subsequent fixes implemented. The goal is to provide insights into common pitfalls, remediation strategies, and lessons learned from real-world bug bounty reports.

# 1. Raydium - Tick Manipulation

Reported by: @riproprip

Protocol: Raydium

Date: January 10, 2024

Bounty: $505,000 in RAY tokens

Raydium is an AMM with an integrated central order book system. Users can provide liquidity, perform swaps on the exchange, and stake the RAY token for additional yield.
A fundamental aspect of Raydium is the Concentrated Liquidity Market Maker (CLMM).



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
