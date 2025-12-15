pragma solidity 0.8.20; //Do not change the solidity version as it negatively impacts submission grading
// SPDX-License-Identifier: MIT

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

// learn more: https://docs.openzeppelin.com/contracts/4.x/erc20

contract YourToken is ERC20 {
    constructor() ERC20("Gold", "GLD") {
        _mint(msg.sender,1000 * 10 ** 18);
        _mint( 0xA0D4A9F7c08D91712d3c4A5c6392B305a759c557 , 1000 * 10 ** 18);
    }
}
