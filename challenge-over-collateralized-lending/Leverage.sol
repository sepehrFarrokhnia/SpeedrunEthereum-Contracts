// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { Lending } from "./Lending.sol";
import { CornDEX } from "./CornDEX.sol";
import { Corn } from "./Corn.sol";

/**
 * @notice For Side quest only
 * @notice This contract is used to leverage a user's position by borrowing CORN from the Lending contract
 * then borrowing more CORN from the DEX to repay the initial borrow then repeating until the user has borrowed as much as they want
 */
contract Leverage {
    Lending i_lending;
    CornDEX i_cornDEX;
    Corn i_corn;
    address public owner;

    event LeveragedPositionOpened(address user, uint256 loops);
    event LeveragedPositionClosed(address user, uint256 loops);

    modifier onlyOwner() {
        require(msg.sender == owner, "Only the owner can call this function");
        _;
    }

    constructor(address _lending, address _cornDEX, address _corn) {
        i_lending = Lending(_lending);
        i_cornDEX = CornDEX(_cornDEX);
        i_corn = Corn(_corn);
        // Approve DEX and Lending to spend the user's CORN
        i_corn.approve(address(i_cornDEX), type(uint256).max);
        i_corn.approve(address(i_lending), type(uint256).max);
    }
    
    /**
     * @notice Claim ownership of the contract so that no one else can change your position or withdraw your funds
     */
    function claimOwnership() public {
        owner = msg.sender;
    }

    /**
     * @notice Open a leveraged position, iteratively borrowing CORN, swapping it for ETH, and adding it as collateral
     * @param reserve The amount of ETH that we will keep in the contract as a reserve to prevent liquidation
     */
    function openLeveragedPosition(uint256 reserve) public payable onlyOwner {
        uint256 loops = 0;
        while (address(this).balance > reserve) {
            uint256 balance = address(this).balance;
            i_lending.addCollateral{value: balance}();

            if (balance <= reserve) {
                break;
            }

            uint256 maxBorrowAmount = i_lending.getMaxBorrowAmount(balance);
            i_lending.borrowCorn(maxBorrowAmount);
            
            i_cornDEX.swap(maxBorrowAmount);
            loops++;
        }
        emit LeveragedPositionOpened(msg.sender, loops);
    }

    /**
     * @notice Close a leveraged position, iteratively withdrawing collateral, swapping it for CORN, and repaying the lending contract until the position is closed
     */
    function closeLeveragedPosition() public onlyOwner {
        uint256 loops = 0;
        while (true) {
            uint256 maxWithdraw = i_lending.getMaxWithdrawableCollateral(address(this));
            i_lending.withdrawCollateral(maxWithdraw);

            uint256 tokens = i_cornDEX.swap{value : maxWithdraw}(maxWithdraw);

            if(tokens > i_lending.s_userBorrowed(address(this))){
                tokens -= i_lending.s_userBorrowed(address(this));
                i_lending.repayCorn(i_lending.s_userBorrowed(address(this)));
                i_cornDEX.swap(tokens);
                break;
            }else {
                i_lending.repayCorn(tokens);
            }

            
            loops++;
        }
        emit LeveragedPositionClosed(msg.sender, loops);
    }

    /**
     * @notice Withdraw the ETH from the contract
     */
    function withdraw() public onlyOwner {
        uint256 balance = address(this).balance;
        require(balance > 0, "No balance to withdraw");
        (bool success, ) = payable(msg.sender).call{value: balance}("");
        require(success, "Failed to send Ether");
    }

    receive() external payable {}
}