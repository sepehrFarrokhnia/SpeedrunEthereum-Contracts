// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "./Lending.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract FlashLoanLiquidator is IFlashLoanRecipient, Ownable {
    receive() external payable {}

    Corn private i_corn;
    CornDEX private i_cornDEX;
    Lending private i_lending;

    constructor(address _lending, address _cornDEX, address _corn) Ownable(msg.sender) {
        i_lending = Lending(_lending);
        i_cornDEX = CornDEX(_cornDEX);
        i_corn = Corn(_corn);
    }

    function executeOperation(uint256 amount, address initiator, address extraParam) external returns (bool) {
        require(i_corn.balanceOf(address(this)) >= amount, "corn not received");
        require(i_lending.isLiquidatable(extraParam), "user not liquidatable");

        uint256 userBorrow = i_lending.s_userBorrowed(extraParam);
        require(amount < userBorrow, "not enough corn sended");

        i_corn.approve(address(i_lending), userBorrow);
        i_lending.liquidate(extraParam);

        require(address(this).balance > 0, "no eth recived");

        uint256 userBorrowedInEth = i_cornDEX.calculateXInput(
            userBorrow,
            address(i_cornDEX).balance,
            i_corn.balanceOf(address(i_cornDEX))
        );

        i_cornDEX.swap{value : userBorrowedInEth}(userBorrowedInEth);
        i_corn.approve(address(i_lending), amount);
        
        if(address(this).balance > 0){
        (bool sent,) = initiator.call{value : address(this).balance}("");
        require(sent,'call failed');
        }

        return true;
    }
}
