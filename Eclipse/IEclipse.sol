//SPDX-License-Identifier: MIT
pragma solidity 0.8.4;
/**
 * King Of The Hill Interface
 */
interface IEclipse {
    function decay() external;
    function getTokenRepresentative() external view returns (address);
    function bind(address _token) external;
}