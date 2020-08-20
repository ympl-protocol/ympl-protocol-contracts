pragma solidity 0.6.6;

import "@openzeppelin/contracts/access/Ownable.sol";

import "./UFragmentsPolicy.sol";

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

/**
 * @title Orchestrator
 * @notice The orchestrator is the main entry point for rebase operations. It coordinates the policy
 * actions with external consumers.
 */
contract Orchestrator is Ownable {
    struct Transaction {
        bool enabled;
        address destination;
        bytes data;
    }

    event TransactionFailed(
        address indexed destination,
        uint256 index,
        bytes data
    );

    // Stable ordering is not guaranteed.
    Transaction[] public transactions;

    UFragmentsPolicy public policy;

    /**
     * @param policy_ Address of the UFragments policy.
     */
    constructor(address policy_) public {
        policy = UFragmentsPolicy(policy_);
    }

    /**
     * @notice Main entry point to initiate a rebase operation.
     *         The Orchestrator calls rebase on the policy and notifies downstream applications.
     *         Contracts are guarded from calling, to avoid flash loan attacks on liquidity
     *         providers.
     *         If a transaction in the transaction list reverts, it is swallowed and the remaining
     *         transactions are executed.
     */
    function rebase() external {
        require(msg.sender == tx.origin); // solhint-disable-line avoid-tx-origin

        policy.rebase();

        for (uint256 i = 0; i < transactions.length; i++) {
            Transaction storage t = transactions[i];
            if (t.enabled) {
                bool result = externalCall(t.destination, t.data);
                if (!result) {
                    emit TransactionFailed(t.destination, i, t.data);
                    revert("Transaction Failed");
                }
            }
        }
    }

    /**
     * @notice Adds a transaction that gets called for a downstream receiver of rebases
     * @param destination Address of contract destination
     * @param data Transaction data payload
     */
    function addTransaction(address destination, bytes calldata data)
        external
        onlyOwner
    {
        transactions.push(
            Transaction({enabled: true, destination: destination, data: data})
        );
    }

    /**
     * @param index Index of transaction to remove.
     *              Transaction ordering may have changed since adding.
     */
    function removeTransaction(uint256 index) external onlyOwner {
        require(index < transactions.length, "index out of bounds");

        if (index < transactions.length - 1) {
            transactions[index] = transactions[transactions.length - 1];
            transactions.pop();
        }
    }

    /**
     * @param index Index of transaction. Transaction ordering may have changed since adding.
     * @param enabled True for enabled, false for disabled.
     */
    function setTransactionEnabled(uint256 index, bool enabled)
        external
        onlyOwner
    {
        require(
            index < transactions.length,
            "index must be in range of stored tx list"
        );
        transactions[index].enabled = enabled;
    }

    /**
     * @return Number of transactions, both enabled and disabled, in transactions list.
     */
    function transactionsSize() external view returns (uint256) {
        return transactions.length;
    }

    /**
     * @dev wrapper to call the encoded transactions on downstream consumers.
     * @param destination Address of destination contract.
     * @param data The encoded data payload.
     * @return True on success
     */
    function externalCall(address destination, bytes memory data)
        internal
        returns (bool)
    {
        (bool result, ) = destination.call(data);
        return result;
    }

    /**
     * @dev set policy contract address for future protocol update
     * @param policy_ The policy.
     */
    function setPolicy(address policy_) external onlyOwner {
        policy = UFragmentsPolicy(policy_);
    }
}
