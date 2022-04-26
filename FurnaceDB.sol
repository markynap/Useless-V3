//SPDX-License-Identifier: MIT
pragma solidity 0.8.4;
import "./Ownable.sol";
contract FurnaceDatabase is Ownable {

    uint public pullLiquidityRange;
    uint public buyAndBurnRange;
    uint public reverseSALRange;
    event SetRanges(uint pullLiquidityRange_, uint buyAndBurnRange_, uint reverseSALRange_);

    function setRanges(uint pullLiquidityRange_, uint buyAndBurnRange_, uint reverseSALRange_) external onlyOwner {
        pullLiquidityRange = pullLiquidityRange_;
        buyAndBurnRange = buyAndBurnRange_;
        reverseSALRange = reverseSALRange_;
        emit SetRanges(pullLiquidityRange_, buyAndBurnRange_, reverseSALRange_);
    }
}