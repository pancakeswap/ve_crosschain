// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "@openzeppelin-4.5.0/contracts/token/ERC20/ERC20.sol";

contract MockOCToken is ERC20 {
    constructor() ERC20("MOCK OC Token", "MOC") {
        _mint(msg.sender, 100000 ether);
    }

    function decimals() public pure override returns (uint8) {
        return 18;
    }

    function mint(address _to, uint256 _amount) external {
        _mint(_to, _amount);
    }
}