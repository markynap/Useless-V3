//SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

import "./IERC20.sol";
import "./IUniswapV2Router02.sol";
import "./EclipseDataFetcher.sol";
import "./SafeMath.sol";
import "./IEclipse.sol";
import "./Proxyable.sol";

/** 
 *
 * Useless King Of The Hill Contract
 * Tracks Useless In Contract To Determine Listing on the Useless App
 * Developed by Markymark (DeFi Mark)
 * 
 */

contract EclipseData {    
    address _useless;
    address _tokenRep;
    bool receiveDisabled;
    EclipseDataFetcher _fetcher;
    uint256 lastDecay;
}


contract Eclipse is EclipseData, IEclipse, Proxyable {
    
    using SafeMath for uint256; 
        
    constructor(address _token) {
        require(msg.sender == 0xf5f91867eBA4F7439997C6D90377557aA612fCF5); // change this to parentProxy deployer
        _bind(_token);
    }
    
    function bind(address _token) external override {
        _bind(_token);
    }
    
    function _bind(address _token) private {
        require(_useless == address(0), 'Proxy Already Bound');
        _tokenRep = _token;
        _useless = 0x60d66a5152612F7D550796910d022Cb2c77B09de;
        _fetcher = EclipseDataFetcher(0x10ED43C718714eb63d5aA57B78B54704E256024E); // enter in data fetcher
        lastDecay = block.number;
    }

    //////////////////////////////////////////
    ///////    MASTER FUNCTIONS    ///////////
    //////////////////////////////////////////
    
    function decay() external override {
        if (lastDecay + _fetcher.getDecayPeriod() > block.number) return;
        uint256 bal = IERC20(_useless).balanceOf(address(this));
        if (bal == 0) { return; }
        lastDecay = block.number;
        uint256 decayFee = _fetcher.getDecayFee();
        uint256 minimum = _fetcher.getUselessMinimumToDecayFullBalance();
        uint256 takeBal = bal <= minimum ? bal : bal.div(decayFee);
        address furnace = _fetcher.getFurnace();
        address rewardPot = _fetcher.uselessRewardPot();
        uint256 rewardAmount = takeBal.mul(_fetcher.uselessRewardPotPercentage()).div(10**2);
        takeBal = takeBal.sub(rewardAmount);
        if (takeBal > 0) {
            bool success = IERC20(_useless).transfer(furnace, takeBal);
            require(success, 'Failure on Useless Transfer To Furnace');
        }
        if (rewardAmount > 0) {
            success = IERC20(_useless).transfer(rewardPot, rewardAmount);
            require(success, 'Failure on Useless Transfer To Furnace');
        }
        emit Decay(takeBal+rewardAmount);
    }
    
    
    //////////////////////////////////////////
    ///////   MODERATOR FUNCTIONS  ///////////
    //////////////////////////////////////////
    
    function liquidateToken(address token, address router) external {
        require(token != _useless, 'Cannot Sell USELESS Tokens');
        liquidate(token, router);
    }
    
    function swapTokenForUseless(address token, address router) external {
        require(token != _useless, 'Cannot Sell USELESS Tokens');
        _swapTokenForUseless(token, router);
    }
    
    
    //////////////////////////////////////////
    ///////    PRIVATE FUNCTIONS   ///////////
    //////////////////////////////////////////
    
    
    function liquidate(address token, address router) internal {
        require(token != _useless, 'Cannot Liquidate Useless Token');
        uint256 bal = IERC20(token).balanceOf(address(this));
        require(bal > 0, 'Insufficient Balance');
        
        IUniswapV2Router02 customRouter = IUniswapV2Router02(router);
        IERC20(token).approve(router, bal);
        
        address[] memory path = new address[](2);
        path[0] = token;
        path[1] = customRouter.WETH();
        
        receiveDisabled = true;
        customRouter.swapExactTokensForETHSupportingFeeOnTransferTokens(
            bal,
            0,
            path,
            address(this),
            block.timestamp.add(30)
        );
        receiveDisabled = false;
        
        buyUseless(address(this).balance);
    }
    
    function _swapTokenForUseless(address token, address router) private {
        require(token != _useless, 'Cannot Liquidate Useless Token');
        uint256 bal = IERC20(token).balanceOf(address(this));
        require(bal > 0, 'Insufficient Balance');
        
        IUniswapV2Router02 customRouter = IUniswapV2Router02(router);
        IERC20(token).approve(router, bal);
        
        address[] memory path = new address[](3);
        path[0] = token;
        path[1] = customRouter.WETH();
        path[2] = _useless;
        
        customRouter.swapExactTokensForTokensSupportingFeeOnTransferTokens(
            bal,
            0,
            path,
            address(this),
            block.timestamp.add(30)
        );
        
    }
    
    function buyUseless(uint256 amount) private {
        if (amount == 0) return;
        address swapper = _fetcher.getSwapper();
        (bool success, ) = address(swapper).call{value: amount}("");
        require(success, 'Failed Useless Purchase');
    }
    
    //////////////////////////////////////////
    ///////     READ FUNCTIONS     ///////////
    //////////////////////////////////////////
    
    function getUselessInContract() external view returns (uint256) {
        return IERC20(_useless).balanceOf(address(this));
    }
    
    function getTokenRepresentative() external override view returns (address) {
        return _tokenRep;
    }
    
    receive() external payable {
        if (!receiveDisabled) {
            buyUseless(msg.value);
        }
    }
    
    // EVENTS
    event Decay(uint256 numUseless);
    
}