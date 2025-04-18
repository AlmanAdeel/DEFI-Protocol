//SPDX-License-Identifier: MIT

pragma solidity ^0.8.25;
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
/*
 * @title OrcaleLib 
 * @author Alman Adeel
 * @notice This library is used to check the Chainlink Oracle for stale data.
 * if a price is stable the function will revert, and render the DSCEngine unusable
 * We want DSCEngine to freeze if prices become stable.
 * 
 * So if chainlink network explodes and you have a alot of money locked
 */


library  OrcaleLib {
    uint256 private constant TIMEOUT = 3 hours; // 3 * 60 * 60
    error OrcaleLib__StalePrice();
    function stalePriceCheckLatestRoundData(AggregatorV3Interface priceFeed) public view returns(uint88,int256,uint256,uint256,uint88){
        (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound) =priceFeed.latestRoundData();
        uint256 secondsSince = block.timestamp - updatedAt;
        if (secondsSince > TIMEOUT){
            revert OrcaleLib__StalePrice();
        }
    return (roundId,answer,startedAt,updatedAt,answeredInRound);
    
    }
}