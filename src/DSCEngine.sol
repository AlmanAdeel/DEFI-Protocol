// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {DecentralizedStableCoin} from "src/DecentralizedStableCoin.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import {OrcaleLib} from "./libraries/OrcaleLib.sol";
/**
 * @title DSCEngine
 * @author Alman
 * The system is designed to be as minimal as possible and have the token minimum a
 * 1 token = $1 peg
 * This stablecoin has the properties:
 * Exogenous Collateral
 * Dollar Pegged
 * Algorthmically Stable
 *
 * it is similar to DAI if DAI had no goverance, no fee and was only backed by WETH and WBTc
 *
 * Our DSC system should over collateralize. At no point should the value of all collateral <=
 *    the $ backed value of DSC.
 *
 * @notice This contract is the core of DSC system. It handles all the logic for minting
 * and redeeming DSC as well ass depostiing & withdrawing collateral.
 * @notice This contract is VERY lossely based on the MakerDAO DSS (DAI) system
 *
 */

contract DSCEngine is ReentrancyGuard {
    //Errors
    error DSCEngine__NeedsMOreThanZero();
    error DSCEngine__TokenAddressesAndPriceFeedAddressMustBesamelength();
    error DSCEngine__TokenNotAllowed();
    error DSCEngine__BreaksHealthFactor(uint256 healthFActor);
    error DSCEngine__mintfailed();
    error DSCEngine__TransactionFailed();
    error DSCEngine__HealthFactorOk();
    error DSCEngine_HealthFactorNotImproved();
    error DSCEngine__DSCEngine__MustBeMoreThanZero();

    ///Types
    using OrcaleLib for AggregatorV3Interface;

    //State Variables
    uint256 private constant ADDITIONAL_FEE_PRECISION = 1e10;
    uint256 private constant LIQUIDATION_PRECSION = 100;
    uint256 private constant LIQUADIATION_THRESHOLD = 50; // between 200% and 110% its safe
    uint256 private constant MIN_HEALTH_FACTOR = 1e18;
    uint256 private constant LIQUADIATION_BONUS = 10; // this means 10 percent bonus
    mapping(address token => address pricefeeds) private s_pricefeeds;
    mapping(address user => mapping(address token => uint256 amount)) private s_collateralDeposited;
    mapping(address user => uint256 amountDscMinted) private s_DscMinted;
    address[] private s_collateraltokens;

    DecentralizedStableCoin private immutable i_dsc;
    /// Modifers

    modifier moreThanZero(uint256 amount) {
        if (amount == 0) {
            revert DSCEngine__NeedsMOreThanZero();
        }
        _;
    }

    modifier isAllowedToken(address token) {
        if (s_pricefeeds[token] == address(0)) {
            revert DSCEngine__TokenNotAllowed();
        }
        _;
    }

    //Events
    event CollateralDeposited(address indexed user, address indexed token, uint256 indexed amount);
    event CollateralRedeemed(
        address indexed RedeemedFrom, address indexed RedeemedTo, address indexed token, uint256 amount
    );

    constructor(address[] memory tokenAddress, address[] memory priceFeedAddress, address dscAddress) {
        //USD price feeds will be used
        if (tokenAddress.length != priceFeedAddress.length) {
            revert DSCEngine__TokenAddressesAndPriceFeedAddressMustBesamelength();
        }
        for (uint256 i = 0; i < tokenAddress.length; i++) {
            s_pricefeeds[tokenAddress[i]] = priceFeedAddress[i]; //weth = wethPriceFeed
            s_collateraltokens.push(tokenAddress[i]); // stored in token array
        }
        i_dsc = DecentralizedStableCoin(dscAddress); // DecentralizedStableCoin contract
    }

    /// exterrnal and public functions

    /*
    * 
    * @param tokenCollateralAddress The address of token to deposit as collateral
    * @param amountCollateral the maount of collateral to deposit
    * @param amountDSCToMint the amount of decentralized stablecoin to mint
    * @notice this function will deposit collateral and mint dsc in one transaction
    */
    function depositCollateralandMintDSC(
        address tokenCollateralAddress,
        uint256 amountCollateral,
        uint256 amountDSCToMint
    ) external {
        depositCollateral(tokenCollateralAddress, amountCollateral);
        mintDsc(amountDSCToMint);
    }

    function depositCollateral(address tokenCollateralAddress, uint256 amountCollateral)
        public
        moreThanZero(amountCollateral)
        isAllowedToken(tokenCollateralAddress)
        nonReentrant
    {
        s_collateralDeposited[msg.sender][tokenCollateralAddress] += amountCollateral; // here we are just storing it into the mapping
        emit CollateralDeposited(msg.sender, tokenCollateralAddress, amountCollateral);
        bool success = IERC20(tokenCollateralAddress).transferFrom(msg.sender, address(this), amountCollateral); // the place where real transfer is happening
        if (!success) {
            revert();
        }
    }

    // in order to redeem collateral:
    //1. health factor must be over 1 After collareral pulled

    function redeemCollateral(address tokenCollateralAddress, uint256 amountCollateral)
        public
        moreThanZero(amountCollateral)
    {
        _redeemCollateral(tokenCollateralAddress, amountCollateral, msg.sender, msg.sender);
        _revertHealthFactorIsBroken(msg.sender);
    }

    // This function burns DSC and redeems underlying collateral in one transaction
    function redeemCollateralForDSC(address tokenCollateralAddress, uint256 amountCollateral, uint256 amountDSCToburn)
        external
    {
        burnDsc(amountDSCToburn);
        redeemCollateral(tokenCollateralAddress, amountCollateral);
    }
    //Check if collateral Value > DSC amount
    /*
     * 
     * @param amountDSCToMint : amount of stable coin to mint
     * @notice They must have more collateral value than minimum thershold
     */

    function mintDsc(uint256 amountDscToMint) public moreThanZero(amountDscToMint) nonReentrant {
        s_DscMinted[msg.sender] += amountDscToMint;
        _revertHealthFactorIsBroken(msg.sender);
        bool minted = i_dsc.mint(msg.sender, amountDscToMint);
        if (!minted) {
            revert DSCEngine__mintfailed();
        }
    }

    function burnDsc(uint256 amount) public moreThanZero(amount) {
        _burnDsc(amount, msg.sender, msg.sender);
        _revertHealthFactorIsBroken(msg.sender); // might be no need for this as it wont be hit
    }

    // if we start nearing undercollaterlization we need someone to start liquidating postions
    // if someone is almost undercollaterlized we will pay to liquidate them
    // e.g $75 backing 50 DSc thershold is less than 50 percent
    // so we allow a liquidator to take 75 dollar backing and pay off 50 dollar DSC
    //@notice you can partially liquidate a user
    //@notice this function working assumes the protocol will be roughly 200% overcollateralized for this to work
    //@notice A knwon bug would if the protocol were 100% or less collaterlized tgebn  we wouldnt be able to incentive the liquidator

    function liquidate(address collateral, address user, uint256 debtToCover)
        external
        moreThanZero(debtToCover)
        nonReentrant
    {
        uint256 startingHealthFactor = _healthFactor(user);
        if (startingHealthFactor >= MIN_HEALTH_FACTOR) {
            revert DSCEngine__HealthFactorOk();
        }
        //we want to burn their DSC debt
        //And take their collateral
        //$140 ETH,$100 DSc
        //debt to cover = 100
        //100 of DSC = 0.05 ETh supposdely it might vary since price is changing
        uint256 tokenAmountFromDebtCovered = getTokenAmountFromUsd(collateral, debtToCover);
        // give them a 10 percent bonus
        //0.05 eth * 0.1 = 0.005 eth
        uint256 bonusCollateral = (tokenAmountFromDebtCovered * LIQUADIATION_BONUS) / LIQUIDATION_PRECSION; // doing this so we get a clear number like 10 or 5
        uint256 totalCollateralToRedeem = tokenAmountFromDebtCovered * bonusCollateral;
        _redeemCollateral(collateral, totalCollateralToRedeem, user, msg.sender);
        _burnDsc(debtToCover, user, msg.sender);
        uint256 endingUserHealthFactor = _healthFactor(user);
        if (endingUserHealthFactor <= startingHealthFactor) {
            revert DSCEngine_HealthFactorNotImproved();
        }
        _revertHealthFactorIsBroken(msg.sender);
    }

    function getHealthFactor() external view {}

    //internal funactions and view functions
    function _redeemCollateral(address tokenCollateralAddress, uint256 amountCollateral, address from, address to)
        private
    {
        s_collateralDeposited[from][tokenCollateralAddress] -= amountCollateral;
        emit CollateralRedeemed(from, to, tokenCollateralAddress, amountCollateral);
        bool success = IERC20(tokenCollateralAddress).transfer(to, amountCollateral); //  again where the real transfer is happening
        if (!success) {
            revert DSCEngine__TransactionFailed();
        }
    }
    // low level internal function do not call unless the function calling is checking for health factor to be broken

    function _burnDsc(uint256 amountDscToBurn, address onBehalfOf, address dscFrom) private {
        s_DscMinted[onBehalfOf] -= amountDscToBurn;
        bool success = i_dsc.transferFrom(dscFrom, address(this), amountDscToBurn);
        if (!success) {
            revert DSCEngine__TransactionFailed();
        }
        i_dsc.burn(amountDscToBurn);
    }

    function _getAccountInformation(address user) private view returns (uint256 total, uint256 collateralvalue) {
        total = s_DscMinted[user];
        collateralvalue = getAccountCollateralValueInUsd(user);
        return (total, collateralvalue);
    }

    function _healthFactor(address user) private view returns (uint256) {
        //returns how close to liquaidation a user is
        //if a user goes below 1 then they can get liquaidate
        //total Dsc minted
        //total collateral value needed

        (uint256 totalDscminted, uint256 collateralValueInUsd) = _getAccountInformation(user);
        if (totalDscminted == 0) return type(uint256).max;
        uint256 collateralAdjustedForThreshold = (collateralValueInUsd * LIQUADIATION_THRESHOLD) / LIQUIDATION_PRECSION;

        return (collateralAdjustedForThreshold * 1e18) / totalDscminted;
    }

    function _revertHealthFactorIsBroken(address user) internal view {
        // check if they have enough collateral
        // revert if they dont
        uint256 userHealthfactor = _healthFactor(user);
        if (userHealthfactor < MIN_HEALTH_FACTOR) {
            revert DSCEngine__BreaksHealthFactor(userHealthfactor);
        }
    }

    function getAccountCollateralValueInUsd(address user) public view returns (uint256 totalCollateralValueInUsd) {
        //loop through each collateral token,get the amount they depoisted and map it to the price to get the usd value
        for (uint256 i = 0; i < s_collateraltokens.length; i++) {
            address token = s_collateraltokens[i];
            uint256 amount = s_collateralDeposited[user][token]; // get the amount of collateral deposited from different coins
            totalCollateralValueInUsd += getUsdValue(token, amount);
        }
        return totalCollateralValueInUsd;
    }

    function getUsdValue(address token, uint256 amount) public view returns (uint256) {
        AggregatorV3Interface pricefeed = AggregatorV3Interface(s_pricefeeds[token]);
        (, int256 price,,,) = pricefeed.latestRoundData();
        return ((uint256(price) * ADDITIONAL_FEE_PRECISION) * amount) / 1e18; //1000 * 1e18 // reason we are multipying by 1e10 and dividing by 1e18 is bec chainlink vrf gives price in 1e8 format so we have to adjust it accordingly
    }

    function getTokenAmountFromUsd(address token, uint256 usdAmountInWei) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_pricefeeds[token]);
        (, int256 price,,,) = priceFeed.stalePriceCheckLatestRoundData();
        //10e18 * 1e18 / 2000e8 * 1e10
        return (usdAmountInWei * 1e18) / (uint256(price) * ADDITIONAL_FEE_PRECISION);
    }

    function getAccountInformation(address user)
        external
        view
        returns (uint256 totalDScminted, uint256 collaateralValueInUsd)
    {
        (totalDScminted, collaateralValueInUsd) = _getAccountInformation(user);
    }

    function getPriceFeed(address token) external view returns (address priceFeed) {
        return s_pricefeeds[token];
    }

    function getCollateralBalance(address user, address tokenCollateralAddress) external view returns (uint256) {
        return s_collateralDeposited[user][tokenCollateralAddress];
    }

    function getDscMinted(address user) external view returns (uint256) {
        return s_DscMinted[user];
    }

    function getCollateralTokens() external view returns (address[] memory) {
        return s_collateraltokens;
    }

    function getCollateralBalanceOfUser(address user, address token) external view returns (uint256) {
        return s_collateralDeposited[user][token];
    }
}
