// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import { IRecurringCollector } from "@graphprotocol/horizon/contracts/interfaces/IRecurringCollector.sol";
import { PausableUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import { ProvisionManager } from "@graphprotocol/horizon/contracts/data-service/utilities/ProvisionManager.sol";

import { Allocation } from "../../../contracts/libraries/Allocation.sol";
import { AllocationManager } from "../../../contracts/utilities/AllocationManager.sol";
import { ISubgraphService } from "../../../contracts/interfaces/ISubgraphService.sol";

import { SubgraphServiceIndexingAgreementSharedTest } from "./shared.t.sol";

contract SubgraphServiceIndexingAgreementAcceptTest is SubgraphServiceIndexingAgreementSharedTest {
    /*
     * TESTS
     */

    /* solhint-disable graph/func-name-mixedcase */
    function test_SubgraphService_AcceptIndexingAgreement_Revert_WhenPaused(
        address allocationId,
        address operator,
        IRecurringCollector.SignedRCV calldata signedRCV
    ) public withSafeIndexerOrOperator(operator) {
        resetPrank(users.pauseGuardian);
        subgraphService.pause();

        resetPrank(operator);
        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        subgraphService.acceptIndexingAgreement(allocationId, signedRCV);
    }

    function test_SubgraphService_AcceptIndexingAgreement_Revert_WhenNotAuthorized(
        address allocationId,
        address operator,
        IRecurringCollector.SignedRCV calldata signedRCV
    ) public withSafeIndexerOrOperator(operator) {
        vm.assume(operator != signedRCV.rcv.serviceProvider);
        resetPrank(operator);
        bytes memory expectedErr = abi.encodeWithSelector(
            ProvisionManager.ProvisionManagerNotAuthorized.selector,
            signedRCV.rcv.serviceProvider,
            operator
        );
        vm.expectRevert(expectedErr);
        subgraphService.acceptIndexingAgreement(allocationId, signedRCV);
    }

    function test_SubgraphService_AcceptIndexingAgreement_Revert_WhenInvalidProvision(
        address indexer,
        uint256 unboundedTokens,
        address allocationId,
        IRecurringCollector.SignedRCV memory signedRCV
    ) public withSafeIndexerOrOperator(indexer) {
        uint256 tokens = bound(unboundedTokens, 1, minimumProvisionTokens - 1);
        mint(indexer, tokens);
        resetPrank(indexer);
        _createProvision(indexer, tokens, maxSlashingPercentage, disputePeriod);

        signedRCV.rcv.serviceProvider = indexer;
        bytes memory expectedErr = abi.encodeWithSelector(
            ProvisionManager.ProvisionManagerInvalidValue.selector,
            "tokens",
            tokens,
            minimumProvisionTokens,
            maximumProvisionTokens
        );
        vm.expectRevert(expectedErr);
        subgraphService.acceptIndexingAgreement(allocationId, signedRCV);
    }

    function test_SubgraphService_AcceptIndexingAgreement_Revert_WhenIndexerNotRegistered(
        address indexer,
        uint256 unboundedTokens,
        address allocationId,
        IRecurringCollector.SignedRCV memory signedRCV
    ) public withSafeIndexerOrOperator(indexer) {
        uint256 tokens = bound(unboundedTokens, minimumProvisionTokens, MAX_TOKENS);
        mint(indexer, tokens);
        resetPrank(indexer);
        _createProvision(indexer, tokens, maxSlashingPercentage, disputePeriod);
        signedRCV.rcv.serviceProvider = indexer;
        bytes memory expectedErr = abi.encodeWithSelector(
            ISubgraphService.SubgraphServiceIndexerNotRegistered.selector,
            indexer
        );
        vm.expectRevert(expectedErr);
        subgraphService.acceptIndexingAgreement(allocationId, signedRCV);
    }

    function test_SubgraphService_AcceptIndexingAgreement_Revert_WhenNotDataService(
        SetupTestIndexerParams calldata fuzzyParams,
        IRecurringCollector.SignedRCV memory signedRCV
    ) public {
        TestIndexerParams memory params = _setupTestIndexer(fuzzyParams);
        vm.assume(signedRCV.rcv.dataService != address(subgraphService));
        signedRCV.rcv.serviceProvider = params.indexer;
        bytes memory expectedErr = abi.encodeWithSelector(
            ISubgraphService.SubgraphServiceIndexingAgreementDataServiceMismatch.selector,
            signedRCV.rcv.dataService
        );
        vm.expectRevert(expectedErr);
        vm.prank(params.indexer);
        subgraphService.acceptIndexingAgreement(params.allocationId, signedRCV);
    }

    function test_SubgraphService_AcceptIndexingAgreement_Revert_WhenInvalidMetadata(
        SetupTestIndexerParams calldata fuzzyParams,
        IRecurringCollector.SignedRCV memory signedRCV
    ) public {
        TestIndexerParams memory params = _setupTestIndexer(fuzzyParams);
        signedRCV.rcv.serviceProvider = params.indexer;
        signedRCV.rcv.dataService = address(subgraphService);
        signedRCV.rcv.metadata = bytes("invalid");
        bytes memory expectedErr = abi.encodeWithSelector(
            ISubgraphService.SubgraphServiceInvalidRCVMetadata.selector,
            signedRCV.rcv.metadata
        );
        vm.expectRevert(expectedErr);
        vm.prank(params.indexer);
        subgraphService.acceptIndexingAgreement(params.allocationId, signedRCV);
    }

    function test_SubgraphService_AcceptIndexingAgreement_Revert_WhenInvalidAllocation(
        SetupTestIndexerParams calldata fuzzyParams,
        address invalidAllocationId,
        IRecurringCollector.SignedRCV memory signedRCV
    ) public {
        TestIndexerParams memory params = _setupTestIndexer(fuzzyParams);
        signedRCV.rcv.serviceProvider = params.indexer;
        signedRCV.rcv.dataService = address(subgraphService);
        signedRCV.rcv.metadata = abi.encode(_createAgreementMetadata(params.subgraphDeploymentId));

        bytes memory expectedErr = abi.encodeWithSelector(
            Allocation.AllocationDoesNotExist.selector,
            invalidAllocationId
        );
        vm.expectRevert(expectedErr);
        vm.prank(params.indexer);
        subgraphService.acceptIndexingAgreement(invalidAllocationId, signedRCV);
    }

    function test_SubgraphService_AcceptIndexingAgreement_Revert_WhenAllocationNotAuthorized(
        SetupTestIndexerParams calldata fuzzyParamsA,
        SetupTestIndexerParams calldata fuzzyParamsB,
        IRecurringCollector.SignedRCV memory signedRCV
    ) public {
        vm.assume(fuzzyParamsA.indexer != fuzzyParamsB.indexer);
        vm.assume(fuzzyParamsA.unboundedAllocationPrivateKey != fuzzyParamsB.unboundedAllocationPrivateKey);
        TestIndexerParams memory paramsA = _setupTestIndexer(fuzzyParamsA);
        TestIndexerParams memory paramsB = _setupTestIndexer(fuzzyParamsB);
        signedRCV.rcv.serviceProvider = paramsA.indexer;
        signedRCV.rcv.dataService = address(subgraphService);
        signedRCV.rcv.metadata = abi.encode(_createAgreementMetadata(paramsA.subgraphDeploymentId));

        bytes memory expectedErr = abi.encodeWithSelector(
            ISubgraphService.SubgraphServiceAllocationNotAuthorized.selector,
            paramsA.indexer,
            paramsB.allocationId
        );
        vm.expectRevert(expectedErr);
        vm.prank(paramsA.indexer);
        subgraphService.acceptIndexingAgreement(paramsB.allocationId, signedRCV);
    }

    function test_SubgraphService_AcceptIndexingAgreement_Revert_WhenAllocationClosed(
        SetupTestIndexerParams calldata fuzzyParams,
        IRecurringCollector.SignedRCV memory signedRCV
    ) public {
        TestIndexerParams memory params = _setupTestIndexer(fuzzyParams);
        signedRCV.rcv.serviceProvider = params.indexer;
        signedRCV.rcv.dataService = address(subgraphService);
        signedRCV.rcv.metadata = abi.encode(_createAgreementMetadata(params.subgraphDeploymentId));

        resetPrank(params.indexer);
        subgraphService.stopService(params.indexer, abi.encode(params.allocationId));
        bytes memory expectedErr = abi.encodeWithSelector(
            AllocationManager.AllocationManagerAllocationClosed.selector,
            params.allocationId
        );
        vm.expectRevert(expectedErr);
        subgraphService.acceptIndexingAgreement(params.allocationId, signedRCV);
    }

    function test_SubgraphService_AcceptIndexingAgreement_Revert_WhenDeploymentIdMismatch(
        SetupTestIndexerParams calldata fuzzyParams,
        bytes32 wrongSubgraphDeploymentId,
        IRecurringCollector.SignedRCV memory signedRCV
    ) public {
        vm.assume(fuzzyParams.subgraphDeploymentId != wrongSubgraphDeploymentId);
        TestIndexerParams memory params = _setupTestIndexer(fuzzyParams);
        signedRCV.rcv.serviceProvider = params.indexer;
        signedRCV.rcv.dataService = address(subgraphService);
        signedRCV.rcv.metadata = abi.encode(_createAgreementMetadata(wrongSubgraphDeploymentId));

        bytes memory expectedErr = abi.encodeWithSelector(
            ISubgraphService.SubgraphServiceIndexingAgreementDeploymentIdMismatch.selector,
            wrongSubgraphDeploymentId,
            params.allocationId,
            params.subgraphDeploymentId
        );
        vm.expectRevert(expectedErr);
        vm.prank(params.indexer);
        subgraphService.acceptIndexingAgreement(params.allocationId, signedRCV);
    }

    function test_SubgraphService_AcceptIndexingAgreement_Revert_WhenAgreementAlreadyAccepted(
        SetupTestIndexerParams calldata fuzzyParams,
        IRecurringCollector.SignedRCV memory signedRCV
    ) public {
        TestIndexerParams memory params = _setupTestIndexer(fuzzyParams);
        signedRCV.rcv.serviceProvider = params.indexer;
        signedRCV.rcv.dataService = address(subgraphService);
        signedRCV.rcv.metadata = abi.encode(_createAgreementMetadata(params.subgraphDeploymentId));

        _mockCollectorAccept(address(recurringCollector), signedRCV);

        resetPrank(params.indexer);
        subgraphService.acceptIndexingAgreement(params.allocationId, signedRCV);

        bytes memory expectedErr = abi.encodeWithSelector(
            ISubgraphService.SubgraphServiceIndexingAgreementAlreadyAccepted.selector,
            ISubgraphService.IndexingAgreementKey({
                indexer: signedRCV.rcv.serviceProvider,
                payer: signedRCV.rcv.payer,
                agreementId: signedRCV.rcv.agreementId
            })
        );
        vm.expectRevert(expectedErr);
        subgraphService.acceptIndexingAgreement(params.allocationId, signedRCV);
    }

    function test_SubgraphService_AcceptIndexingAgreement_Revert_WhenAgreementAlreadyAllocated() public {}

    function test_SubgraphService_AcceptIndexingAgreement(
        SetupTestIndexerParams calldata fuzzyParams,
        IRecurringCollector.SignedRCV memory signedRCV
    ) public {
        TestIndexerParams memory params = _setupTestIndexer(fuzzyParams);
        _acceptAgreement(params, signedRCV);
    }
    /* solhint-enable graph/func-name-mixedcase */
}
