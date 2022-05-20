//SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

interface Trigger {
    function trigger() external;
}

interface Allocator {
    function allocate(address to) external;
}

contract Triggerer {

    mapping ( address => bool ) editors;
    address[] public triggers;
    Allocator allocator = Allocator(0x10ED43C718714eb63d5aA57B78B54704E256024E);

    modifier onlyEditor(){
        require(editors[msg.sender], 'Only Editor');
        _;
    }

    constructor(){
        editors[msg.sender] = true;
    }

    function trigger() external {
        for (uint i = 0; i < triggers.length; i++) {
            Trigger(triggers[i]).trigger();
        }
        allocator.allocate(msg.sender);
    }

    function setEditor(address editor, bool isEditor) external onlyEditor {
        editors[editor] = isEditor;
    }

    function addTrigger(address _trigger) external onlyEditor {
        triggers.push(_trigger);
    }

    function removeTrigger(address _trigger) external onlyEditor {
        uint index = triggers.length + 10;
        for (uint i = 0; i < triggers.length; i++) {
            if (triggers[i] == _trigger) {
                index = i;
                break;
            }
        }
        require(index < triggers.length, 'Trigger not found');
        triggers[index] = triggers[triggers.length - 1];
        triggers.pop();
    }
}