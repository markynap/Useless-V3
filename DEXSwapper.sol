//SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

import "./IUniswapV2Router02.sol";
import "./Ownable.sol";
import "./IERC20.sol";
import "./SafeMath.sol";

interface IPair {
    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);
    function swap(uint amount0Out, uint amount1Out, address to, bytes calldata data) external;
}

interface IWETH {
    function withdraw(uint256 amount) external;
}

contract DEXSwapper is Ownable {

    using SafeMath for uint256;

    // Fee Taken On Swaps
    uint256 public fee            = 35;
    uint256 public FeeDenominator = 10000;

    // Fee Recipient
    address public feeReceiver;

    // WETH
    address public WETH;

    constructor(address WETH_, address feeReceiver_) {
        require(WETH_ != address(0), 'Zero Address');
        require(feeReceiver_ != address(0), 'Zero Address');
        WETH = WETH_;
        feeReceiver = feeReceiver_;
    }

    function setFee(uint256 newFee) external onlyOwner {
        require(
            newFee <= 200,
            'Fee Too High'
        );
        fee = newFee;
    }

    function setFeeRecipient(address newFeeRecipient) external onlyOwner {
        require(
            newFeeRecipient != address(0),
            'Zero Address'
        );
        feeReceiver = newFeeRecipient;
    }

    function swapETHForToken(address DEX, address token, uint256 amountOutMin) external payable {
        require(
            msg.value > 0,
            'Zero Value'
        );
        uint _fee = getFee(msg.value);
        _sendETH(feeReceiver, _fee);

        // instantiate router
        IUniswapV2Router02 router = IUniswapV2Router02(DEX);

        // define swap path
        address[] memory path = new address[](2);
        path[0] = WETH;
        path[1] = token;

        // make the swap
        router.swapExactETHForTokensSupportingFeeOnTransferTokens{value: msg.value - _fee}(amountOutMin, path, msg.sender, block.timestamp + 300);

        // save memory
        delete path;
    }

    function swapTokenForETH(address DEX, address token, uint256 amount, uint256 amountOutMin) external {
        require(
            amount > 0,
            'Zero Value'
        );

        // liquidity pool
        IPair pair = IPair(IUniswapV2Factory(IUniswapV2Router02(DEX).factory()).getPair(token, WETH));
        _transferIn(msg.sender, address(pair), token, amount);

        // handle swap logic
        (address input, address output) = (token, WETH);
        (address token0,) = sortTokens(input, output);
        uint amountInput;
        uint amountOutput;
        { // scope to avoid stack too deep errors
        (uint reserve0, uint reserve1,) = pair.getReserves();
        (uint reserveInput, uint reserveOutput) = input == token0 ? (reserve0, reserve1) : (reserve1, reserve0);
        amountInput = IERC20(input).balanceOf(address(pair)).sub(reserveInput);
        amountOutput = getAmountOut(amountInput, reserveInput, reserveOutput);
        }
        (uint amount0Out, uint amount1Out) = input == token0 ? (uint(0), amountOutput) : (amountOutput, uint(0));

        // make the swap
        pair.swap(amount0Out, amount1Out, address(this), new bytes(0));

        // check output amount
        uint amountOut = IERC20(WETH).balanceOf(address(this));
        require(amountOut >= amountOutMin, 'INSUFFICIENT_OUTPUT_AMOUNT');
        IWETH(WETH).withdraw(amountOut);

        // take fee in bnb and send rest to sender
        uint _fee = getFee(amountOut);
        _sendETH(feeReceiver, _fee);
        _sendETH(msg.sender, amountOut - _fee);
    }

    function swapTokenForToken(address DEX, address tokenIn, address tokenOut, uint256 amountIn, uint256 amountOutMin) external {
        require(
            amountIn > 0,
            'Zero Value'
        );

        // fetch fee and transfer in to receiver
        uint _fee = getFee(amountIn);
        _transferIn(msg.sender, feeReceiver, tokenIn, _fee);

        // transfer rest into liquidity pool
        IPair pair = IPair(IUniswapV2Factory(IUniswapV2Router02(DEX).factory()).getPair(tokenIn, tokenOut));
        _transferIn(msg.sender, address(pair), tokenIn, amountIn - _fee);

        // handle swap logic
        (address input, address output) = (tokenIn, tokenOut);
        (address token0,) = sortTokens(input, output);
        uint amountInput;
        uint amountOutput;
        { // scope to avoid stack too deep errors
        (uint reserve0, uint reserve1,) = pair.getReserves();
        (uint reserveInput, uint reserveOutput) = input == token0 ? (reserve0, reserve1) : (reserve1, reserve0);
        amountInput = IERC20(input).balanceOf(address(pair)).sub(reserveInput);
        amountOutput = getAmountOut(amountInput, reserveInput, reserveOutput);
        }
        (uint amount0Out, uint amount1Out) = input == token0 ? (uint(0), amountOutput) : (amountOutput, uint(0));

        // make the swap
        uint before = IERC20(tokenOut).balanceOf(msg.sender);
        pair.swap(amount0Out, amount1Out, msg.sender, new bytes(0));
        uint received = IERC20(tokenOut).balanceOf(msg.sender).sub(before);

        // check output amount
        require(received >= amountOutMin, 'INSUFFICIENT_OUTPUT_AMOUNT');
    }

    // given an input amount of an asset and pair reserves, returns the maximum output amount of the other asset
    function getAmountOut(uint amountIn, uint reserveIn, uint reserveOut) internal pure returns (uint amountOut) {
        require(amountIn > 0, 'PancakeLibrary: INSUFFICIENT_INPUT_AMOUNT');
        require(reserveIn > 0 && reserveOut > 0, 'PancakeLibrary: INSUFFICIENT_LIQUIDITY');
        uint amountInWithFee = amountIn.mul(9970);
        uint numerator = amountInWithFee.mul(reserveOut);
        uint denominator = reserveIn.mul(10000).add(amountInWithFee);
        amountOut = numerator / denominator;
    }

    function sortTokens(address tokenA, address tokenB) internal pure returns (address token0, address token1) {
        require(tokenA != tokenB, 'IDENTICAL_ADDRESSES');
        (token0, token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        require(token0 != address(0), 'PancakeLibrary: ZERO_ADDRESS');
    }

    function getFee(uint256 amount) public view returns (uint256) {
        return( amount * fee ) / FeeDenominator;
    }

    function _sendETH(address receiver, uint amount) internal {
        (bool s,) = payable(receiver).call{value: amount}("");
        require(s, 'Failure On ETH Transfer');
    }

    function _transferIn(address fromUser, address toUser, address token, uint256 amount) internal returns (uint256) {
        uint before = IERC20(token).balanceOf(toUser);
        bool s = IERC20(token).transferFrom(fromUser, toUser, amount);
        uint received = IERC20(token).balanceOf(toUser) - before;
        require(
            s && received > 0 && received <= amount,
            'Error On Transfer From'
        );
        return received;
    }

    receive() external payable {}
}