pragma solidity 0.6.6;

import "@openzeppelin/contracts/access/Ownable.sol";

import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";
import "@uniswap/lib/contracts/libraries/FixedPoint.sol";

import "@uniswap/v2-periphery/contracts/libraries/UniswapV2OracleLibrary.sol";
import "@uniswap/v2-periphery/contracts/libraries/UniswapV2Library.sol";


/*
 __     __              _                 _                  _ 
 \ \   / /             | |               | |                | |
  \ \_/ / __ ___  _ __ | |_ __  _ __ ___ | |_ ___   ___ ___ | |
   \   / '_ ` _ \| '_ \| | '_ \| '__/ _ \| __/ _ \ / __/ _ \| |
    | || | | | | | |_) | | |_) | | | (_) | || (_) | (_| (_) | |
    |_||_| |_| |_| .__/|_| .__/|_|  \___/ \__\___/ \___\___/|_|
                 | |     | |                                   
                 |_|     |_|

  credit to our big brother Ampleforth.                                                  
*/


interface IOracle {
    function update() external;

    function consult(address token, uint256 amountIn)
        external
        view
        returns (uint256 amountOut);
}

contract UniswapOracle is IOracle, Ownable {
    using FixedPoint for *;
    using SafeMath for uint256;

    IUniswapV2Pair pair;
    address public token0;
    address public token1;

    uint256 public price0CumulativeLast;
    uint256 public price1CumulativeLast;
    uint32 public blockTimestampLast;
    FixedPoint.uq112x112 public price0Average;
    FixedPoint.uq112x112 public price1Average;

    address public policy;

    constructor(
        address factory,
        address tokenA,
        address tokenB
    ) public {
        IUniswapV2Pair _pair = IUniswapV2Pair(
            UniswapV2Library.pairFor(factory, tokenA, tokenB)
        );
        pair = _pair;
        token0 = _pair.token0();
        token1 = _pair.token1();
        price0CumulativeLast = _pair.price0CumulativeLast(); // fetch the current accumulated price value (1 / 0)
        price1CumulativeLast = _pair.price1CumulativeLast(); // fetch the current accumulated price value (0 / 1)
        uint112 reserve0;
        uint112 reserve1;
        (reserve0, reserve1, blockTimestampLast) = _pair.getReserves();
        require(reserve0 != 0 && reserve1 != 0, "Oracle: NO_RESERVES"); // ensure that there's liquidity in the pair
        updatePrice();
    }

    modifier onlyPolicy() {
        require(msg.sender == policy);
        _;
    }

    function update() external override onlyPolicy {
        updatePrice();
    }

    function updatePrice() private {
        (
            uint256 price0Cumulative,
            uint256 price1Cumulative,
            uint32 blockTimestamp
        ) = UniswapV2OracleLibrary.currentCumulativePrices(address(pair));
        uint32 timeElapsed = blockTimestamp - blockTimestampLast; // overflow is desired

        // overflow is desired, casting never truncates
        // cumulative price is in (uq112x112 price * seconds) units so we simply wrap it after division by time elapsed
        price0Average = FixedPoint.uq112x112(
            uint224((price0Cumulative - price0CumulativeLast) / timeElapsed)
        );
        price1Average = FixedPoint.uq112x112(
            uint224((price1Cumulative - price1CumulativeLast) / timeElapsed)
        );

        price0CumulativeLast = price0Cumulative;
        price1CumulativeLast = price1Cumulative;
        blockTimestampLast = blockTimestamp;
    }

    // note this will always return 0 before update has been called successfully for the first time.
    function consult(address token, uint256 amountIn)
        external
        override
        view
        returns (uint256 amountOut)
    {
        if (token == token0) {
            amountOut = price0Average.mul(amountIn).decode144();
        } else {
            require(token == token1, "Oracle: INVALID_TOKEN");
            amountOut = price1Average.mul(amountIn).decode144();
        }
    }

    function consultRealTime(address token, uint256 amountIn)
        external
        view
        returns (uint256 amountOut)
    {
        (
            uint256 price0Cumulative,
            uint256 price1Cumulative,
            uint32 blockTimestamp
        ) = UniswapV2OracleLibrary.currentCumulativePrices(address(pair));
        uint32 timeElapsed = blockTimestamp - blockTimestampLast; // overflow is desired

        // same block we return latest
        if (timeElapsed == 0) {
            if (token == token0) {
                amountOut = price0Average.mul(amountIn).decode144();
            } else {
                require(token == token1, "Oracle: INVALID_TOKEN");
                amountOut = price1Average.mul(amountIn).decode144();
            }
        } else {
            // overflow is desired, casting never truncates
            // cumulative price is in (uq112x112 price * seconds) units so we simply wrap it after division by time elapsed

            if (token == token0) {
                amountOut = FixedPoint
                    .uq112x112(
                    uint224(
                        (price0Cumulative - price0CumulativeLast) / timeElapsed
                    )
                )
                    .mul(amountIn)
                    .decode144();
            } else {
                require(token == token1, "Oracle: INVALID_TOKEN");
                amountOut = FixedPoint
                    .uq112x112(
                    uint224(
                        (price1Cumulative - price1CumulativeLast) / timeElapsed
                    )
                )
                    .mul(amountIn)
                    .decode144();
            }
        }
    }

    // we only allow policy to update the price, because we remove window
    function setPolicy(address policy_) external onlyOwner {
        policy = policy_;
    }
}
