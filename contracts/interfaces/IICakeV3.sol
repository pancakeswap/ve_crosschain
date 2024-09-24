// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

interface IICakeV3 {

    function admin() external view returns (address);

    function getVeCakeUser(address _user) external view returns (address);

    function getUserCredit(address _user) external view returns (uint256);
}
