pragma solidity 0.8.20; //Do not change the solidity version as it negatively impacts submission grading
// SPDX-License-Identifier: MIT

import "@openzeppelin/contracts/access/Ownable.sol";
import "./YourToken.sol";

contract Vendor is Ownable {

    event BuyTokens(address buyer, uint256 amountOfETH, uint256 amountOfTokens);
    event SellTOkens(address seller, uint256 amountOfETH, uint256 amountOfTokens);

    YourToken public yourToken;

    uint256 public constant tokensPerEth = 100;


    constructor(address tokenAddress) Ownable(msg.sender) {
        yourToken = YourToken(tokenAddress);
    }

    function buyTokens() external payable{
        require(msg.value > 0 ,'no eth sended');
        uint256 tokens = msg.value * tokensPerEth;
        require(yourToken.balanceOf(address(this)) >= tokens);
        require(yourToken.transfer(msg.sender, tokens),'transfer failed');
        emit BuyTokens(msg.sender, msg.value, tokens);
    }

    function withdraw() external onlyOwner() {
        require(address(this).balance > 0 , 'no eth to withdraw');
        (bool send,) = msg.sender.call{value : address(this).balance}("");
        require(send,'call failed');
        
    }

    function sellTokens(uint256 amount) external{
        require(yourToken.balanceOf(msg.sender) >= amount , 'do not have enough tokens');
        require(yourToken.allowance(msg.sender, address(this)) >= amount,'not enough allowance');
        require(yourToken.transferFrom(msg.sender,address(this), amount),'transfer failed');
        uint256 ethAmount = amount / tokensPerEth;
        require(address(this).balance >= ethAmount,'not enough ether in contract');
        (bool send,) = msg.sender.call{value : ethAmount}("");
        require(send,'call failed');
        emit SellTOkens(msg.sender, ethAmount, amount);
    }
}


