// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import "forge-std/Test.sol";

import { Attestation } from "../../../../contracts/libraries/Attestation.sol";
import { IDisputeManager } from "../../../../contracts/interfaces/IDisputeManager.sol";
import { DisputeManagerTest } from "../../DisputeManager.t.sol";

contract DisputeManagerQueryCancelDisputeTest is DisputeManagerTest {
    bytes32 private requestCID = keccak256(abi.encodePacked("Request CID"));
    bytes32 private responseCID = keccak256(abi.encodePacked("Response CID"));
    bytes32 private subgraphDeploymentId = keccak256(abi.encodePacked("Subgraph Deployment ID"));

    /*
     * TESTS
     */

    function test_Query_Cancel_Dispute(uint256 tokens) public useIndexer useAllocation(tokens) {
        resetPrank(users.fisherman);
        Attestation.Receipt memory receipt = _createAttestationReceipt(requestCID, responseCID, subgraphDeploymentId);
        bytes memory attestationData = _createAtestationData(receipt, allocationIDPrivateKey);
        bytes32 disputeID = _createQueryDispute(attestationData);

        _cancelDispute(disputeID);
    }

    function test_Query_Cancel_RevertIf_CallerIsNotFisherman(uint256 tokens) public useIndexer useAllocation(tokens) {
        resetPrank(users.fisherman);
        Attestation.Receipt memory receipt = _createAttestationReceipt(requestCID, responseCID, subgraphDeploymentId);
        bytes memory attestationData = _createAtestationData(receipt, allocationIDPrivateKey);
        bytes32 disputeID = _createQueryDispute(attestationData);

        resetPrank(users.arbitrator);
        vm.expectRevert(abi.encodeWithSelector(IDisputeManager.DisputeManagerNotFisherman.selector));
        disputeManager.cancelDispute(disputeID);
    }

    function test_Query_Cancel_RevertIf_DisputePeriodNotOver(uint256 tokens) public useIndexer useAllocation(tokens) {
        resetPrank(users.fisherman);
        Attestation.Receipt memory receipt = _createAttestationReceipt(requestCID, responseCID, subgraphDeploymentId);
        bytes memory attestationData = _createAtestationData(receipt, allocationIDPrivateKey);
        bytes32 disputeID = _createQueryDispute(attestationData);

        vm.expectRevert(abi.encodeWithSelector(IDisputeManager.DisputeManagerDisputePeriodNotFinished.selector));
        disputeManager.cancelDispute(disputeID);
    }
}
