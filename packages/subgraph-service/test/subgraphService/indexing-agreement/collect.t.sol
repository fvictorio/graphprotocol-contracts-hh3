// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import { IGraphPayments } from "@graphprotocol/horizon/contracts/interfaces/IGraphPayments.sol";
import { IRecurringCollector } from "@graphprotocol/horizon/contracts/interfaces/IRecurringCollector.sol";
import { IPaymentsCollector } from "@graphprotocol/horizon/contracts/interfaces/IPaymentsCollector.sol";
import { PausableUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import { ProvisionManager } from "@graphprotocol/horizon/contracts/data-service/utilities/ProvisionManager.sol";

import { AllocationManager } from "../../../contracts/utilities/AllocationManager.sol";
import { ISubgraphService } from "../../../contracts/interfaces/ISubgraphService.sol";

import { SubgraphServiceIndexingAgreementSharedTest } from "./shared.t.sol";

contract SubgraphServiceIndexingAgreementCollectTest is SubgraphServiceIndexingAgreementSharedTest {
    /*
     * TESTS
     */

    /* solhint-disable graph/func-name-mixedcase */
    function test_SubgraphService_CollectIndexingFees(
        SetupTestIndexerParams calldata fuzzyParams,
        ISubgraphService.IndexingAgreementKey memory key,
        uint256 entities,
        bytes32 poi,
        IRecurringCollector.SignedRCV calldata fuzzySignedRCV,
        uint256 unboundedTokensCollected
    ) public {
        TestIndexerParams memory params = _setupTestIndexer(fuzzyParams);
        IRecurringCollector.SignedRCV memory signedRCV = _acceptAgreement(params, fuzzySignedRCV);
        key.indexer = params.indexer;
        key.payer = signedRCV.rcv.payer;
        key.agreementId = signedRCV.rcv.agreementId;

        resetPrank(params.indexer);
        bytes memory data = abi.encode(
            IRecurringCollector.CollectParams({
                key: IRecurringCollector.AgreementKey({
                    dataService: address(subgraphService),
                    payer: key.payer,
                    serviceProvider: key.indexer,
                    agreementId: key.agreementId
                }),
                collectionId: bytes32(uint256(uint160(params.allocationId))),
                tokens: 0,
                dataServiceCut: 0
            })
        );
        uint256 tokensCollected = bound(unboundedTokensCollected, 1, params.tokens / stakeToFeesRatio);
        vm.mockCall(
            address(recurringCollector),
            abi.encodeWithSelector(IPaymentsCollector.collect.selector, IGraphPayments.PaymentTypes.IndexingFee, data),
            abi.encode(tokensCollected)
        );
        vm.expectCall(
            address(recurringCollector),
            abi.encodeCall(IPaymentsCollector.collect, (IGraphPayments.PaymentTypes.IndexingFee, data))
        );
        vm.expectEmit(address(subgraphService));
        emit ISubgraphService.IndexingFeesCollected(
            key.indexer,
            key.payer,
            key.agreementId,
            params.allocationId,
            params.subgraphDeploymentId,
            epochManager.currentEpoch(),
            tokensCollected,
            entities,
            poi
        );
        subgraphService.collect(
            params.indexer,
            IGraphPayments.PaymentTypes.IndexingFee,
            abi.encode(key, entities, poi)
        );
    }

    function test_SubgraphService_CollectIndexingFees_LocksStake() public {
        // TODO: Test
    }

    function test_SubgraphService_CollectIndexingFees_Revert_WhenPaused(
        ISubgraphService.IndexingAgreementKey calldata key,
        uint256 entities,
        bytes32 poi
    ) public withSafeIndexerOrOperator(key.indexer) {
        resetPrank(users.pauseGuardian);
        subgraphService.pause();

        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        resetPrank(key.indexer);
        subgraphService.collect(key.indexer, IGraphPayments.PaymentTypes.IndexingFee, abi.encode(key, entities, poi));
    }

    function test_SubgraphService_CollectIndexingFees_Revert_WhenNotAuthorized(
        address operator,
        ISubgraphService.IndexingAgreementKey calldata key,
        uint256 entities,
        bytes32 poi
    ) public withSafeIndexerOrOperator(operator) {
        vm.assume(operator != key.indexer);
        resetPrank(operator);
        bytes memory expectedErr = abi.encodeWithSelector(
            ProvisionManager.ProvisionManagerNotAuthorized.selector,
            key.indexer,
            operator
        );
        vm.expectRevert(expectedErr);
        subgraphService.collect(key.indexer, IGraphPayments.PaymentTypes.IndexingFee, abi.encode(key, entities, poi));
    }

    function test_SubgraphService_CollectIndexingFees_Revert_WhenInvalidProvision(
        uint256 unboundedTokens,
        ISubgraphService.IndexingAgreementKey calldata key,
        uint256 entities,
        bytes32 poi
    ) public withSafeIndexerOrOperator(key.indexer) {
        uint256 tokens = bound(unboundedTokens, 1, minimumProvisionTokens - 1);
        mint(key.indexer, tokens);
        resetPrank(key.indexer);
        _createProvision(key.indexer, tokens, maxSlashingPercentage, disputePeriod);

        bytes memory expectedErr = abi.encodeWithSelector(
            ProvisionManager.ProvisionManagerInvalidValue.selector,
            "tokens",
            tokens,
            minimumProvisionTokens,
            maximumProvisionTokens
        );
        vm.expectRevert(expectedErr);
        subgraphService.collect(key.indexer, IGraphPayments.PaymentTypes.IndexingFee, abi.encode(key, entities, poi));
    }

    function test_SubgraphService_CollectIndexingFees_Revert_WhenIndexerNotRegistered(
        uint256 unboundedTokens,
        ISubgraphService.IndexingAgreementKey calldata key,
        uint256 entities,
        bytes32 poi
    ) public withSafeIndexerOrOperator(key.indexer) {
        uint256 tokens = bound(unboundedTokens, minimumProvisionTokens, MAX_TOKENS);
        mint(key.indexer, tokens);
        resetPrank(key.indexer);
        _createProvision(key.indexer, tokens, maxSlashingPercentage, disputePeriod);
        bytes memory expectedErr = abi.encodeWithSelector(
            ISubgraphService.SubgraphServiceIndexerNotRegistered.selector,
            key.indexer
        );
        vm.expectRevert(expectedErr);
        subgraphService.collect(key.indexer, IGraphPayments.PaymentTypes.IndexingFee, abi.encode(key, entities, poi));
    }

    function test_SubgraphService_CollectIndexingFees_Revert_WhenInvalidAgreement(
        SetupTestIndexerParams calldata fuzzyParams,
        ISubgraphService.IndexingAgreementKey memory key,
        uint256 entities,
        bytes32 poi
    ) public {
        TestIndexerParams memory params = _setupTestIndexer(fuzzyParams);
        key.indexer = params.indexer;

        bytes memory expectedErr = abi.encodeWithSelector(
            ISubgraphService.SubgraphServiceIndexingAgreementNotActive.selector,
            key
        );
        vm.expectRevert(expectedErr);
        resetPrank(params.indexer);
        subgraphService.collect(
            params.indexer,
            IGraphPayments.PaymentTypes.IndexingFee,
            abi.encode(key, entities, poi)
        );
    }

    function test_SubgraphService_CollectIndexingFees_Reverts_WhenAllocationClosed(
        SetupTestIndexerParams calldata fuzzyParams,
        ISubgraphService.IndexingAgreementKey memory key,
        uint256 entities,
        bytes32 poi,
        IRecurringCollector.SignedRCV calldata fuzzySignedRCV
    ) public {
        TestIndexerParams memory params = _setupTestIndexer(fuzzyParams);
        _acceptAgreement(params, fuzzySignedRCV);

        key.indexer = params.indexer;
        key.payer = fuzzySignedRCV.rcv.payer;
        key.agreementId = fuzzySignedRCV.rcv.agreementId;

        resetPrank(params.indexer);
        subgraphService.stopService(params.indexer, abi.encode(params.allocationId));

        bytes memory expectedErr = abi.encodeWithSelector(
            AllocationManager.AllocationManagerAllocationClosed.selector,
            params.allocationId
        );
        vm.expectRevert(expectedErr);
        subgraphService.collect(
            params.indexer,
            IGraphPayments.PaymentTypes.IndexingFee,
            abi.encode(key, entities, poi)
        );
    }
    /* solhint-enable graph/func-name-mixedcase */
}
