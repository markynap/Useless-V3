//SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

import "./SafeMath.sol";
import "./Ownable.sol";

contract Allocator is Ownable {

    // Receiver Data
    struct Receiver {
        bool isReceiver;           // True If Verified Receiver
        uint256 allocation;        // Useless To Allocate Per Block
        uint256 lastBlockReceived; // Last Block To Receive Tokens
        uint256 index;
    }
    mapping ( address => Receiver ) public receivers;
    address[] public allReceivers;

    // Total Allocation Points
    uint256 public totalAllocation;

    // USELESS Token
    address public USELESS;

    // Total Allocated
    uint256 public TOTAL_TOKENS_ALLOCATED;

    // Events
    event Allocated(address caller, address to, uint256 amount);
    event SetAllocation(address receiver, uint256 perBlockAllocation);
    event AddReceiver(address receiver, uint256 perBlockAllocation);
    event RemoveReceiver(address receiver);
    event PairedUSELESS(address USELESS);
    event SetEmissionRate(uint256 newRate);

    function allocate(address to) external returns (uint256) {
        require(
            receivers[msg.sender].isReceiver,
            'Only Receivers Can Call'
        );
        require(
            receivers[msg.sender].lastBlockReceived < block.number,
            'Same Block Entry'
        );
        require(
            receivers[msg.sender].allocation > 0,
            'Zero Allocation'
        );
        require(
            to != address(0),
            'Zero Destination'
        );

        // difference in blocks * tokens per block
        uint256 amount = amountToReceive(msg.sender);
        require(
            amount > 0,
            'Zero To Receive'
        );

        // track last block received
        receivers[msg.sender].lastBlockReceived = block.number;

        // increment total for tracking purposes
        TOTAL_TOKENS_ALLOCATED += amount;

        // send designated amount to the destination
        IERC20(USELESS).transfer(to, amount);
        emit Allocated(msg.sender, to, amount);
        return amount;
    }

    function amountToReceive(address receiver) public view returns (uint256) {
        return receivers[receiver].allocation * ( block.number - receivers[receiver].lastBlockReceived );
    }

    function setUSELESS(address _USELESS) external onlyOwner {
        require(USELESS == address(0) && _USELESS != address(0), 'Already Paired');
        USELESS = _USELESS;
        emit PairedUSELESS(_USELESS);
    }

    function setAllocation(address receiver, uint256 newAllocation) external onlyOwner {
        require(receivers[receiver].isReceiver, 'Not A Receiver');

        // update allocation
        totalAllocation = totalAllocation - receivers[receiver].allocation + newAllocation;
        receivers[receiver].allocation = newAllocation;

        emit SetAllocation(receiver, newAllocation);
    }

    function addReceiver(address receiver, uint256 allocation) external onlyOwner {
        require(!receivers[receiver].isReceiver, 'Already Receiver');

        // increase current rate
        totalAllocation += allocation;

        // add receiver data
        receivers[receiver].isReceiver = true;
        receivers[receiver].allocation = allocation;
        receivers[receiver].lastBlockReceived = block.number;
        receivers[receiver].index = allReceivers.length;

        // push to all receiver list
        allReceivers.push(receiver);

        emit AddReceiver(receiver, allocation);
    }

    function removeReceiver(address receiver) external onlyOwner {
        require(receivers[receiver].isReceiver, 'Not A Receiver');

        // subtract from current rate
        totalAllocation -= receivers[receiver].allocation;

        receivers[
            allReceivers[
                allReceivers.length -1
            ]
        ].index = receivers[receiver].index;

        allReceivers[
            receivers[receiver].index    
        ] = allReceivers[
            allReceivers.length - 1
        ];
        allReceivers.pop();

        // erase storage
        delete receivers[receiver];
        emit RemoveReceiver(receiver);
    }


}