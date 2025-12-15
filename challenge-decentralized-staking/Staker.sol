// SPDX-License-Identifier: MIT
pragma solidity 0.8.20; //Do not change the solidity version as it negatively impacts submission grading

import "hardhat/console.sol";
import "./ExampleExternalContract.sol";

contract Staker {
    ExampleExternalContract public exampleExternalContract;

    event Stake(address, uint256);

    mapping(address => uint256) public balances;
    uint256 public constant threshold = 1 ether;
    uint256 public deadline;

    constructor(address exampleExternalContractAddress) {
        exampleExternalContract = ExampleExternalContract(exampleExternalContractAddress);
        deadline = block.timestamp + 30 seconds;
    }

    function stake() external payable {
        require(msg.value > 0);
        balances[msg.sender] = msg.value;
        emit Stake(msg.sender, msg.value);
    }

    function execute() external {
        // require(,"not enough money");
        require(block.timestamp >= deadline,"deadline not reached");
        require(!exampleExternalContract.completed(),"execute called before");
        if(address(this).balance >= threshold){
        exampleExternalContract.complete{value : address(this).balance}();
        }
    }

    function withdraw() external {
        require(address(this).balance < threshold,"threashold is met");
        (bool send,) = msg.sender.call{value : balances[msg.sender]}("");
        require(send);
    }

    function timeLeft() view external returns (uint256) {
        if(block.timestamp >= deadline){
            return uint256(0);
        }
        return deadline - block.timestamp;
    }


    receive() external payable{
        this.stake();
    }

}
