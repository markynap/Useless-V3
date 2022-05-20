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
    uint256 public fee                     = 35;
    uint256 public constant FeeDenominator = 10000;

    // Fee Recipient
    address public feeReceiver;

    // WETH
    address public immutable WETH;

    // Affiliate
    struct Affiliate {
        bool isApproved;
        uint fee;
    }
    mapping ( address => Affiliate ) public affiliates;

    constructor(address WETH_, address feeReceiver_) {
        require(WETH_ != address(0), 'Zero Address');
        require(feeReceiver_ != address(0), 'Zero Address');
        WETH = WETH_;
        feeReceiver = feeReceiver_;
    }

    function registerAffiliate(address recipient, uint fee_) external onlyOwner {
        affiliates[recipient].isApproved = true;
        affiliates[recipient].fee = fee_;
    }

    function removeAffiliate(address affiliate) external onlyOwner {
        delete affiliates[affiliate];
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

    function swapETHForToken(address feeRecipient, address DEX, address token, uint256 amountOutMin, address recipient) external payable {
        require(
            msg.value > 0,
            'Zero Value'
        );
        uint _fee = getFee(msg.value);
        if (feeRecipient != feeReceiver) {
            require(
                affiliates[feeRecipient].isApproved,
                'Not Approved Affiliate'
            );

            uint hFee = _fee * affiliates[feeRecipient].fee / 100;
            if (hFee > 0) {
                _sendETH(feeRecipient, hFee);
            }
            _fee = _fee - hFee;
        }
        _sendETH(feeReceiver, _fee);

        // instantiate router
        IUniswapV2Router02 router = IUniswapV2Router02(DEX);

        // define swap path
        address[] memory path = new address[](2);
        path[0] = WETH;
        path[1] = token;

        // make the swap
        router.swapExactETHForTokensSupportingFeeOnTransferTokens{value: msg.value - _fee}(amountOutMin, path, recipient, block.timestamp + 300);

        // save memory
        delete path;
    }

    function swapTokenForETH(address feeRecipient, address DEX, address token, uint256 amount, uint256 amountOutMin, address recipient) external {
        require(
            amount > 0,
            'Zero Value'
        );

        address fRecipient_ = feeRecipient;

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
        if (fRecipient_ != feeReceiver) {
            require(
                affiliates[fRecipient_].isApproved,
                'Not Approved Affiliate'
            );

            uint hFee = _fee * affiliates[fRecipient_].fee / 100;
            if (hFee > 0) {
                _sendETH(fRecipient_, hFee);
            }
            _fee = _fee - hFee;
        }
        _sendETH(feeReceiver, _fee);
        _sendETH(recipient, amountOut - _fee);
    }

    function swapTokenForToken(address feeRecipient, address DEX, address tokenIn, address tokenOut, uint256 amountIn, uint256 amountOutMin, address recipient) external {
        require(
            amountIn > 0,
            'Zero Value'
        );
        address tokenOut_ = tokenOut;
        address recipient_ = recipient;

        // fetch fee and transfer in to receiver
        uint _fee = getFee(amountIn);
        if (feeRecipient != feeReceiver) {
            require(
                affiliates[feeRecipient].isApproved,
                'Not Approved Affiliate'
            );

            uint hFee = _fee * affiliates[feeRecipient].fee / 100;
            if (hFee > 0) {
                _transferIn(msg.sender, feeRecipient, tokenIn, hFee);
            }
            _fee = _fee - hFee;
        }
        _transferIn(msg.sender, feeReceiver, tokenIn, _fee);

        // transfer rest into liquidity pool
        IPair pair = IPair(IUniswapV2Factory(IUniswapV2Router02(DEX).factory()).getPair(tokenIn, tokenOut_));
        _transferIn(msg.sender, address(pair), tokenIn, amountIn - _fee);

        // handle swap logic
        (address input, address output) = (tokenIn, tokenOut_);
        (address token0,) = sortTokens(input, output);
        uint amountInput;
        uint amountOutput;
        { // scope to avoid stack too deep errors
        (uint reserve0, uint reserve1,) = pair.getReserves();
        (uint reserveInput, uint reserveOutput) = input == token0 ? (reserve0, reserve1) : (reserve1, reserve0);
        amountInput = IERC20(input).balanceOf(address(pair)).sub(reserveInput);
        amountOutput = getAmountOut(amountInput, reserveInput, reserveOutput);
        }
        {
        (uint amount0Out, uint amount1Out) = input == token0 ? (uint(0), amountOutput) : (amountOutput, uint(0));

        uint before = IERC20(tokenOut_).balanceOf(recipient_);
        pair.swap(amount0Out, amount1Out, recipient_, new bytes(0));
        
        // check output amount
        require(IERC20(tokenOut_).balanceOf(recipient_).sub(before) >= amountOutMin, 'INSUFFICIENT_OUTPUT_AMOUNT');
        }
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