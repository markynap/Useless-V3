//SPDX-License-Identifier: MIT
pragma solidity 0.8.4;
import "./IERC20.sol";

contract Migration {

    mapping ( address => uint256 ) public recipients;
    mapping ( address => uint256 ) public migrators;
    address[] allMigrators;
    address[] allRecipients;
    address useless = 0x2cd2664Ce5639e46c6a3125257361e01d0213657;
    address caller  = 0x091dD81C8B9347b30f1A4d5a88F92d6F2A42b059;
    event Migrate(address sender, address recipient, uint256 amount);

    function migrate(uint amount, address recipient) external {
        require(
            amount > 0 && recipient != address(0),
            'Invalid Arguments'
        );

        bool s = IERC20(useless).transferFrom(msg.sender, address(this), amount);
        require(s, 'Approval Not Given');

        if (migrators[msg.sender] == 0) {
            allMigrators.push(msg.sender);
        }
        if (recipients[recipient] == 0) {
            allRecipients.push(recipient);
        }

        migrators[msg.sender] += amount;
        recipients[recipient] += amount;

        emit Migrate(msg.sender, recipient, amount);
    }
    function getAllMigrators() external view returns (address[] memory) {
        return allMigrators();
    }
    function getAllRecipients() external view returns (address[] memory) {
        return allRecipients();
    }
    function withdraw(uint amount) external {
        require(msg.sender == caller);
        _withdraw(amount);
    }
    function withdraw() external {
        require(msg.sender == caller);
        _withdraw(IERC20(useless).balanceOf(address(this)));
    }
    function _withdraw(uint amount) internal {
        IERC20(useless).transfer(caller, amount);
    }
}