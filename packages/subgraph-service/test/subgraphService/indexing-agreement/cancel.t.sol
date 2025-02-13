// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import { IRecurringCollector } from "@graphprotocol/horizon/contracts/interfaces/IRecurringCollector.sol";
import { PausableUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import { ProvisionManager } from "@graphprotocol/horizon/contracts/data-service/utilities/ProvisionManager.sol";

import { ISubgraphService } from "../../../contracts/interfaces/ISubgraphService.sol";

import { SubgraphServiceIndexingAgreementSharedTest } from "./shared.t.sol";

contract SubgraphServiceIndexingAgreementCancelTest is SubgraphServiceIndexingAgreementSharedTest {
    /*
     * TESTS
     */

    /* solhint-disable graph/func-name-mixedcase */
    function test_SubgraphService_CancelIndexingAgreementByPayer_Revert_WhenPaused(
        address rando,
        address serviceProvider,
        address payer,
        bytes16 agreementId
    ) public withSafeIndexerOrOperator(rando) {
        resetPrank(users.pauseGuardian);
        subgraphService.pause();

        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        resetPrank(rando);
        subgraphService.cancelIndexingAgreementByPayer(serviceProvider, payer, agreementId);
    }

    function test_SubgraphService_CancelIndexingAgreementByPayer_Revert_WhenNotAuthorized(
        address rando,
        address serviceProvider,
        address payer,
        bytes16 agreementId
    ) public withSafeIndexerOrOperator(rando) {
        bytes memory expectedErr = abi.encodeWithSelector(
            ISubgraphService.SubgraphServiceIndexingAgreementNonCancelableBy.selector,
            payer,
            rando
        );
        vm.expectRevert(expectedErr);
        resetPrank(rando);
        subgraphService.cancelIndexingAgreementByPayer(serviceProvider, payer, agreementId);
    }

    function test_SubgraphService_CancelIndexingAgreementByPayer_Revert_WhenNotAccepted(
        SetupTestIndexerParams calldata fuzzyParams,
        address payer,
        bytes16 agreementId
    ) public {
        TestIndexerParams memory params = _setupTestIndexer(fuzzyParams);

        _mockCollectorIsAuthorized(address(recurringCollector), payer, params.indexer, true);

        resetPrank(params.indexer);
        bytes memory expectedErr = abi.encodeWithSelector(
            ISubgraphService.SubgraphServiceIndexingAgreementNotActive.selector,
            ISubgraphService.IndexingAgreementKey({ indexer: params.indexer, payer: payer, agreementId: agreementId })
        );
        vm.expectRevert(expectedErr);
        subgraphService.cancelIndexingAgreementByPayer(params.indexer, payer, agreementId);
    }

    function test_SubgraphService_CancelIndexingAgreementByPayer_Revert_WhenCanceled(
        SetupTestIndexerParams calldata fuzzyParams,
        IRecurringCollector.SignedRCV calldata fuzzySignedRCV,
        bool cancelSource
    ) public {
        TestIndexerParams memory params = _setupTestIndexer(fuzzyParams);
        IRecurringCollector.SignedRCV memory signedRCV = _acceptAgreement(params, fuzzySignedRCV);
        _cancelAgreementBy(params.indexer, signedRCV.rcv.payer, signedRCV.rcv.agreementId, cancelSource);

        _mockCollectorIsAuthorized(address(recurringCollector), signedRCV.rcv.payer, params.indexer, true);

        resetPrank(params.indexer);
        bytes memory expectedErr = abi.encodeWithSelector(
            ISubgraphService.SubgraphServiceIndexingAgreementNotActive.selector,
            ISubgraphService.IndexingAgreementKey({
                indexer: params.indexer,
                payer: signedRCV.rcv.payer,
                agreementId: signedRCV.rcv.agreementId
            })
        );
        vm.expectRevert(expectedErr);
        subgraphService.cancelIndexingAgreementByPayer(params.indexer, signedRCV.rcv.payer, signedRCV.rcv.agreementId);
    }

    function test_SubgraphService_CancelIndexingAgreementByPayer(
        SetupTestIndexerParams calldata fuzzyParams,
        IRecurringCollector.SignedRCV calldata fuzzySignedRCV
    ) public {
        TestIndexerParams memory params = _setupTestIndexer(fuzzyParams);
        IRecurringCollector.SignedRCV memory signedRCV = _acceptAgreement(params, fuzzySignedRCV);

        _cancelAgreementByPayer(params.indexer, signedRCV.rcv.payer, signedRCV.rcv.agreementId);
    }

    function test_SubgraphService_CancelIndexingAgreement_Revert_WhenPaused(
        address operator,
        address indexer,
        address payer,
        bytes16 agreementId
    ) public withSafeIndexerOrOperator(operator) {
        resetPrank(users.pauseGuardian);
        subgraphService.pause();

        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        resetPrank(operator);
        subgraphService.cancelIndexingAgreement(indexer, payer, agreementId);
    }

    function test_SubgraphService_CancelIndexingAgreement_Revert_WhenNotAuthorized(
        address operator,
        address indexer,
        address payer,
        bytes16 agreementId
    ) public withSafeIndexerOrOperator(operator) {
        vm.assume(operator != indexer);
        resetPrank(operator);
        bytes memory expectedErr = abi.encodeWithSelector(
            ProvisionManager.ProvisionManagerNotAuthorized.selector,
            indexer,
            operator
        );
        vm.expectRevert(expectedErr);
        subgraphService.cancelIndexingAgreement(indexer, payer, agreementId);
    }

    function test_SubgraphService_CancelIndexingAgreement_Revert_WhenInvalidProvision(
        address indexer,
        address payer,
        bytes16 agreementId,
        uint256 unboundedTokens
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
        subgraphService.cancelIndexingAgreement(indexer, payer, agreementId);
    }

    function test_SubgraphService_CancelIndexingAgreement_Revert_WhenIndexerNotRegistered(
        address indexer,
        address payer,
        bytes16 agreementId,
        uint256 unboundedTokens
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
        subgraphService.cancelIndexingAgreement(indexer, payer, agreementId);
    }

    function test_SubgraphService_CancelIndexingAgreement_Revert_WhenNotAccepted(
        SetupTestIndexerParams calldata fuzzyParams,
        address payer,
        bytes16 agreementId
    ) public {
        TestIndexerParams memory params = _setupTestIndexer(fuzzyParams);

        resetPrank(params.indexer);
        bytes memory expectedErr = abi.encodeWithSelector(
            ISubgraphService.SubgraphServiceIndexingAgreementNotActive.selector,
            ISubgraphService.IndexingAgreementKey({ indexer: params.indexer, payer: payer, agreementId: agreementId })
        );
        vm.expectRevert(expectedErr);
        subgraphService.cancelIndexingAgreement(params.indexer, payer, agreementId);
    }

    function test_SubgraphService_CancelIndexingAgreement_Revert_WhenCanceled(
        SetupTestIndexerParams calldata fuzzyParams,
        IRecurringCollector.SignedRCV calldata fuzzySignedRCV,
        bool cancelSource
    ) public {
        TestIndexerParams memory params = _setupTestIndexer(fuzzyParams);
        IRecurringCollector.SignedRCV memory signedRCV = _acceptAgreement(params, fuzzySignedRCV);
        _cancelAgreementBy(params.indexer, signedRCV.rcv.payer, signedRCV.rcv.agreementId, cancelSource);

        resetPrank(params.indexer);
        bytes memory expectedErr = abi.encodeWithSelector(
            ISubgraphService.SubgraphServiceIndexingAgreementNotActive.selector,
            ISubgraphService.IndexingAgreementKey({
                indexer: params.indexer,
                payer: signedRCV.rcv.payer,
                agreementId: signedRCV.rcv.agreementId
            })
        );
        vm.expectRevert(expectedErr);
        subgraphService.cancelIndexingAgreement(params.indexer, signedRCV.rcv.payer, signedRCV.rcv.agreementId);
    }

    function test_SubgraphService_CancelIndexingAgreement(
        SetupTestIndexerParams calldata fuzzyParams,
        IRecurringCollector.SignedRCV calldata fuzzySignedRCV
    ) public {
        TestIndexerParams memory params = _setupTestIndexer(fuzzyParams);
        IRecurringCollector.SignedRCV memory signedRCV = _acceptAgreement(params, fuzzySignedRCV);

        _cancelAgreementByIndexer(params.indexer, signedRCV.rcv.payer, signedRCV.rcv.agreementId);
    }
    /* solhint-enable graph/func-name-mixedcase */
}
