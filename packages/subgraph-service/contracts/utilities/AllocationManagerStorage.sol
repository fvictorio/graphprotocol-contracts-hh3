// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.27;

import { Allocation } from "../libraries/Allocation.sol";
import { LegacyAllocation } from "../libraries/LegacyAllocation.sol";

/**
 * @title AllocationManagerStorage
 * @notice This contract holds all the storage variables for the Allocation Manager contract.
 * @custom:security-contact Please email security+contracts@thegraph.com if you find any
 * bugs. We may have an active bug bounty program.
 */
abstract contract AllocationManagerV1Storage {
    /// @notice Allocation details
    mapping(address allocationId => Allocation.State allocation) internal _allocations;

    /// @notice Legacy allocation details
    mapping(address allocationId => LegacyAllocation.State allocation) internal _legacyAllocations;

    /// @notice Tracks allocated tokens per indexer
    mapping(address indexer => uint256 tokens) public allocationProvisionTracker;

    /// @notice Maximum amount of time, in seconds, allowed between presenting POIs to qualify for indexing rewards
    uint256 public maxPOIStaleness;

    /// @notice Destination of accrued indexing rewards
    mapping(address indexer => address destination) public rewardsDestination;

    /// @notice Track total tokens allocated per subgraph deployment
    /// @dev Used to calculate indexing rewards
    mapping(bytes32 subgraphDeploymentId => uint256 tokens) internal _subgraphAllocatedTokens;

    /// @dev Gap to allow adding variables in future upgrades
    uint256[50] private __gap;
}
