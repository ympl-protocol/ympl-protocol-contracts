pragma solidity 0.6.6;

import "@openzeppelin/contracts/access/Ownable.sol";

import "./lib/SafeMathInt.sol";
import "./lib/UInt256Lib.sol";
import "./UFragments.sol";

/*
 __     __              _                 _                  _ 
 \ \   / /             | |               | |                | |
  \ \_/ / __ ___  _ __ | |_ __  _ __ ___ | |_ ___   ___ ___ | |
   \   / '_ ` _ \| '_ \| | '_ \| '__/ _ \| __/ _ \ / __/ _ \| |
    | || | | | | | |_) | | |_) | | | (_) | || (_) | (_| (_) | |
    |_||_| |_| |_| .__/|_| .__/|_|  \___/ \__\___/ \___\___/|_|
                 | |     | |                                   
                 |_|     |_|

  credit to our big brother Ampleforth                                                  
*/

interface IOracle {
    function update() external;

    function consult(address token, uint256 amountIn)
        external
        view
        returns (uint256 amountOut);
}

/**
 * @title uFragments Monetary Supply Policy
 * @dev This is an implementation of the uFragments Ideal Money protocol.
 *      uFragments operates symmetrically on expansion and contraction. It will both split and
 *      combine coins to maintain a stable unit price.
 *
 *      This component regulates the token supply of the uFragments ERC20 token in response to
 *      market oracles.
 */
contract UFragmentsPolicy is Ownable {
    using SafeMath for uint256;
    using SafeMathInt for int256;
    using UInt256Lib for uint256;

    event LogRebase(
        uint256 indexed epoch,
        uint256 exchangeRate,
        int256 requestedSupplyAdjustment,
        uint256 timestampSec,
        uint256 randomNumber,
        uint256 rebaseLag,
        string reason
    );

    event setRebaseBlockNumber(uint256 blockNumber);

    event blockNumberOverflow(uint256 blockNumber, uint256 blockNumberToRebase);

    UFragments public uFrags;

    // Market oracle provides the token/USD exchange rate as an 18 decimal fixed point number.
    // (eg) An oracle value of 1.5e18 it would mean 1 Ample is trading for $1.50.
    IOracle public marketOracle;

    // If the current exchange rate is within this fractional distance from the target, no supply
    // update is performed. Fixed point number--same format as the rate.
    // (ie) abs(rate - targetRate) / targetRate < deviationThreshold, then no supply change.
    // DECIMALS Fixed point number.
    uint256 public deviationThreshold;

    // The rebase lag parameter, used to dampen the applied supply adjustment by 1 / rebaseLag
    // Check setRebaseLag comments for more details.
    // Natural number, no decimal places.
    uint256 public rebaseLagBase;

    // additional random rebaseLag
    uint256 public rebaseLagRandomAddition;

    // More than this much time must pass between rebase operations.
    uint256 public minRebaseTimeIntervalSec;

    // Block timestamp of last rebase operation
    uint256 public lastRebaseTimestampSec;

    // The rebase window begins this many seconds into the minRebaseTimeInterval period.
    // For example if minRebaseTimeInterval is 24hrs, it represents the time of day in seconds.
    uint256 public rebaseWindowOffsetSec;

    // The number of rebase cycles since inception
    uint256 public epoch;

    uint256 private constant DECIMALS = 18;

    // Due to the expression in computeSupplyDelta(), MAX_RATE * MAX_SUPPLY must fit into an int256.
    // Both are 18 decimals fixed point numbers.
    uint256 private constant MAX_RATE = 10**6 * 10**DECIMALS;
    // MAX_SUPPLY = MAX_INT256 / MAX_RATE
    uint256 private constant MAX_SUPPLY = ~(uint256(1) << 255) / MAX_RATE;

    // This module orchestrates the rebase execution and downstream notification.
    address public orchestrator;

    uint256 public constant offset_random_blocknumber = 2;

    // block number for getting hash to rebase
    uint256 public blockNumberToRebase = 0;

    // the chance to rebase successfully
    uint256 public chanceToRebasePercent = 25;

    // gurantee first rebase
    bool public firstRebase = true;

    // 0.0025 eth rate
    uint256 public targetEthRate = 2500000000000000;

    bool public rebaseInit = false;

    constructor(UFragments uFrags_) public {
        // deviationThreshold = 0.05e18 = 5e16
        deviationThreshold = 5 * 10**(DECIMALS - 2);

        rebaseLagBase = 6;
        rebaseLagRandomAddition = 4;
        minRebaseTimeIntervalSec = 4 hours;
        rebaseWindowOffsetSec = 0;
        lastRebaseTimestampSec = 0;
        epoch = 0;

        uFrags = uFrags_;
    }

    modifier onlyOrchestrator() {
        require(msg.sender == orchestrator);
        _;
    }

    function rand(uint256 blocknumber) internal view returns (uint256) {
        uint256 randomNumber = uint256(blockhash(blocknumber));
        return randomNumber;
    }

    /**
     * @notice set next rebase block hash
     *
     * @dev we use future blockhash as source for randomness, this will be safe until network is mature we will moving to chainlink VCR
     */

    function setNextRebaseBlock() public {
        require(rebaseInit, "rebase period not yet initialized");
        require(
            blockNumberToRebase == 0,
            "cannot set next rebase block, already set"
        );
        require(inRebaseWindow(), "You need to wait for next rebase window");

        blockNumberToRebase = block.number.add(offset_random_blocknumber);
        emit setRebaseBlockNumber(blockNumberToRebase);
    }

    function initRebasePeriod() external onlyOwner {
        require(!rebaseInit, "rebase period already initialized");
        rebaseInit = true;
        // snap the last rebase to now on first time, so next period work properly.
        lastRebaseTimestampSec = now;
    }

    /**
     * @notice Initiates a new rebase operation, provided the minimum time period has elapsed.
     *
     * @dev The supply adjustment equals (_totalSupply * DeviationFromTargetRate) / rebaseLag
     *      Where DeviationFromTargetRate is (MarketOracleRate - targetRate) / targetRate
     *      and targetRate is 1 ** 18
     */

    function rebase() external onlyOrchestrator {
        require(inRebaseWindow(), "Cannot rebase, out of rebase window");
        require(isFutureBlockSet(), "Please initialze rebase first");
        require(
            canRebaseWithFutureBlock(),
            "Cannot rebase, future block not reached"
        );
        require(rebaseInit, "rebase period not yet initialized");
        // unsecure random with future hash the rebase probabilty is 25%, we can rebase every 4 hours 6 times a day
        // rebase can be called every 4 hours. unsecure random chance is fine due to miner and everyone
        // will have the same incentive if it gets included.
        // possible outcome [0, 1 , 2...,100]
        uint256 randomNumber = rand(blockNumberToRebase);
        if (randomNumber == 0) {
            // this is incase 256 block passed, guard agaist it and return to new cycle
            // reset blockNumberToRebase to zero so we can call it again.
            blockNumberToRebase = 0;
            emit blockNumberOverflow(block.number, blockNumberToRebase);
            return;
        }
        uint256 randomZeroToHundred = randomNumber.mod(100);

        // Snap the rebase time to now.
        lastRebaseTimestampSec = now;

        // random between rebase lag + (randomNumber % rebaseLagRandomAddition + 1)
        // eg 6 + (N % 5) = 6 + [0, 4] ~ 6 - 10
        uint256 rebaseLag = rebaseLagBase.add(
            randomNumber.mod(rebaseLagRandomAddition + 1)
        );

        epoch = epoch.add(1);

        // 1 YMPL
        uint256 oneToken = 1 * 10**uFrags.decimals();

        marketOracle.update();

        uint256 exchangeRate = marketOracle.consult(address(uFrags), oneToken);

        if (exchangeRate > MAX_RATE) {
            exchangeRate = MAX_RATE;
        }

        int256 supplyDelta = computeSupplyDelta(exchangeRate, targetEthRate);

        // Apply the Dampening factor.
        supplyDelta = supplyDelta.div(rebaseLag.toInt256Safe());

        if (
            supplyDelta > 0 &&
            uFrags.totalSupply().add(uint256(supplyDelta)) > MAX_SUPPLY
        ) {
            supplyDelta = (MAX_SUPPLY.sub(uFrags.totalSupply())).toInt256Safe();
        }

        // 1/4 is equal to 25 percent, blockNumberToRebase should not be zero if setted
        if (
            (randomZeroToHundred <= chanceToRebasePercent &&
                blockNumberToRebase != 0) || firstRebase
        ) {
            uint256 supplyAfterRebase = uFrags.rebase(epoch, supplyDelta);
            assert(supplyAfterRebase <= MAX_SUPPLY);
            emit LogRebase(
                epoch,
                exchangeRate,
                supplyDelta,
                now,
                randomZeroToHundred,
                rebaseLag,
                firstRebase ? "first-rebase" : "rebased"
            );
            // only gurantee first time
            firstRebase = false;
        } else {
            emit LogRebase(
                epoch,
                exchangeRate,
                supplyDelta,
                now,
                randomZeroToHundred,
                rebaseLag,
                "not rebased"
            );
        }
        // once rebased, we reset to zero so we can call it again.
        blockNumberToRebase = 0;
    }

    /**
     * @notice Sets the reference to the market oracle.
     * @param marketOracle_ The address of the market oracle contract.
     */
    function setMarketOracle(IOracle marketOracle_) external onlyOwner {
        marketOracle = marketOracle_;
    }

    /**
     * @notice Sets the reference to the orchestrator.
     * @param orchestrator_ The address of the orchestrator contract.
     */
    function setOrchestrator(address orchestrator_) external onlyOwner {
        orchestrator = orchestrator_;
    }

    /**
     * @notice Sets the deviation threshold fraction. If the exchange rate given by the market
     *         oracle is within this fractional distance from the targetRate, then no supply
     *         modifications are made. DECIMALS fixed point number.
     * @param deviationThreshold_ The new exchange rate threshold fraction.
     */
    function setDeviationThreshold(uint256 deviationThreshold_)
        external
        onlyOwner
    {
        deviationThreshold = deviationThreshold_;
    }

    /**
     * @notice Sets the rebase lag parameter.
               It is used to dampen the applied supply adjustment by 1 / rebaseLag
               If the rebase lag R, equals 1, the smallest value for R, then the full supply
               correction is applied on each rebase cycle.
               If it is greater than 1, then a correction of 1/R of is applied on each rebase.
     * @param rebaseLagBase_ The new rebaseLagBase lag parameter.
     * @param rebaseLagRandomAddition_ The new rebaseLagRandomAddition_ lag parameter.
     */
    function setRebaseLag(
        uint256 rebaseLagBase_,
        uint256 rebaseLagRandomAddition_
    ) external onlyOwner {
        require(rebaseLagBase_ > 0);
        require(rebaseLagRandomAddition_ > 0);
        rebaseLagBase = rebaseLagBase_;
        rebaseLagRandomAddition = rebaseLagRandomAddition_;
    }

    /**
     * @notice Sets the parameters which control the timing and frequency of
     *         rebase operations.
     *         a) the minimum time period that must elapse between rebase cycles.
     *         b) the rebase window offset parameter.
     *         c) the rebase window length parameter.
     * @param minRebaseTimeIntervalSec_ More than this much time must pass between rebase
     *        operations, in seconds.
     * @param rebaseWindowOffsetSec_ The number of seconds from the beginning of
              the rebase interval, where the rebase window begins.
     */
    function setRebaseTimingParameters(
        uint256 minRebaseTimeIntervalSec_,
        uint256 rebaseWindowOffsetSec_
    ) external onlyOwner {
        require(minRebaseTimeIntervalSec_ > 0);
        require(rebaseWindowOffsetSec_ < minRebaseTimeIntervalSec_);

        minRebaseTimeIntervalSec = minRebaseTimeIntervalSec_;
        rebaseWindowOffsetSec = rebaseWindowOffsetSec_;
    }

    /**
     * @notice Set chance to rebase percent
     * @param chanceToRebasePercent_ Chance to rebase percent
     */
    function setChanceToRebasePercent(uint256 chanceToRebasePercent_)
        external
        onlyOwner
    {
        require(chanceToRebasePercent <= 100 && chanceToRebasePercent >= 0);
        chanceToRebasePercent = chanceToRebasePercent_;
    }

    /**
     * @return If the latest block timestamp is within the rebase time window it, returns true.
     *         Otherwise, returns false.
     */
    function inRebaseWindow() public view returns (bool) {
        return now > lastRebaseTimestampSec.add(minRebaseTimeIntervalSec);
    }

    function canRebaseWithFutureBlock() public view returns (bool) {
        return block.number > blockNumberToRebase;
    }

    /**
     * @dev check if rebase blocknumber has been set
     * @return future block set?
     */
    function isFutureBlockSet() public view returns (bool) {
        return blockNumberToRebase > 0;
    }

    /**
     * @return Computes the total supply adjustment in response to the exchange rate
     *         and the targetRate.
     */
    function computeSupplyDelta(uint256 rate, uint256 targetRate)
        private
        view
        returns (int256)
    {
        if (withinDeviationThreshold(rate, targetRate)) {
            return 0;
        }

        // supplyDelta = totalSupply * (rate - targetRate) / targetRate
        int256 targetRateSigned = targetRate.toInt256Safe();
        return
            uFrags
                .totalSupply()
                .toInt256Safe()
                .mul(rate.toInt256Safe().sub(targetRateSigned))
                .div(targetRateSigned);
    }

    /**
     * @param rate The current exchange rate, an 18 decimal fixed point number.
     * @param targetRate The target exchange rate, an 18 decimal fixed point number.
     * @return If the rate is within the deviation threshold from the target rate, returns true.
     *         Otherwise, returns false.
     */
    function withinDeviationThreshold(uint256 rate, uint256 targetRate)
        private
        view
        returns (bool)
    {
        uint256 absoluteDeviationThreshold = targetRate
            .mul(deviationThreshold)
            .div(10**DECIMALS);

        return
            (rate >= targetRate &&
                rate.sub(targetRate) < absoluteDeviationThreshold) ||
            (rate < targetRate &&
                targetRate.sub(rate) < absoluteDeviationThreshold);
    }
}
