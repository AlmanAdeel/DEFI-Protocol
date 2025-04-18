//handdler is going to narrow down the way we call function//SPDX-License-Identifier: MIT
//Have properties that should always hold

//What are our invariants ?

//1.  The total supply of DSC should be less than the total value of collateral
//2. Getter view functions should never revert <- evergreen invariant
pragma solidity ^0.8.25;

import {Test, console} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {DeployDSC} from "script/DeployDSC.s.sol";
import {DSCEngine} from "src/DSCEngine.sol";
import {DecentralizedStableCoin} from "src/DecentralizedStableCoin.sol";
import {HelperConfig} from "script/HelperConfig.s.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Handler} from "test/fuzz/Handler.t.sol";

contract InterivantsTest is StdInvariant, Test {
    DSCEngine dsce;
    DeployDSC deployer;
    DecentralizedStableCoin dsc;
    HelperConfig config;
    address weth;
    address wbtc;
    Handler handler;

    function setUp() external {
        deployer = new DeployDSC();
        (dsc, dsce, config) = deployer.run();
        (,, weth, wbtc,) = config.activeNetworkConfig();
        //targetContract(address(dsce));
        handler = new Handler(dsce, dsc);
        targetContract(address(handler));
        //what handler would do is it wont let you call specific functions is a specific function hasnt been executed
        //for e.g redeemCollateral wont be called unless DepositCollateral is called
    }
    // a little documenatation for my ownself
    // basicllay we write the stuff written below to do the task we want it to do rather than performing usual depoist and other stuff like we do in unit test
    // and the handler will make sure that the function is called in the right order
    // it is called in a way that i should be called

    function invariant_protocolMustHaveMoreValueThanTotalSupply() public view {
        //get the value of all the collateral in the protocol
        //compare it to all the debt (dsc)
        uint256 totalSupply = dsc.totalSupply();
        uint256 totalWethDeposited = IERC20(weth).balanceOf(address(dsce)); // total amount of weth sent to that contract
        uint256 totalWBtcDeposited = IERC20(wbtc).balanceOf(address(dsce)); // total amount of wbtc sent to that contract
        uint256 wethValue = dsce.getUsdValue(weth, totalWethDeposited);
        uint256 wbtcValue = dsce.getUsdValue(wbtc, totalWBtcDeposited);
        console.log("Total Supply of DSC: ", totalSupply);
        console.log("Total Value of Weth: ", wethValue);
        console.log("Total Value of WBTC: ", wbtcValue);
        console.log("Times mint called", handler.timesMintIsCalled());

        assert(wethValue + wbtcValue >= totalSupply);
    }

    function invairants_gettersShouldNotRevert() public view {
        dsce.getAccountInformation(msg.sender);
        dsce.getCollateralTokens();
    }
}
