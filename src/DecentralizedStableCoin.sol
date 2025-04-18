// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {ERC20Burnable, ERC20} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
/**
 * @title DecentralizedStableCoin 
 * @author Alman
 * Collateral: Exogenous
 * Minting: Algorothmic
 * Relative Stabiolity: Pegged to usd
 * 
 * This the contract is meant to be goverened by DScEngine.This contract is just the ERC20 implementation of our stablecoin system
 */

contract DecentralizedStableCoin is ERC20Burnable,Ownable{
    error DecentralizedStableCoin__MustBeMoreThanZero();
    error DecentralizedStableCoin__BurnAmountExceedsBalance();
    error DecentralizedStableCoin__NotZeroAddress();
    
    constructor() ERC20("DecentralizedStableCoin","DSC")Ownable(msg.sender){

    }

    function burn(uint256 _amount) public override onlyOwner{
        uint256 balance = balanceOf(msg.sender);
        if (_amount <=0){
            revert DecentralizedStableCoin__MustBeMoreThanZero();
        }
        if (balance < _amount){
            revert DecentralizedStableCoin__BurnAmountExceedsBalance();
        }
        //means use the burn function in the inheratince super class. it overrides our burn function by making the checks
        super.burn(_amount);
    }

    function mint(address _to,uint256 _amount) external onlyOwner returns(bool){
        if (_to == address(0)){
            revert DecentralizedStableCoin__NotZeroAddress();

        }
        if(_amount <=0){
            revert DecentralizedStableCoin__MustBeMoreThanZero();
        }
        //does not overide our mint function
        _mint(_to,_amount);
        return true;

    }

    
        
    
}