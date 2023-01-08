//SPDX-License-Identifier: Unlicense
pragma solidity >=0.6.6;

import "hardhat/console.sol";

// Uniswap interface and library imports
import "./libraries/UniswapV2Library.sol";
import "./libraries/SafeERC20.sol";
import "./interfaces/IUniswapV2Router01.sol";
import "./interfaces/IUniswapV2Router02.sol";
import "./interfaces/IUniswapV2Pair.sol";
import "./interfaces/IUniswapV2Factory.sol";
import "./interfaces/IERC20.sol";

contract PancakeFlashSwap {
    using SafeERC20 for IERC20;

    address private constant PANCAKE_FACTORY =
        0xcA143Ce32Fe78f1f7019d7d551a6402fC5350c73;
    address private constant PANCAKE_ROUTER =
        0x10ED43C718714eb63d5aA57B78B54704E256024E;

    address private constant WBNB = 0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c;
    address private constant BUSD = 0xe9e7CEA3DedcA5984780Bafc599bD69ADd087D56;
    address private constant CAKE = 0x0E09FaBB73Bd3Ade0a17ECC321fD13a19e81cE82;
    address private constant ALICE = 0xAC51066d7bEC65Dc4589368da368b212745d63E8;

    uint256 private deadline = block.timestamp + 1 days;
    uint256 private constant MAX_INT =
        115792089237316195423570985008687907853269984665640564039457584007913129639935;


    function getBalanceOfToken(address _address) public view returns (uint256) {
        return IERC20(_address).balanceOf(address(this));
    }

    // PLACE A TRADE
    function placeTrade(
        address _fromToken,
        address _toToken,
        uint256 _amountIn
    ) private returns (uint256) {
        address pair = IUniswapV2Factory(PANCAKE_FACTORY).getPair(
            _fromToken,
            _toToken
        );
        require(pair != address(0), "Pool does not exist");

        address[] memory path = new address[](2);
        path[0] = _fromToken;
        path[1] = _toToken;

        uint256 amountRequired = IUniswapV2Router01(PANCAKE_ROUTER)
            .getAmountsOut(_amountIn, path)[1];

        uint256 amountReceived = IUniswapV2Router01(PANCAKE_ROUTER)
            .swapExactTokensForTokens(
                _amountIn, 
                amountRequired, 
                path,
                address(this),
                deadline 
            )[1];

        require(amountReceived > 0, "Aborted Tx: Trade returned zero");

        return amountReceived;
    }

    function checkProfitability(uint256 _input, uint256 _output)
        private
        returns (bool)
    {
        return _output > _input;
    }

    // ARBITRAGE
    function startArbitrage(address _tokenBorrow, uint256 _amount) external {
        IERC20(BUSD).safeApprove(address(PANCAKE_ROUTER), MAX_INT);
        IERC20(ALICE).safeApprove(address(PANCAKE_ROUTER), MAX_INT);
        IERC20(CAKE).safeApprove(address(PANCAKE_ROUTER), MAX_INT);

        address pair = IUniswapV2Factory(PANCAKE_FACTORY).getPair(
            _tokenBorrow,
            WBNB
        );

        require(pair != address(0), "Pool does not exist");

        address token0 = IUniswapV2Pair(pair).token0();
        address token1 = IUniswapV2Pair(pair).token1();
        uint256 amount0Out = _tokenBorrow == token0 ? _amount : 0;
        uint256 amount1Out = _tokenBorrow == token1 ? _amount : 0;


        bytes memory data = abi.encode(_tokenBorrow, _amount, msg.sender);

    
        IUniswapV2Pair(pair).swap(amount0Out, amount1Out, address(this), data);
    }

    function pancakeCall(
        address _sender,
        uint256 _amount0,
        uint256 _amount1,
        bytes calldata _data
    ) external {

        address token0 = IUniswapV2Pair(msg.sender).token0();
        address token1 = IUniswapV2Pair(msg.sender).token1();
        address pair = IUniswapV2Factory(PANCAKE_FACTORY).getPair(
            token0,
            token1
        );
        require(msg.sender == pair, "The sender needs to match the pair");
        require(_sender == address(this), "Sender should match this contract");

        (address tokenBorrow, uint256 amount, address myAddress) = abi.decode(
            _data,
            (address, uint256, address)
        );


        uint256 fee = ((amount * 3) / 997) + 1;
        uint256 amountToRepay = amount + fee;


        uint256 loanAmount = _amount0 > 0 ? _amount0 : _amount1;


        uint256 trade1AcquiredCoin = placeTrade(BUSD, ALICE, loanAmount);
        uint256 trade2AcquiredCoin = placeTrade(ALICE, CAKE, trade1AcquiredCoin);
        uint256 trade3AcquiredCoin = placeTrade(CAKE, BUSD, trade2AcquiredCoin);

        // Check Profitability
        bool profCheck = checkProfitability(amountToRepay, trade3AcquiredCoin);
        require(profCheck, "Arbitrage not profitable");

        IERC20 otherToken = IERC20(BUSD);
        otherToken.transfer(myAddress, trade3AcquiredCoin - amountToRepay);

        // Pay Loan Back
        IERC20(tokenBorrow).transfer(pair, amountToRepay);
    }
}
