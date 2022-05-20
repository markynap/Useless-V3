//SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

import "./IERC20.sol";
import "./EclipseGenerator.sol";

/** 
 *
 * Useless King Of The Hill Contract
 * Tracks Useless In Contract To Determine Listing on the Useless App
 * Developed by Markymark (DeFi Mark)
 * 
 */

contract EclipseData {    
    address _eclipseToken;
    EclipseGenerator _fetcher;
    uint256 lastDecay;
}


contract Eclipse is EclipseData, Proxyable {
    
    using SafeMath for uint256; 
        
    function bind(address eclipseToken) external {
        require(_eclipseToken == address(0), 'Proxy Already Bound');
        _eclipseToken = eclipseToken;
        _fetcher = EclipseGenerator(payable(msg.sender));
        lastDecay = block.number;
    }
    
    //////////////////////////////////////////
    ///////    MASTER FUNCTIONS    ///////////
    //////////////////////////////////////////
    
    function decay() external {
        address useless = _fetcher.useless();
        uint256 bal = IERC20(useless).balanceOf(address(this));
        if (bal == 0) { return; }

        if (lastDecay + _fetcher.getDecayPeriod() > block.number) { return; }
        lastDecay = block.number;

        uint256 minimum = _fetcher.getUselessMinimumToDecayFullBalance();
        uint256 takeBal = bal <= minimum ? bal : bal * _fetcher.getDecayFee() / 100;
        if (takeBal > 0) {
            bool success = IERC20(useless).transfer(_fetcher.feeCollector(), takeBal);
            require(success, 'Failure on Useless Transfer To Furnace');
        }
        emit Decay(takeBal);
    }
    
    //////////////////////////////////////////
    ///////     READ FUNCTIONS     ///////////
    //////////////////////////////////////////
    
    function getUselessInContract() external view returns (uint256) {
        return IERC20(_fetcher.useless()).balanceOf(address(this));
    }
    
    function getTokenRepresentative() external view returns (address) {
        return _eclipseToken;
    }
    
    // EVENTS
    event Decay(uint256 numUseless);
    
}