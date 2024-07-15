// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

/** @title IIFODeployerV8.
 * @notice It is an interface for IFODeployerV8.sol
 */
interface IIFODeployerV8 {

    function previousIFOAddress() external view returns (address);

    function currIFOAddress() external view returns (address);
}