//SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

import "./IEclipse.sol";
import "./Proxyable.sol";
import "./SafeMath.sol";
import "./Address.sol";
import "./IERC20.sol";

/** 
 * 
 * Eclipse Contract Generator
 * Generates Proxy Eclipse Contracts For Specified Token Projects
 * Costs A Specified Amount To Have Eclipse Created and Swapper Unlocked
 * Developed by Markymark (DeFi Mark)
 * 
 */ 
contract EclipseGenerator {
    
    using Address for address;
    using SafeMath for uint256;

    // useless contract
    address public immutable useless;
    // parent contract
    address private _parentProxy;
    
    // eclipse data
    struct EclipseLib {
        bool isVerified;
        address tokenRepresentative;
    }
    
    // eclipse => isVerified, tokenRepresentative
    mapping ( address => EclipseLib ) public eclipseContracts;
    
    // Token => Eclipse
    mapping ( address => address ) public tokenToEclipse;
    
    // list of Eclipses
    address[] public eclipseContractList;
    
    // decay tracker
    uint256 public decayIndex;

    // Database Contracts
    address public feeCollector;
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
    
    // initialize
    constructor(address uselessToken, uint256 decayPeriod) {
        useless = uselessToken;
        _isMaster[msg.sender] = true;
        _decayPeriod = decayPeriod;
        _decayFee = 10;
        _uselessMinimumToDecayFullBalance = 1000 * 10**18; // 1000 useless
    }

    //////////////////////////////////////////
    ///////    MASTER FUNCTIONS    ///////////
    //////////////////////////////////////////
    
    
    function decayByToken(address _token) external onlyMaster {
        _decay(tokenToEclipse[_token]);
    }
    
    function decayByEclipse(address _Eclipse) external onlyMaster {
        _decay(_Eclipse);
    }
    
    function deleteEclipse(address eclipse) external onlyMaster {
        require(eclipseContracts[eclipse].isVerified, 'Not Eclipse Contract');
        _deleteEclipse(eclipseContracts[eclipse].tokenRepresentative);
    }
    
    function deleteEclipseByToken(address token) external onlyMaster {
        require(eclipseContracts[tokenToEclipse[token]].isVerified, 'Not Eclipse Contract');
        _deleteEclipse(token);
    }
    
    function pullRevenue() external onlyMaster {
        _withdraw();
    }
    
    function withdrawTokens(address token) external onlyMaster {
        uint256 bal = IERC20(token).balanceOf(address(this));
        require(bal > 0, 'Insufficient Balance');
        IERC20(token).transfer(msg.sender, bal);
    }

    function setDecayFee(uint256 newFee) external onlyMaster {
        require(
            newFee <= 30,
            'Fee Too High'
        );
        _decayFee = newFee;
    }
    
    function lockProxy(address proxy) external onlyMaster {
        _parentProxy = proxy;
    }

    function setUselessMinimumToDecayFullBalance(uint minToDecay) external onlyMaster {
        _uselessMinimumToDecayFullBalance = minToDecay;
    }

    function setMasterPriviledge(address user, bool userIsMaster) external onlyMaster {
        _isMaster[user] = userIsMaster;
    }

    function setEclipseCreationCost(uint256 newCost) external onlyMaster {
        creationCost = newCost;
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
        require(
            listedTokens[token].isListed,
            'Not Listed'
        );
        listed[listedTokens[token].listedIndex] = listed[listed.length-1];
        listedTokens[listed[listed.length-1]].listedIndex = listedTokens[token].listedIndex;
        listed.pop();
        delete listedTokens[token];
    }

    function _listToken(address token, uint256 buyFee, uint256 sellFee) private {
        require(
            !listedTokens[token].isListed,
            'Already Listed'
        );
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

    function getFeeCollector() external view returns(address) {
        return feeCollector;
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
    
    
    //////////////////////////////////////////
    ///////    PUBLIC FUNCTIONS    ///////////
    //////////////////////////////////////////
    
    
    function createEclipse(address _tokenToList) external payable {
        require(tx.origin == msg.sender, 'No Proxies Allowed');
        require(msg.value >= creationCost || _isMaster[msg.sender], 'Cost Not Met');
        // create proxy
        address hill = Proxyable(payable(_parentProxy)).createProxy();
        // initialize proxy
        IEclipse(payable(hill)).bind(_tokenToList);
        // add to database
        eclipseContracts[address(hill)].isVerified = true;
        eclipseContracts[address(hill)].tokenRepresentative = _tokenToList;
        tokenToEclipse[_tokenToList] = address(hill);
        eclipseContractList.push(address(hill));
        _withdraw();
        emit EclipseCreated(address(hill), _tokenToList);
    }
    
    function iterateDecay(uint256 iterations) external {
        require(iterations <= eclipseContractList.length, 'Too Many Iterations');
        for (uint i = 0; i < iterations; i++) {
            if (decayIndex >= eclipseContractList.length) {
                decayIndex = 0;
            }
            _decay(eclipseContractList[decayIndex]);
            decayIndex++;
        }
    }
    
    function decayAll() external {
        for (uint i = 0; i < eclipseContractList.length; i++) {      
            _decay(eclipseContractList[i]);
        }
    }
    
    //////////////////////////////////////////
    ///////   INTERNAL FUNCTIONS   ///////////
    //////////////////////////////////////////
    
    
    function _decay(address eclipse) internal {
        IEclipse(payable(eclipse)).decay();
    }
    
    function _deleteEclipse(address token) internal {
        uint index = eclipseContractList.length;
        for (uint i = 0; i < eclipseContractList.length; i++) {
            if (tokenToEclipse[token] == eclipseContractList[i]) {
                index = i;
                break;
            }
        }
        require(index < eclipseContractList.length, 'Eclipse Not Found');
        eclipseContractList[index] = eclipseContractList[eclipseContractList.length - 1];
        eclipseContractList.pop();
        delete eclipseContracts[tokenToEclipse[token]];
        delete tokenToEclipse[token];
    }
    
    function _withdraw() internal {
        if (address(this).balance > 0) {
            (bool successful,) = payable(feeCollector).call{value: address(this).balance}("");
            require(successful, 'BNB Transfer Failed');
        }
    }
    
    //////////////////////////////////////////
    ///////     READ FUNCTIONS     ///////////
    //////////////////////////////////////////
    
    function kingOfTheHill() external view returns (address) {
        uint256 max = 0;
        address king;
        for (uint i = 0; i < eclipseContractList.length; i++) {
            uint256 amount = IERC20(useless).balanceOf(eclipseContractList[i]);
            if (amount > max) {
                max = amount;
                king = eclipseContractList[i];
            }
        }
        return king == address(0) ? king : eclipseContracts[king].tokenRepresentative;
    }
    
    function getUselessInEclipse(address _token) external view returns(uint256) {
        if (tokenToEclipse[_token] == address(0)) return 0;
        return IERC20(useless).balanceOf(tokenToEclipse[_token]);
    }
    
    function getEclipseForToken(address _token) external view returns(address) {
        return tokenToEclipse[_token];
    }
    
    function getTokenForEclipse(address _eclipse) external view returns(address) {
        return eclipseContracts[_eclipse].tokenRepresentative;
    }
    
    function isEclipseContractVerified(address _contract) external view returns(bool) {
        return eclipseContracts[_contract].isVerified;
    }
    
    function isTokenListed(address token) external view returns(bool) {
        return tokenToEclipse[token] != address(0);
    }
    
    function getEclipseContractList() external view returns (address[] memory) {
        return eclipseContractList;
    }
    
    function getEclipseContractListLength() external view returns (uint256) {
        return eclipseContractList.length;
    }
    
    receive() external payable {}
    
    //////////////////////////////////////////
    ///////         EVENTS         ///////////
    //////////////////////////////////////////
    
    
    event EclipseCreated(address Eclipse, address tokenListed);
    event TransferOwnership(address newOwner);

}