//SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

import "./IEclipse.sol";
import "./Proxyable.sol";
import "./EclipseDataFetcher.sol";
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
    address private immutable _useless;
    // owner 
    address private _master;
    // parent contract
    address private _parentProxy;
    // data fetcher
    EclipseDataFetcher private immutable _fetcher;

    // master only functions
    modifier onlyMaster() {require(msg.sender == _master, 'Master Function'); _;}
    
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
    
    // percentage for furnace
    uint256 public furnacePercent;
    
    // initialize
    constructor(address initialOwner, address dataFetcher, address uselessToken) {
        _master = initialOwner;
        _fetcher = EclipseDataFetcher(dataFetcher);
        _useless = uselessToken;
        furnacePercent = 50;
    }
    
    function lockProxy(address proxy) external onlyMaster {
        require(_parentProxy == address(0), 'Proxy Locked');
        _parentProxy = proxy;
    }
    
    
    //////////////////////////////////////////
    ///////    PUBLIC FUNCTIONS    ///////////
    //////////////////////////////////////////
    
    
    function createEclipse(address _tokenToList) external payable {
        require(tx.origin == msg.sender, 'No Proxies Allowed');
        uint256 cost = _fetcher.creationCost();
        require(msg.value >= cost, 'Cost Not Met');
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
    ///////    MASTER FUNCTIONS    ///////////
    //////////////////////////////////////////
    
    
    function transferOwnership(address newOwner) external onlyMaster {
        require(_master != newOwner, 'Owners Match');
        _master = newOwner;
        emit TransferOwnership(newOwner);
    }
    
    function decayByToken(address _token) external onlyMaster {
        _decay(tokenToEclipse[_token]);
    }
    
    function decayByEclipse(address _Eclipse) external onlyMaster {
        _decay(_Eclipse);
    }
    
    function setFurnacePercent(uint256 newPercent) external onlyMaster {
        furnacePercent = newPercent;
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
        IERC20(token).transfer(_master, bal);
    }
    
    
    //////////////////////////////////////////
    ///////   INTERNAL FUNCTIONS   ///////////
    //////////////////////////////////////////
    
    
    function _decay(address eclipse) internal {
        IEclipse(payable(eclipse)).decay();
    }
    
    function _deleteEclipse(address token) internal {
        for (uint i = 0; i < eclipseContractList.length; i++) {
            if (tokenToEclipse[token] == eclipseContractList[i]) {
                eclipseContractList[i] = eclipseContractList[eclipseContractList.length - 1];
                break;
            }
        }
        eclipseContractList.pop();
        delete eclipseContracts[tokenToEclipse[token]];
        delete tokenToEclipse[token];
    }
    
    function _withdraw() internal {
        address receiver = _fetcher.getMarketing();
        address furnace = _fetcher.getFurnace();
        
        uint256 amountFurnace = address(this).balance.mul(furnacePercent).div(10**2);
        uint256 receiverAmount = address(this).balance.sub(amountFurnace); 
        
        if (address(this).balance > 100) {
            (bool success,) = payable(receiver).call{value: receiverAmount}("");
            require(success, 'BNB Transfer Failed');
        
            (bool successful,) = payable(furnace).call{value: amountFurnace}("");
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
            uint256 amount = IERC20(_useless).balanceOf(eclipseContractList[i]);
            if (amount > max) {
                max = amount;
                king = eclipseContractList[i];
            }
        }
        return king == address(0) ? king : eclipseContracts[king].tokenRepresentative;
    }
    
    function getUselessInEclipse(address _token) external view returns(uint256) {
        if (tokenToEclipse[_token] == address(0)) return 0;
        return IERC20(_useless).balanceOf(tokenToEclipse[_token]);
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