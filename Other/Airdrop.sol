//SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

import "./Ownable.sol";

contract Airdrop is Ownable {

    address public token;
    uint256 public numberAirdropped;
    event AirDroppedList(uint nUsersAirdropped);

    constructor(address token_){
        token = token_;
    }

    function airDrop(address[] users, uint256[] amounts) external onlyOwner {
        require(
            users.length == amounts.length,
            'Invalid Length'
        );
        for (uint i = 0; i < users.length; i++) {
            if (amounts[i] > 0) {
                IERC20(token).transfer(
                    users[i],
                    amounts[i]
                );
                numberAirdropped++;
            }
        }
        emit AirDroppedList(users.length);
    }

    function withdraw(uint amount) external onlyOwner {
        IERC20(token).transfer(msg.sender, amount);
    }

    function withdraw() external onlyOwner {
        (bool s,) = payable(msg.sender).call{value: address(this).balance}("");
        require(s);
    }
}