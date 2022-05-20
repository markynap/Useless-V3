//SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

/*
    @title Proxyable a minimal proxy contract based on the EIP-1167 .
    @notice Using this contract is only necessary if you need to create large quantities of a contract.
        The use of proxies can significantly reduce the cost of contract creation at the expense of added complexity
        and as such should only be used when absolutely necessary. you must ensure that the memory of the created proxy
        aligns with the memory of the proxied contract. Inspect the created proxy during development to ensure it's
        functioning as intended.
    @custom::warning Do not destroy the contract you create a proxy too. Destroying the contract will corrupt every proxied
        contracted created from it.
*/
contract Proxyable {
    bool private proxy;

    /// @notice checks to see if this is a proxy contract
    /// @return proxy returns false if this is a proxy and true if not
    function isProxy() external view returns (bool) {
        return proxy;
    }

    /// @notice A modifier to ensure that a proxy contract doesn't attempt to create a proxy of itself.
    modifier isProxyable() {
        require(!proxy, "Unable to create a proxy from a proxy");
        _;
    }

    /// @notice initialize a proxy setting isProxy_ to true to prevents any further calls to initialize_
    function initialize_() external isProxyable {
        proxy = true;
    }

    /// @notice creates a proxy of the derived contract
    /// @return proxyAddress the address of the newly created proxy
    function createProxy() external isProxyable returns (address proxyAddress) {
        // the address of this contract because only a non-proxy contract can call this
        bytes20 deployedAddress = bytes20(address(this));
        assembly {
        // load the free memory pointer
            let fmp := mload(0x40)
        // first 20 bytes of built in proxy bytecode
            mstore(fmp, 0x3d602d80600a3d3981f3363d3d373d3d3d363d73000000000000000000000000)
        // store 20 bytes from the target address at the 20th bit (inclusive)
            mstore(add(fmp, 0x14), deployedAddress)
        // store the remaining bytes
            mstore(add(fmp, 0x28), 0x5af43d82803e903d91602b57fd5bf30000000000000000000000000000000000)
        // create a new contract using the proxy memory and return the new address
            proxyAddress := create(0, fmp, 0x37)
        }
        // intiialize the proxy above to set its isProxy_ flag to true
        Proxyable(proxyAddress).initialize_();
    }
}
