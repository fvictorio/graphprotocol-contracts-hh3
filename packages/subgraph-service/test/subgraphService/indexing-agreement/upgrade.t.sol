// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import { IRecurringCollector } from "@graphprotocol/horizon/contracts/interfaces/IRecurringCollector.sol";
import { PausableUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import { ProvisionManager } from "@graphprotocol/horizon/contracts/data-service/utilities/ProvisionManager.sol";

import { ISubgraphService } from "../../../contracts/interfaces/ISubgraphService.sol";

import { SubgraphServiceIndexingAgreementSharedTest } from "./shared.t.sol";

contract SubgraphServiceIndexingAgreementUpgradeTest is SubgraphServiceIndexingAgreementSharedTest {
    /*
     * TESTS
     */

    /* solhint-disable graph/func-name-mixedcase */
    // function test_SubgraphService_UpgradeIndexingAgreement(
    //     SetupTestIndexerParams calldata fuzzyParams,
    //     uint256 entities,
    //     bytes32 poi,
    //     IRecurringCollector.SignedRCA calldata fuzzySignedRCA,
    //     uint256 unboundedTokensCollected
    // ) public {
    //     TestIndexerParams memory params = _setupTestIndexer(fuzzyParams);
    //     IRecurringCollector.SignedRCA memory signedRCA = _acceptAgreement(params, fuzzySignedRCA);

    //     resetPrank(params.indexer);
    //     bytes memory data = abi.encode(
    //         IRecurringCollector.CollectParams({
    //             agreementId: signedRCA.rca.agreementId,
    //             collectionId: bytes32(uint256(uint160(params.allocationId))),
    //             tokens: 0,
    //             dataServiceCut: 0
    //         })
    //     );
    //     uint256 tokensCollected = bound(unboundedTokensCollected, 1, params.tokens / stakeToFeesRatio);
    //     vm.mockCall(
    //         address(recurringCollector),
    //         abi.encodeWithSelector(IPaymentsCollector.collect.selector, IGraphPayments.PaymentTypes.IndexingFee, data),
    //         abi.encode(tokensCollected)
    //     );
    //     vm.expectCall(
    //         address(recurringCollector),
    //         abi.encodeCall(IPaymentsCollector.collect, (IGraphPayments.PaymentTypes.IndexingFee, data))
    //     );
    //     vm.expectEmit(address(subgraphService));
    //     emit ISubgraphService.IndexingFeesCollectedV1(
    //         params.indexer,
    //         signedRCA.rca.payer,
    //         signedRCA.rca.agreementId,
    //         params.allocationId,
    //         params.subgraphDeploymentId,
    //         epochManager.currentEpoch(),
    //         tokensCollected,
    //         entities,
    //         poi
    //     );
    //     subgraphService.collect(
    //         params.indexer,
    //         IGraphPayments.PaymentTypes.IndexingFee,
    //         _encodeCollectDataV1(signedRCA.rca.agreementId, entities, poi)
    //     );
    // }

    function test_SubgraphService_UpgradeIndexingAgreement_Revert_WhenPaused(
        address operator,
        IRecurringCollector.SignedRCAU calldata signedRCAU
    ) public withSafeIndexerOrOperator(operator) {
        resetPrank(users.pauseGuardian);
        subgraphService.pause();

        resetPrank(operator);
        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        subgraphService.upgradeIndexingAgreement(operator, signedRCAU);
    }

    function test_SubgraphService_Upgrade_Revert_WhenNotAuthorized(
        address indexer,
        address notAuthorized,
        IRecurringCollector.SignedRCAU calldata signedRCAU
    ) public withSafeIndexerOrOperator(notAuthorized) {
        vm.assume(notAuthorized != indexer);
        resetPrank(notAuthorized);
        bytes memory expectedErr = abi.encodeWithSelector(
            ProvisionManager.ProvisionManagerNotAuthorized.selector,
            indexer,
            notAuthorized
        );
        vm.expectRevert(expectedErr);
        subgraphService.upgradeIndexingAgreement(indexer, signedRCAU);
    }

    function test_SubgraphService_Upgrade_Revert_WhenInvalidProvision(
        address indexer,
        uint256 unboundedTokens,
        IRecurringCollector.SignedRCAU memory signedRCAU
    ) public withSafeIndexerOrOperator(indexer) {
        uint256 tokens = bound(unboundedTokens, 1, minimumProvisionTokens - 1);
        mint(indexer, tokens);
        resetPrank(indexer);
        _createProvision(indexer, tokens, maxSlashingPercentage, disputePeriod);

        bytes memory expectedErr = abi.encodeWithSelector(
            ProvisionManager.ProvisionManagerInvalidValue.selector,
            "tokens",
            tokens,
            minimumProvisionTokens,
            maximumProvisionTokens
        );
        vm.expectRevert(expectedErr);
        subgraphService.upgradeIndexingAgreement(indexer, signedRCAU);
    }

    function test_SubgraphService_Upgrade_Revert_WhenIndexerNotRegistered(
        address indexer,
        uint256 unboundedTokens,
        IRecurringCollector.SignedRCAU memory signedRCAU
    ) public withSafeIndexerOrOperator(indexer) {
        uint256 tokens = bound(unboundedTokens, minimumProvisionTokens, MAX_TOKENS);
        mint(indexer, tokens);
        resetPrank(indexer);
        _createProvision(indexer, tokens, maxSlashingPercentage, disputePeriod);

        bytes memory expectedErr = abi.encodeWithSelector(
            ISubgraphService.SubgraphServiceIndexerNotRegistered.selector,
            indexer
        );
        vm.expectRevert(expectedErr);
        subgraphService.upgradeIndexingAgreement(indexer, signedRCAU);
    }

    function test_SubgraphService_Upgrade_Revert_WhenNotAccepted(
        SetupTestIndexerParams calldata fuzzyParams,
        IRecurringCollector.SignedRCAU memory signedRCAU
    ) public {
        TestIndexerParams memory params = _setupTestIndexer(fuzzyParams);

        bytes memory expectedErr = abi.encodeWithSelector(
            ISubgraphService.SubgraphServiceIndexingAgreementNotActive.selector,
            signedRCAU.rcau.agreementId
        );
        vm.expectRevert(expectedErr);
        resetPrank(params.indexer);
        subgraphService.upgradeIndexingAgreement(params.indexer, signedRCAU);
    }

    function test_SubgraphService_Upgrade_Revert_WhenInvalidMetadata(
        SetupTestIndexerParams calldata fuzzyParams,
        IRecurringCollector.SignedRCA memory fuzzySignedRCA,
        IRecurringCollector.SignedRCAU memory fuzzySignedRCAU
    ) public {
        TestIndexerParams memory params = _setupTestIndexer(fuzzyParams);
        IRecurringCollector.SignedRCA memory signedRCA = _acceptAgreement(params, fuzzySignedRCA);
        fuzzySignedRCAU.rcau.agreementId = signedRCA.rca.agreementId;
        fuzzySignedRCAU.rcau.metadata = bytes("invalid");

        bytes memory expectedErr = abi.encodeWithSelector(
            ISubgraphService.SubgraphServiceDecoderInvalidData.selector,
            "_decodeRCAUMetadata",
            fuzzySignedRCAU.rcau.metadata
        );
        vm.expectRevert(expectedErr);
        resetPrank(params.indexer);
        subgraphService.upgradeIndexingAgreement(params.indexer, fuzzySignedRCAU);
    }

    // function test_SubgraphService_Upgrade_Revert_WhenInvalidAgreement(
    //     SetupTestIndexerParams calldata fuzzyParams,
    //     bytes16 agreementId,
    //     uint256 entities,
    //     bytes32 poi
    // ) public {
    //     TestIndexerParams memory params = _setupTestIndexer(fuzzyParams);

    //     bytes memory expectedErr = abi.encodeWithSelector(
    //         ISubgraphService.SubgraphServiceIndexingAgreementNotActive.selector,
    //         agreementId
    //     );
    //     vm.expectRevert(expectedErr);
    //     resetPrank(params.indexer);
    //     subgraphService.collect(
    //         params.indexer,
    //         IGraphPayments.PaymentTypes.IndexingFee,
    //         _encodeCollectDataV1(agreementId, entities, poi)
    //     );
    // }

    // function test_SubgraphService_Upgrade_Reverts_WhenAllocationClosed(
    //     SetupTestIndexerParams calldata fuzzyParams,
    //     uint256 entities,
    //     bytes32 poi,
    //     IRecurringCollector.SignedRCA calldata fuzzySignedRCA
    // ) public {
    //     TestIndexerParams memory params = _setupTestIndexer(fuzzyParams);
    //     _acceptAgreement(params, fuzzySignedRCA);

    //     resetPrank(params.indexer);
    //     subgraphService.stopService(params.indexer, abi.encode(params.allocationId));

    //     bytes memory expectedErr = abi.encodeWithSelector(
    //         AllocationManager.AllocationManagerAllocationClosed.selector,
    //         params.allocationId
    //     );
    //     vm.expectRevert(expectedErr);
    //     subgraphService.collect(
    //         params.indexer,
    //         IGraphPayments.PaymentTypes.IndexingFee,
    //         _encodeCollectDataV1(fuzzySignedRCA.rca.agreementId, entities, poi)
    //     );
    // }
    /* solhint-enable graph/func-name-mixedcase */
}
