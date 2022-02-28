//SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

import "./Ownable.sol";
import "./IERC20.sol";

contract SellFeeReceiver is Ownable {

    // USELESS token
    address public constant token = 0x10ED43C718714eb63d5aA57B78B54704E256024E;

    address public furnace;
    address public multisig;
    address public stakingContract;

    function trigger() external {
        uint balance = IERC20(token).balanceOf(address(this));
        IERC20(token).transfer(furnace, balance / 3);        
        IERC20(token).transfer(multisig, balance / 3);
        IERC20(token).transfer(stakingContract, IERC20(token).balanceOf(address(this)));
    }

    function setFurnace(address furnace_) external onlyOwner {
        furnace = furnace_;
    }
    function setMultisig(address multisig_) external onlyOwner {
        multisig = multisig_;
    }
    function setStakingContract(address stakingContract_) external onlyOwner {
        stakingContract = stakingContract_;
    }
    function withdraw() external onlyOwner {
        (bool s,) = payable(owner).call{vaule: amount}("");
        require(s);
    }
    function withdraw(address token) external onlyOwner {
        IERC20(token).transfer(owner, IERC20(token).balanceOf(address(this)));
    }
    receive() external payable {}
}