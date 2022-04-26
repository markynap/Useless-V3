//SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

import "./SafeMath.sol";
import "./Address.sol";

contract EclipseDataFetcher {

    using SafeMath for uint256;
    using Address for address;

    address public _furnace;
    address public _marketing;
    address public uselessRewardPot;
   
    uint256 public uselessRewardPotPercentage;
    uint256 private _decayPeriod;
    uint256 private _decayFee;
    uint256 private _uselessMinimumToDecayFullBalance;
    uint256 public creationCost;

    struct ListedToken {
        bool isListed;
        uint256 buyFee;
        uint256 sellFee;
        uint256 listedIndex;
    }

    mapping (address => ListedToken) public listedTokens;
    address[] public listed;

    mapping (address => bool) _isMaster;
    modifier onlyMaster(){require(_isMaster[msg.sender], 'Only Master'); _;}

    constructor() {
        _isMaster[msg.sender] = true;
        _decayPeriod = 201600; // one week
        _decayFee = 10;
        _uselessMinimumToDecayFullBalance = 100 * 10**18; // 100 useless
    }

    function setUselessMinimumToDecayFullBalance(uint minToDecay) external onlyMaster {
        _uselessMinimumToDecayFullBalance = minToDecay;
    }

    function setMasterPriviledge(address user, bool userIsMaster) external onlyMaster {
        _isMaster[user] = userIsMaster;
    }
    
    function setUselessRewardPot(address newPot) external onlyMaster {
        uselessRewardPot = newPot;
    }
    
    function setEclipseCreationCost(uint256 newCost) external onlyMaster {
        creationCost = newCost;
    }
    
    function setUselessRewardPotPercentage(uint256 newPercentage) external onlyMaster {
        uselessRewardPotPercentage = newPercentage;
    }

    function setFeesForToken(address token, uint256 buyFee, uint256 sellFee) external onlyMaster {
        listedTokens[token].buyFee = buyFee;
        listedTokens[token].sellFee = sellFee;
    }

    function listToken(address token) external onlyMaster {
        _listToken(token, 0, 0);
    }

    function listTokenWithFees(address token, uint256 buyFee, uint256 sellFee) external onlyMaster {
        _listToken(token, buyFee, sellFee);
    }
    
    function delistToken(address token) external onlyMaster {
        listed[listedTokens[token].listedIndex] = listed[listed.length-1];
        listedTokens[listed[listed.length-1]].listedIndex = listedTokens[token].listedIndex;
        listed.pop();
        delete listedTokens[token];
    }

    function _listToken(address token, uint256 buyFee, uint256 sellFee) private {
        listedTokens[token].isListed = true;
        listedTokens[token].buyFee = buyFee;
        listedTokens[token].sellFee = sellFee;
        listedTokens[token].listedIndex = listed.length;
        listed.push(token);
    }

    function getFeesForToken(address token) external view returns (uint, uint) {
        return (listedTokens[token].buyFee, listedTokens[token].sellFee);
    }
    
    function isListed(address token) external view returns (bool) {
        return listedTokens[token].isListed;
    }

    function getFurnace() external view returns(address) {
        return _furnace;
    }

    function getMarketing() external view returns(address) {
        return _marketing;
    }

    function isMaster(address user) external view returns(bool) {
        return _isMaster[user];
    }
    
    function getDecayPeriod() public view returns (uint256) {
        return _decayPeriod;
    }
    
    function getDecayFee() public view returns (uint256) {
        return _decayFee;
    }
    
    function getUselessMinimumToDecayFullBalance() public view returns (uint256) {
        return _uselessMinimumToDecayFullBalance;
    }
    
    function getListedTokens() public view returns (address[] memory) {
        return listed;
    }
}