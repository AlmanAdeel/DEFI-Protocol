// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Script} from 'forge-std/Script.sol';
import {DecentralizedStableCoin} from "src/DecentralizedStableCoin.sol";
import {DSCEngine} from "src/DSCEngine.sol";
import {HelperConfig} from "script/HelperConfig.s.sol";
contract DeployDSC is Script {
    address[] public tokenAddress;
    address[] public priceFeedAddress;
    function run() external returns(DecentralizedStableCoin,DSCEngine,HelperConfig){
        HelperConfig config = new HelperConfig();
        (address wethPriceFeed,address wbtcPriceFeed,address weth,address wbtc,uint256 deployerKey) = config.activeNetworkConfig();
        tokenAddress = [weth,wbtc];
        priceFeedAddress = [wethPriceFeed,wbtcPriceFeed];

        vm.startBroadcast(deployerKey);
        DecentralizedStableCoin dsc = new DecentralizedStableCoin();
        DSCEngine Dscengine = new DSCEngine(tokenAddress,priceFeedAddress,address(dsc));
        dsc.transferOwnership(address(Dscengine));
        vm.stopBroadcast();
        return(dsc,Dscengine,config);

    } 
}