// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Test, console} from "forge-std/Test.sol";
import {DeployDSC} from "script/DeployDSC.s.sol";
import {DecentralizedStableCoin} from "src/DecentralizedStableCoin.sol";
import {DSCEngine} from "src/DSCEngine.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {HelperConfig} from "script/HelperConfig.s.sol";

contract DscEngineTest is Test {
    DeployDSC deployer;
    DecentralizedStableCoin dsc;
    DSCEngine dsce;
    HelperConfig config;
    address ethUsdPriceFeed;
    address btcUsdPriceFeed;
    address weth;
    address public USER = makeAddr("user");
    uint256 public constant AMOUNT_COLLATERAL = 10 ether;
    uint256 public constant STARTING_ERC20_BALANCE = 10 ether;
    uint256 public constant AMOUNT_DSC_MINTED = 5 ether;

    function setUp() external {
        deployer = new DeployDSC();
        (dsc, dsce, config) = deployer.run();
        (ethUsdPriceFeed,, weth,,) = config.activeNetworkConfig();
        ERC20Mock(weth).mint(USER, STARTING_ERC20_BALANCE);
    }

    //////Constructor Test ////////
    address[] public tokenAddress;
    address[] public priceFeedAddresses;

    function testRevertIfTokenLengthDoesntMatchPriceFeed() public {
        tokenAddress.push(weth);
        priceFeedAddresses.push(ethUsdPriceFeed);
        priceFeedAddresses.push(btcUsdPriceFeed);

        vm.expectRevert(DSCEngine.DSCEngine__TokenAddressesAndPriceFeedAddressMustBesamelength.selector);
        new DSCEngine(tokenAddress, priceFeedAddresses, address(dsc));
    }

    /////////
    //Price Feed Tests

    function testGetUsdValue() public view {
        uint256 ethAmount = 15e18;
        //15e18 * 2000 = 30000 e18;
        uint256 expectedUsd = 30_000e18;
        uint256 actualusd = dsce.getUsdValue(weth, ethAmount);
        assertEq(expectedUsd, actualusd);
    }

    function testGetTokenAmountFromUsd() public view {
        uint256 usdAmount = 100 ether;
        uint256 expectedWeth = 0.05 ether;
        uint256 actualWeth = dsce.getTokenAmountFromUsd(weth, usdAmount);
        assertEq(expectedWeth, actualWeth);
    }

    //Deposit collateral test///

    function testRevertsIfCollateralIsZero() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);
        vm.expectRevert(DSCEngine.DSCEngine__NeedsMOreThanZero.selector);
        dsce.depositCollateral(weth, 0);
        vm.stopPrank();
    }

    function testRevertsWithUnApprovedCollateral() public {
        ERC20Mock ranToken = new ERC20Mock("RAN", "Ran", USER, AMOUNT_COLLATERAL);
        vm.startPrank(USER);
        vm.expectRevert(DSCEngine.DSCEngine__TokenNotAllowed.selector);
        dsce.depositCollateral(address(ranToken), AMOUNT_COLLATERAL);
        vm.stopPrank();
    }

    modifier depositedCollateral() {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);
        dsce.depositCollateral(weth, AMOUNT_COLLATERAL);
        vm.stopPrank();
        _;
    }

    function testCanDepositCollateralANdGetAccountInfo() public depositedCollateral {
        (uint256 totalDscminted, uint256 collateralValueInUsd) = dsce.getAccountInformation(USER);

        uint256 expectedTotalDscMinted = 0;
        uint256 expectDepositAmount = dsce.getTokenAmountFromUsd(weth, collateralValueInUsd);
        assertEq(totalDscminted, expectedTotalDscMinted);
        assertEq(AMOUNT_COLLATERAL, expectDepositAmount);
    }

    ///// extra tests////
    function testGetAccountInformation() public depositedCollateral {
        (uint256 totalDscminted, uint256 collateralValueInUsd) = dsce.getAccountInformation(USER);

        console.log("Total DSC Minted: ", totalDscminted);
        console.log("Collateral Value in USD: ", collateralValueInUsd);

        assert(collateralValueInUsd > 0); // Should NOT be 0
    }

    function testTokenRegistered() public view {
        address priceFeed = dsce.getPriceFeed(weth);
        console.log("WETH Price Feed Address:", priceFeed);
        assert(priceFeed != address(0)); //  Should not be zero address
    }

    function testDepositCollateralStoresBalance() public depositedCollateral {
        uint256 storedCollateral = dsce.getCollateralBalance(USER, weth);
        console.log("Stored Collateral: ", storedCollateral);
        assertEq(storedCollateral, AMOUNT_COLLATERAL); //  Should match deposited amount
    }

    modifier depositedandMintedCollateral() {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);
        dsce.depositCollateralandMintDSC(weth, AMOUNT_COLLATERAL, AMOUNT_DSC_MINTED);
        vm.stopPrank();
        _;
    }

    ////redeem function test////
    /// @notice Test that redeeming a safe amount of collateral works as expected.
    function testCanRedeemCollateralSuccessfully() external depositedandMintedCollateral {
        uint256 redeemAmount = 1 ether; // amount to redeem

        // Check DSCEngine's balance after deposit
        uint256 engineBalanceBefore = ERC20Mock(weth).balanceOf(address(dsce));

        // USER redeems a safe amount of collateral (no DSC minted, so health factor is fine)
        vm.startPrank(USER);
        dsce.redeemCollateral(weth, redeemAmount);
        vm.stopPrank();

        // Verify DSCEngine's WETH balance decreased by redeemAmount.
        uint256 engineBalanceAfter = ERC20Mock(weth).balanceOf(address(dsce));
        assertEq(engineBalanceBefore - engineBalanceAfter, redeemAmount, "Engine balance did not decrease correctly");

        // Verify USER's WETH balance increases accordingly.
        // USER started with STARTING_ERC20_BALANCE, deposited AMOUNT_COLLATERAL (so USER's balance became STARTING_ERC20_BALANCE - AMOUNT_COLLATERAL),
        // and after redeeming, USER's balance should be (STARTING_ERC20_BALANCE - AMOUNT_COLLATERAL + redeemAmount).
        uint256 userBalanceAfter = ERC20Mock(weth).balanceOf(USER);
        uint256 expectedUserBalance = STARTING_ERC20_BALANCE - AMOUNT_COLLATERAL + redeemAmount;
        assertEq(userBalanceAfter, expectedUserBalance, "User balance not updated correctly after redemption");
    }

    //  function testRevertsIfTransferFails() external {
    //     address owner = msg.sender;
    //     vm.prank(owner);
    //     MockFailedTransfer mockDsc = new MockFailedTransfer();
    //     tokenAddress = [address(mockDSc)];

    // }

    // Burn DSC test

    function testDscCanBeBurned() public depositedandMintedCollateral {
        uint256 amountToBurn = 1 ether;
        // Assume minted DSC is 1 ether at this point.
        uint256 expectedDscMinted = 5 ether;
        uint256 actualDscMinted = dsce.getDscMinted(USER);
        assertEq(expectedDscMinted, actualDscMinted);

        vm.startPrank(USER);
        // Approve DSCEngine to spend DSC for burning.
        dsc.approve(address(dsce), amountToBurn);
        dsce.burnDsc(amountToBurn);
        vm.stopPrank();

        uint256 mintedAfter = dsce.getDscMinted(USER);
        assertEq(mintedAfter, expectedDscMinted - amountToBurn);
        uint256 userBalance = dsc.balanceOf(USER);
        assertEq(userBalance, expectedDscMinted - amountToBurn, "User's DSC balance not updated correctly after burn");
    }

    // function testRevertIfBurnAmountExceedsBalance() public {
    //     vm.startPrank(USER);
    //     dsc.approve(address(dsce), AMOUNT_DSC_MINTED);
    //     vm.expectRevert(DSCEngine.DSCEngine__BurnAmountExceedsBalance.selector);
    //     dsce.burnDsc(AMOUNT_DSC_MINTED + 1);
    //     vm.stopPrank();
    // }

    // function testRevertIfBurnAmountIsZero() public {
    //     vm.startPrank(USER);
    //     dsc.approve(address(dsce), AMOUNT_DSC_MINTED);
    //     vm.expectRevert(DSCEngine.DSCEngine__MustBeMoreThanZero.selector);
    //     dsce.burnDsc(0);
    //     vm.stopPrank();
    // }

    // function testSucceedsIfAmountIsMoreThanZero() public {
    // uint256 validAmount = 1 ether;

    // vm.startPrank(USER);
    // dsce.mintDsc(validAmount);
    // vm.stopPrank();

    // uint256 userDscMinted = dsce.getDscMinted(USER);
    // assertEq(userDscMinted, validAmount, "Minted DSC amount is incorrect");
    // }
}
