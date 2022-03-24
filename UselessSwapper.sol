//SPDX-License-Identifier: MIT
pragma solidity 0.8.4;
import "./IUniswapV2Router02.sol";

contract Swapper {

    // dex router
    IUniswapV2Router02 router;

    constructor(address _router, address _useless){
        router = IUniswapV2Router02(_router);
        path = new address[](2);
        path[0] = router.WETH();
        path[1] = _useless;
    }

    // swap ONE for useless
    receive() external payable {
        router.swapExactETHForTokensSupportingFeeOnTransferTokens{value: msg.value}(0, path, tx.origin, block.timestamp + 300);
    }
}