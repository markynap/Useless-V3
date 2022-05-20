//SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

import "./IERC20.sol";
import "./SafeMath.sol";
import "./IUniswapV2Router02.sol";

interface IUseless {
    function burn(uint amount) external;
}

interface IFurnaceDB {
    function pullLiquidityRange() external view returns (uint256);
    function buyAndBurnRange() external view returns (uint256);
    function reverseSALRange() external view returns (uint256);
}

/**
 * 
 * ONE Sent to this contract will be used to automatically manage the Useless Liquidity Pool
 *
 */
contract UselessFurnace {
    
    using SafeMath for uint256;
  
    /**  Useless Stats  **/
    address immutable public _token;
    address immutable public _tokenLP;
  
    /** address of wrapped ONE **/ 
    address immutable private ONE;
    
    // database
    IFurnaceDB furnaceDB;
  
    /** ONE Thresholds **/
    uint256 constant public automateThreshold = 5 * 10**16;
    uint256 constant max_ONE_in_call = 100000 * 10**18;
  
    /** Pancakeswap Router **/
    IUniswapV2Router02 constant router = IUniswapV2Router02(0x10ED43C718714eb63d5aA57B78B54704E256024E);
  
    /** Flash-Loan Prevention **/
    uint256 lastBlockAutomated;
    
    /** ONE -> Token **/
    address[] private ONEToToken;

    constructor(address _useless, address _uselessLP, address _furnaceDB) {
        // Instantiate Token and LP
        _token = _useless;
        _tokenLP = _uselessLP;
        // WETH
        ONE = router.WETH();
        // ONE -> Token
        ONEToToken = new address[](2);
        ONEToToken[0] = router.WETH();
        ONEToToken[1] = _useless;

        // furnace database
        furnaceDB = IFurnaceDB(_furnaceDB);
    }
  
    /** Automate Function */
    function BURN_IT_DOWN_BABY() external {
        require(lastBlockAutomated < block.number, 'Same Block Entry');
        lastBlockAutomated = block.number;
        automate();
    }
    
    function getRanges() public view returns (uint256 pL, uint256 bbr, uint256 rsal) {
        pL = furnaceDB.pullLiquidityRange();
        bbr = furnaceDB.buyAndBurnRange();
        rsal = furnaceDB.reverseSALRange();
    }

    /** Automate Function */
    function automate() private {
        // check useless standing
        checkUselessStanding();
        // determine the health of the lp
        uint256 dif = determineLPHealth();
        // check cases
        dif = clamp(dif, 1, 10000);
        
        (uint256 pullLiquidityRange, uint256 buyAndBurnRange, uint256 reverseSALRange) = getRanges();
    
        if (dif <= pullLiquidityRange) {
            uint256 percent = uint256(10000).div(dif);
            pullLiquidity(percent);
        } else if (dif <= buyAndBurnRange) {
            buyAndBurn();
        } else if (dif <= reverseSALRange) {
            reverseSwapAndLiquify();
        } else {
            uint256 tokenBal = IERC20(_token).balanceOf(address(this));
            if (liquidityThresholdReached(tokenBal)) {
                pairLiquidity(tokenBal);
            } else {
                reverseSwapAndLiquify();
            }
        }
    }

    /**
     * Buys USELESS Tokens and burns them
     */ 
    function buyAndBurn() private {
        // keep ONE in range
        uint256 ONEToUse = address(this).balance > max_ONE_in_call ? max_ONE_in_call : address(this).balance;
        // buy and burn it
        router.swapExactETHForTokensSupportingFeeOnTransferTokens{value: ONEToUse}(
            0, 
            ONEToToken,
            address(this), // store
            block.timestamp.add(30)
        );
        // received from swap
        uint256 bal = IERC20(_token).balanceOf(address(this));
        if (bal > 0) {
            _burn(bal);
        }
        
        // tell blockchain
        emit BuyAndBurn(ONEToUse);
    }
  
   /**
    * Uses ONE in Contract to Purchase Useless, pairs with remaining ONE and adds to Liquidity Pool
    * Reversing The Effects Of SwapAndLiquify
    * Price Positive - LP Neutral Operation
    */
    function reverseSwapAndLiquify() private {
        // ONE Balance before the swap
        uint256 initialBalance = address(this).balance > max_ONE_in_call ? max_ONE_in_call : address(this).balance;
        // USELESS Balance before the Swap
        uint256 contractBalance = IERC20(_token).balanceOf(address(this));
        // Swap 50% of the ONE in Contract for USELESS Tokens
        uint256 transferAMT = initialBalance.div(2);
        // Swap ONE for USELESS
        router.swapExactETHForTokens{value: transferAMT}(
            0, // accept any amount of USELESS
            ONEToToken,
            address(this), // Store in Contract
            block.timestamp.add(30)
        );
        // how many USELESS Tokens were received
        uint256 diff = IERC20(_token).balanceOf(address(this)).sub(contractBalance);
        // add liquidity to Pancakeswap
        addLiquidity(diff, transferAMT);
        emit ReverseSwapAndLiquify(diff, transferAMT);
    }
   
    /**
     * Pairs ONE and USELESS in the contract and adds to liquidity if we are above thresholds 
     */
    function pairLiquidity(uint256 uselessInContract) private {
        // amount of ONE in the pool
        uint256 ONELP = IERC20(ONE).balanceOf(_tokenLP);
        // make sure we have tokens in LP
        ONELP = ONELP == 0 ? address(_tokenLP).balance : ONELP;
        // how much ONE do we need to pair with our useless
        uint256 ONEBal = getTokenInToken(_token, ONE, uselessInContract);
        //if there isn't enough ONE in contract
        if (address(this).balance < ONEBal) {
            // recalculate with ONE we have
            uint256 nUseless = uselessInContract.mul(address(this).balance).div(ONEBal);
            addLiquidity(nUseless, address(this).balance);
            emit LiquidityPairAdded(nUseless, address(this).balance);
        } else {
            // pair liquidity as is 
            addLiquidity(uselessInContract, ONEBal);
            emit LiquidityPairAdded(uselessInContract, ONEBal);
        }
    }
    
    /** Checks Number of Tokens in LP */
    function checkUselessStanding() private {
        uint256 threshold = getCirculatingSupply().div(10**4);
        uint256 uselessBalance = IERC20(_token).balanceOf(address(this));
        if (uselessBalance >= threshold) {
            // burn 1/4 of balance
            _burn(uselessBalance.div(2));
        }
    }
    
    function _burn(uint256 portion) internal {
        IUseless(_token).burn(portion);
    }
   
    /** Returns the price of tokenOne in tokenTwo according to Pancakeswap */
    function getTokenInToken(address tokenOne, address tokenTwo, uint256 amtTokenOne) public view returns (uint256){
        address[] memory path = new address[](2);
        path[0] = tokenOne;
        path[1] = tokenTwo;
        return router.getAmountsOut(amtTokenOne, path)[1];
    } 
    
    /**
     * Adds USELESS and ONE to the USELESS/ONE Liquidity Pool
     */ 
    function addLiquidity(uint256 uselessAmount, uint256 ONEAmount) private {
       
        // approve router to move tokens
        IERC20(_token).approve(address(router), uselessAmount);
        // add the liquidity
        router.addLiquidityETH{value: ONEAmount}(
            _token,
            uselessAmount,
            0,
            0,
            address(this),
            block.timestamp.add(30)
        );
    }

    /**
     * Removes Liquidity from the pool and stores the ONE and USELESS in the contract
     */
    function pullLiquidity(uint256 percentLiquidity) private returns (bool){
       // Percent of our LP Tokens
       uint256 pLiquidity = IERC20(_tokenLP).balanceOf(address(this)).mul(percentLiquidity).div(10**2);
       // Approve Router 
       IERC20(_tokenLP).approve(address(router), pLiquidity);
       // remove the liquidity
       router.removeLiquidityETHSupportingFeeOnTransferTokens(
            _token,
            pLiquidity,
            0,
            0,
            address(this),
            block.timestamp.add(30)
        );
        
        emit LiquidityPulled(percentLiquidity, pLiquidity);
        return true;
    }
    
    /**
     * Determines the Health of the LP
     * returns the percentage of the Circulating Supply that is in the LP
     */ 
    function determineLPHealth() public view returns(uint256) {
        // Find the balance of USELESS in the liquidity pool
        uint256 lpBalance = IERC20(_token).balanceOf(_tokenLP).mul(2);
        // lpHealth = Supply / LP Balance
        return lpBalance == 0 ? 2 : getCirculatingSupply().mul(100).div(lpBalance);
    }
    
    /** Whether or not the Pair Liquidity Threshold has been reached */
    function liquidityThresholdReached(uint256 bal) private view returns (bool) {
        return bal >= getCirculatingSupply().div(10**7);
    }
  
    /** Returns the Circulating Supply of Token */
    function getCirculatingSupply() private view returns(uint256) {
        return IERC20(_token).totalSupply();
    }
  
    /** Amount of LP Tokens in this contract */ 
    function getLPTokenBalance() external view returns (uint256) {
        return IERC20(_tokenLP).balanceOf(address(this));
    }
  
    /** Percentage of LP Tokens In Contract */
    function getPercentageOfLPTokensOwned() external view returns (uint256) {
        return uint256(10**18).mul(IERC20(_tokenLP).balanceOf(address(this))).div(IERC20(_tokenLP).totalSupply());
    }
      
    /** Clamps a variable between a min and a max */
    function clamp(uint256 variable, uint256 min, uint256 max) private pure returns (uint256){
        if (variable <= min) {
            return min;
        } else if (variable >= max) {
            return max;
        } else {
            return variable;
        }
    }
  
    // EVENTS 
    event BuyAndBurn(uint256 amountONEUsed);
    event ReverseSwapAndLiquify(uint256 uselessAmount,uint256 ONEAmount);
    event LiquidityPairAdded(uint256 uselessAmount,uint256 ONEAmount);
    event LiquidityPulled(uint256 percentOfLiquidity, uint256 numLPTokens);

    // Receive ONE
    receive() external payable { }

}