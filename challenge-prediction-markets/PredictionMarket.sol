//SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 <0.9.0;

import { PredictionMarketToken } from "./PredictionMarketToken.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

contract PredictionMarket is Ownable {
    /////////////////
    /// Errors //////
    /////////////////

    error PredictionMarket__MustProvideETHForInitialLiquidity();
    error PredictionMarket__InvalidProbability();
    error PredictionMarket__PredictionAlreadyReported();
    error PredictionMarket__OnlyOracleCanReport();
    error PredictionMarket__OwnerCannotCall();
    error PredictionMarket__PredictionNotReported();
    error PredictionMarket__InsufficientWinningTokens();
    error PredictionMarket__AmountMustBeGreaterThanZero();
    error PredictionMarket__MustSendExactETHAmount();
    error PredictionMarket__InsufficientTokenReserve(Outcome _outcome, uint256 _amountToken);
    error PredictionMarket__TokenTransferFailed();
    error PredictionMarket__ETHTransferFailed();
    error PredictionMarket__InsufficientBalance(uint256 _tradingAmount, uint256 _userBalance);
    error PredictionMarket__InsufficientAllowance(uint256 _tradingAmount, uint256 _allowance);
    error PredictionMarket__InsufficientLiquidity();
    error PredictionMarket__InvalidPercentageToLock();

    //////////////////////////
    /// State Variables //////
    //////////////////////////

    enum Outcome {
        YES,
        NO
    }

    uint256 private constant PRECISION = 1e18;

    address public i_oracle;
    uint256 public i_initialTokenValue;
    uint8 public i_initialYesProbability;
    uint8 public i_percentageLocked;

    PredictionMarketToken public i_yesToken;
    PredictionMarketToken public i_noToken;

    string public s_question;
    uint256 public s_ethCollateral;
    uint256 public s_lpTradingRevenue;
    bool public s_isReported = false;
    PredictionMarketToken public s_winningToken;

    /////////////////////////
    /// Events //////
    /////////////////////////

    event TokensPurchased(address indexed buyer, Outcome outcome, uint256 amount, uint256 ethAmount);
    event TokensSold(address indexed seller, Outcome outcome, uint256 amount, uint256 ethAmount);
    event WinningTokensRedeemed(address indexed redeemer, uint256 amount, uint256 ethAmount);
    event MarketReported(address indexed oracle, Outcome winningOutcome, address winningToken);
    event MarketResolved(address indexed resolver, uint256 totalEthToSend);
    event LiquidityAdded(address indexed provider, uint256 ethAmount, uint256 tokensAmount);
    event LiquidityRemoved(address indexed provider, uint256 ethAmount, uint256 tokensAmount);

    /////////////////
    /// Modifiers ///
    /////////////////

    modifier amountGreaterThanZero(uint256 _amount) {
        if (_amount <= 0) {
            revert PredictionMarket__AmountMustBeGreaterThanZero();
        }
        _;
    }

    modifier predictionNotReported() {
        if (s_isReported) {
            revert PredictionMarket__PredictionAlreadyReported();
        }
        _;
    }

    modifier predictionReported() {
        if (!s_isReported) {
            revert PredictionMarket__PredictionNotReported();
        }
        _;
    }

    modifier notOwner() {
        if (msg.sender == owner()) {
            revert PredictionMarket__OwnerCannotCall();
        }
        _;
    }

    //////////////////
    ////Constructor///
    //////////////////

    constructor(
        address _liquidityProvider,
        address _oracle,
        string memory _question,
        uint256 _initialTokenValue,
        uint8 _initialYesProbability,
        uint8 _percentageToLock
    ) payable Ownable(_liquidityProvider) {
        if (msg.value == 0) {
            revert PredictionMarket__MustProvideETHForInitialLiquidity();
        }
        if (_initialYesProbability >= 100 || _initialYesProbability == 0) {
            revert PredictionMarket__InvalidProbability();
        }

        if (_percentageToLock >= 100 || _percentageToLock == 0) {
            revert PredictionMarket__InvalidPercentageToLock();
        }
        s_ethCollateral += msg.value;
        s_question = _question;
        i_oracle = _oracle;
        i_initialTokenValue = _initialTokenValue;
        i_initialYesProbability = _initialYesProbability;
        i_percentageLocked = _percentageToLock;

        uint256 tokenAmount = (msg.value * PRECISION) / _initialTokenValue;
        i_yesToken = new PredictionMarketToken("Yes", "Y", msg.sender, tokenAmount);
        i_noToken = new PredictionMarketToken("No", "N", msg.sender, tokenAmount);

        if (_percentageToLock >= 100) {
            revert PredictionMarket__InvalidPercentageToLock();
        }

        uint256 amountToLockYes = (tokenAmount * _initialYesProbability * _percentageToLock * 2) / 10000;
        uint256 amountToLockNo = (tokenAmount * (100 - _initialYesProbability) * _percentageToLock * 2) / 10000;

        bool yesTransfer = i_yesToken.transfer(msg.sender, amountToLockYes);
        bool noTransfer = i_noToken.transfer(msg.sender, amountToLockNo);

        if (!yesTransfer || !noTransfer) {
            revert PredictionMarket__TokenTransferFailed();
        }
    }

    /////////////////
    /// Functions ///
    /////////////////

    /**
     * @notice Add liquidity to the prediction market and mint tokens
     * @dev Only the owner can add liquidity and only if the prediction is not reported
     */
    function addLiquidity() external payable onlyOwner amountGreaterThanZero(msg.value) predictionNotReported {
        uint256 tokenAmount = (msg.value * PRECISION) / i_initialTokenValue;
        s_ethCollateral += msg.value;
        i_yesToken.mint(address(this), tokenAmount);
        i_noToken.mint(address(this), tokenAmount);

        emit LiquidityAdded(msg.sender, msg.value, tokenAmount);
    }

    /**
     * @notice Remove liquidity from the prediction market and burn respective tokens, if you remove liquidity before prediction ends you got no share of lpReserve
     * @dev Only the owner can remove liquidity and only if the prediction is not reported
     * @param _ethToWithdraw Amount of ETH to withdraw from liquidity pool
     */
    function removeLiquidity(
        uint256 _ethToWithdraw
    ) external onlyOwner amountGreaterThanZero(_ethToWithdraw) predictionNotReported {
        uint256 tokenAmount = (_ethToWithdraw * i_initialTokenValue) / PRECISION;

        if (tokenAmount > (i_yesToken.balanceOf(address(this)))) {
            revert PredictionMarket__InsufficientTokenReserve(Outcome.YES, tokenAmount);
        }

        if (tokenAmount > (i_noToken.balanceOf(address(this)))) {
            revert PredictionMarket__InsufficientTokenReserve(Outcome.NO, tokenAmount);
        }
        s_ethCollateral -= _ethToWithdraw;

        i_yesToken.burn(address(this), tokenAmount);
        i_noToken.burn(address(this), tokenAmount);

        (bool send, ) = msg.sender.call{ value: _ethToWithdraw }("");
        if (!send) {
            revert PredictionMarket__ETHTransferFailed();
        }

        emit LiquidityRemoved(msg.sender, _ethToWithdraw, tokenAmount);
    }

    /**
     * @notice Report the winning outcome for the prediction
     * @dev Only the oracle can report the winning outcome and only if the prediction is not reported
     * @param _winningOutcome The winning outcome (YES or NO)
     */
    function report(Outcome _winningOutcome) external predictionNotReported {
        if (msg.sender != i_oracle) {
            revert PredictionMarket__OnlyOracleCanReport();
        }
        s_winningToken = _winningOutcome == Outcome.NO ? i_noToken : i_yesToken;
        s_isReported = true;
        emit MarketReported(msg.sender, _winningOutcome, address(s_winningToken));
    }

    /**
     * @notice Owner of contract can redeem winning tokens held by the contract after prediction is resolved and get ETH from the contract including LP revenue and collateral back
     * @dev Only callable by the owner and only if the prediction is resolved
     * @return ethRedeemed The amount of ETH redeemed
     */
    function resolveMarketAndWithdraw() external onlyOwner predictionReported returns (uint256 ethRedeemed) {
        uint256 availableWinningToken = s_winningToken.balanceOf(address(this));
        if (availableWinningToken > 0) {
            ethRedeemed = (availableWinningToken * i_initialTokenValue) / PRECISION;
            ethRedeemed = ethRedeemed > s_ethCollateral ? s_ethCollateral : ethRedeemed;
            s_ethCollateral -= ethRedeemed;

            s_winningToken.burn(address(this), availableWinningToken);
        }

        uint256 ethToPay = ethRedeemed + s_lpTradingRevenue;
        s_lpTradingRevenue = 0;

        (bool send, ) = msg.sender.call{ value: ethToPay }("");
        if (!send) {
            revert PredictionMarket__ETHTransferFailed();
        }
        emit MarketResolved(msg.sender, ethToPay);
        return ethRedeemed;
    }

    /**
     * @notice Buy prediction outcome tokens with ETH, need to call priceInETH function first to get right amount of tokens to buy
     * @param _outcome The possible outcome (YES or NO) to buy tokens for
     * @param _amountTokenToBuy Amount of tokens to purchase
     */
    function buyTokensWithETH(
        Outcome _outcome,
        uint256 _amountTokenToBuy
    )
        external
        payable
        amountGreaterThanZero(_amountTokenToBuy)
        amountGreaterThanZero(msg.value)
        predictionNotReported
        notOwner
    {
        uint256 price = getBuyPriceInEth(_outcome, _amountTokenToBuy);
        if (msg.value != price) {
            revert PredictionMarket__MustSendExactETHAmount();
        }
        s_lpTradingRevenue += msg.value;
        PredictionMarketToken token = _outcome == Outcome.NO ? i_noToken : i_yesToken;
        bool isTransfer = token.transfer(msg.sender, _amountTokenToBuy);
        if (!isTransfer) {
            revert PredictionMarket__TokenTransferFailed();
        }
        emit TokensPurchased(msg.sender, _outcome, _amountTokenToBuy, price);
    }

    /**
     * @notice Sell prediction outcome tokens for ETH, need to call priceInETH function first to get right amount of tokens to buy
     * @param _outcome The possible outcome (YES or NO) to sell tokens for
     * @param _tradingAmount The amount of tokens to sell
     */
    function sellTokensForEth(
        Outcome _outcome,
        uint256 _tradingAmount
    ) external amountGreaterThanZero(_tradingAmount) predictionNotReported notOwner {
        uint256 price = getSellPriceInEth(_outcome, _tradingAmount);
        PredictionMarketToken token = _outcome == Outcome.NO ? i_noToken : i_yesToken;

        if (s_lpTradingRevenue < price) {
            revert PredictionMarket__InsufficientBalance(_tradingAmount, token.balanceOf(msg.sender));
        }
        if (token.balanceOf(msg.sender) < _tradingAmount) {
            revert PredictionMarket__InsufficientBalance(_tradingAmount, token.balanceOf(msg.sender));
        }
        if (token.allowance(msg.sender, address(this)) < _tradingAmount) {
            revert PredictionMarket__InsufficientAllowance(_tradingAmount, token.allowance(msg.sender, address(this)));
        }
        bool isTransfer = token.transferFrom(msg.sender, address(this), _tradingAmount);
        if (!isTransfer) {
            revert PredictionMarket__TokenTransferFailed();
        }
        (bool sent, ) = msg.sender.call{ value: price }("");
        if (!sent) {
            revert PredictionMarket__ETHTransferFailed();
        }
        emit TokensSold(msg.sender, _outcome, _tradingAmount, price);
    }

    /**
     * @notice Redeem winning tokens for ETH after prediction is resolved, winning tokens are burned and user receives ETH
     * @dev Only if the prediction is resolved
     * @param _amount The amount of winning tokens to redeem
     */
    function redeemWinningTokens(uint256 _amount) external amountGreaterThanZero(_amount) predictionReported notOwner(){
        if (s_winningToken.balanceOf(msg.sender) < _amount) {
            revert PredictionMarket__InsufficientWinningTokens();
        }
        s_winningToken.burn(msg.sender, _amount);
        uint256 price = _amount * i_initialTokenValue / PRECISION;
        (bool sent, ) = msg.sender.call{ value: price }("");
        if (!sent) {
            revert PredictionMarket__ETHTransferFailed();
        }
        emit WinningTokensRedeemed(msg.sender, _amount, price);
    }

    /**
     * @notice Calculate the total ETH price for buying tokens
     * @param _outcome The possible outcome (YES or NO) to buy tokens for
     * @param _tradingAmount The amount of tokens to buy
     * @return The total ETH price
     */
    function getBuyPriceInEth(Outcome _outcome, uint256 _tradingAmount) public view returns (uint256) {
        return _calculatePriceInEth(_outcome, _tradingAmount, false);
    }

    /**
     * @notice Calculate the total ETH price for selling tokens
     * @param _outcome The possible outcome (YES or NO) to sell tokens for
     * @param _tradingAmount The amount of tokens to sell
     * @return The total ETH price
     */
    function getSellPriceInEth(Outcome _outcome, uint256 _tradingAmount) public view returns (uint256) {
        return _calculatePriceInEth(_outcome, _tradingAmount, true);
    }

    /////////////////////////
    /// Helper Functions ///
    ////////////////////////

    /**
     * @dev Internal helper to calculate ETH price for both buying and selling
     * @param _outcome The possible outcome (YES or NO)
     * @param _tradingAmount The amount of tokens
     * @param _isSelling Whether this is a sell calculation
     */
    function _calculatePriceInEth(
        Outcome _outcome,
        uint256 _tradingAmount,
        bool _isSelling
    ) private view amountGreaterThanZero(_tradingAmount) returns (uint256) {
        (uint256 primaryReserve, uint256 secondaryReserve) = _getCurrentReserves(_outcome);

        if (!_isSelling && primaryReserve < _tradingAmount) {
            revert PredictionMarket__InsufficientLiquidity();
        }

        uint256 tokenTotalSupply = i_yesToken.totalSupply();
        uint256 primarySold = tokenTotalSupply - primaryReserve;
        uint256 secondarySold = tokenTotalSupply - secondaryReserve;

        uint256 currentProbability = _calculateProbability(primarySold, (primarySold + secondarySold));

        primarySold = _isSelling ? (primarySold - _tradingAmount) : (primarySold + _tradingAmount);
        uint256 afterProbability = _calculateProbability(primarySold, (primarySold + secondarySold));

        uint256 avgProbability = (currentProbability + afterProbability) / 2;

        return (i_initialTokenValue * avgProbability * _tradingAmount) / (PRECISION * PRECISION);
    }

    /**
     * @dev Internal helper to get the current reserves of the tokens
     * @param _outcome The possible outcome (YES or NO)
     * @return The current reserves of the tokens
     */
    function _getCurrentReserves(Outcome _outcome) private view returns (uint256, uint256) {
        if (_outcome == Outcome.YES) {
            return (i_yesToken.balanceOf(address(this)), i_noToken.balanceOf(address(this)));
        }
        return (i_noToken.balanceOf(address(this)), i_yesToken.balanceOf(address(this)));
    }

    /**
     * @dev Internal helper to calculate the probability of the tokens
     * @param tokensSold The number of tokens sold
     * @param totalSold The total number of tokens sold
     * @return The probability of the tokens
     */
    function _calculateProbability(uint256 tokensSold, uint256 totalSold) private pure returns (uint256) {
        return (tokensSold * PRECISION) / totalSold;
    }

    /////////////////////////
    /// Getter Functions ///
    ////////////////////////

    /**
     * @notice Get the prediction details
     */
    function getPrediction()
        external
        view
        returns (
            string memory question,
            string memory outcome1,
            string memory outcome2,
            address oracle,
            uint256 initialTokenValue,
            uint256 yesTokenReserve,
            uint256 noTokenReserve,
            bool isReported,
            address yesToken,
            address noToken,
            address winningToken,
            uint256 ethCollateral,
            uint256 lpTradingRevenue,
            address predictionMarketOwner,
            uint256 initialProbability,
            uint256 percentageLocked
        )
    {
        oracle = i_oracle;
        initialTokenValue = i_initialTokenValue;
        percentageLocked = i_percentageLocked;
        initialProbability = i_initialYesProbability;
        question = s_question;
        ethCollateral = s_ethCollateral;
        lpTradingRevenue = s_lpTradingRevenue;
        predictionMarketOwner = owner();
        yesToken = address(i_yesToken);
        noToken = address(i_noToken);
        outcome1 = i_yesToken.name();
        outcome2 = i_noToken.name();
        yesTokenReserve = i_yesToken.balanceOf(address(this));
        noTokenReserve = i_noToken.balanceOf(address(this));
        isReported = s_isReported;
        winningToken = address(s_winningToken);
    }
}
