//SPDX-License-Identifier: MIT
pragma solidity 0.8.4;
import "./IUniswapV2Router02.sol";
import "./IERC20.sol";
import "./Ownable.sol";

interface IUseless {
    function permissions(address user) external view returns (bool,uint,bool,uint,bool,bool);
    function buyFeeRecipient() external view returns (address);
}

contract Swapper is Ownable {

    // dex router
    IUniswapV2Router02 router;

    // max tax
    uint256 public maxTax = 30;
    uint256 public minTax = 0;
    uint256 private constant DENOM = 1000;

    // min and max amounts
    uint256 public minAmount = 10 * 10**18;
    uint256 public maxAmount = 100 * 10**18;

    // useless
    address public useless;
    address[] path;

    constructor(address _router, address _useless){
        router = IUniswapV2Router02(_router);
        useless = _useless;
        path = new address[](2);
        path[0] = router.WETH();
        path[1] = _useless;
    }

    function withdraw() external onlyOwner {
        (bool s,) = payable(msg.sender).call{value: address(this).balance}("");
        require(s);
    }
    
    function withdrawTokens(address token) external onlyOwner {
        IERC20(token).transfer(
            msg.sender,
            IERC20(token).balanceOf(address(this))
        );
    }

    function setMinMaxTax(uint minTax_, uint maxTax_) external onlyOwner {
        minTax = minTax_;
        maxTax = maxTax_;
    }

    function setMinMaxAmounts(uint minAmount_, uint maxAmount_) external onlyOwner {
        minAmount = minAmount_;
        maxAmount = maxAmount_;
    }

    function gradientSwap(address recipient, uint256 minOut) external payable {
        require(
            recipient != address(0) &&
            msg.value > 0,
            'Zero Values'
        );

        // is sender tx exempt
        (bool inExempt,,,,,) = IUseless(useless).permissions(msg.sender);

        // make sure contract is ingress-exempt and egress-exempt
        router.swapExactETHForTokensSupportingFeeOnTransferTokens{value: msg.value}(minOut, path, address(this), block.timestamp + 300);

        // amount received
        uint256 balance = IERC20(useless).balanceOf(address(this));

        // recipient
        address feeRecipient = IUseless(useless).buyFeeRecipient();

        // impose seocndary tax
        uint tax = inExempt ? 0 : getTax(balance, msg.value);

        // transfer tax to recipient
        if (tax > 0 && feeRecipient != address(0)) {
            IERC20(useless).transfer(feeRecipient, tax);
        }
    
        // transfer useless to buyer
        IERC20(useless).transfer(
            recipient,
            IERC20(useless).balanceOf(address(this))
        );
    }

    function getTax(uint amount, uint value) public view returns (uint256) {

        if (value <= minAmount) {
            return ( amount * maxTax ) / DENOM;
        }

        if (value >= maxAmount) {
            return 0;
        }

        // amount * tax * (( maxAmount - value )/ maxAmount )
        return ( ( amount * maxTax * ( maxAmount - value ) ) / ( maxAmount * DENOM ) );
    }

    // swap ONE for useless
    receive() external payable {
        router.swapExactETHForTokensSupportingFeeOnTransferTokens{value: msg.value}(0, path, tx.origin, block.timestamp + 300);
    }
}