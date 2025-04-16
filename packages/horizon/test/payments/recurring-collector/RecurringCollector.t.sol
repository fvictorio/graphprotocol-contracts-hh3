// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import { Test } from "forge-std/Test.sol";

import { IGraphPayments } from "../../../contracts/interfaces/IGraphPayments.sol";
import { IPaymentsCollector } from "../../../contracts/interfaces/IPaymentsCollector.sol";
import { IRecurringCollector } from "../../../contracts/interfaces/IRecurringCollector.sol";
import { RecurringCollector } from "../../../contracts/payments/collectors/RecurringCollector.sol";

import { Bounder } from "../../utils/Bounder.t.sol";
import { RecurringCollectorControllerMock } from "./RecurringCollectorControllerMock.t.sol";
import { PaymentsEscrowMock } from "./PaymentsEscrowMock.t.sol";
import { RecurringCollectorHelper } from "./RecurringCollectorHelper.t.sol";

contract RecurringCollectorTest is Test, Bounder {
    struct TestCollectParams {
        IRecurringCollector.CollectParams collectData;
        address dataService;
    }

    RecurringCollector private _recurringCollector;
    PaymentsEscrowMock private _paymentsEscrow;
    RecurringCollectorHelper private _recurringCollectorHelper;

    function setUp() public {
        _paymentsEscrow = new PaymentsEscrowMock();
        _recurringCollector = new RecurringCollector(
            "RecurringCollector",
            "1",
            address(new RecurringCollectorControllerMock(address(_paymentsEscrow))),
            1
        );
        _recurringCollectorHelper = new RecurringCollectorHelper(_recurringCollector);
    }

    /*
     * TESTS
     */

    /* solhint-disable graph/func-name-mixedcase */

    function test_Accept(IRecurringCollector.RecurringCollectionAgreement memory rca, uint256 unboundedKey) public {
        _authorizeAndAccept(rca, boundKey(unboundedKey));
    }

    function test_Accept_Revert_WhenAcceptanceDeadlineElapsed(
        IRecurringCollector.SignedRCA memory signedRCA,
        uint256 skip
    ) public {
        boundSkip(skip, 1, type(uint256).max);
        signedRCA.rca.acceptDeadline = bound(signedRCA.rca.acceptDeadline, 0, block.timestamp - 1);
        bytes memory expectedErr = abi.encodeWithSelector(
            IRecurringCollector.RecurringCollectorAgreementAcceptanceElapsed.selector,
            signedRCA.rca.acceptDeadline
        );
        vm.expectRevert(expectedErr);
        vm.prank(signedRCA.rca.dataService);
        _recurringCollector.accept(signedRCA);
    }

    function test_Accept_Revert_WhenAlreadyAccepted(
        IRecurringCollector.RecurringCollectionAgreement memory rca,
        uint256 unboundedKey
    ) public {
        uint256 key = boundKey(unboundedKey);
        IRecurringCollector.SignedRCA memory signedRCA = _authorizeAndAccept(rca, key);

        bytes memory expectedErr = abi.encodeWithSelector(
            IRecurringCollector.RecurringCollectorAgreementAlreadyAccepted.selector,
            signedRCA.rca.agreementId
        );
        vm.expectRevert(expectedErr);
        vm.prank(signedRCA.rca.dataService);
        _recurringCollector.accept(signedRCA);
    }

    function test_Cancel(IRecurringCollector.RecurringCollectionAgreement memory rca, uint256 unboundedKey) public {
        _authorizeAndAccept(rca, boundKey(unboundedKey));
        _cancel(rca);
    }

    function test_Cancel_Revert_WhenNotAccepted(IRecurringCollector.RecurringCollectionAgreement memory rca) public {
        bytes memory expectedErr = abi.encodeWithSelector(
            IRecurringCollector.RecurringCollectorAgreementNeverAccepted.selector,
            rca.agreementId
        );
        vm.expectRevert(expectedErr);
        vm.prank(rca.dataService);
        _recurringCollector.cancel(rca.agreementId);
    }

    function test_Cancel_Revert_WhenNotDataService(
        IRecurringCollector.RecurringCollectionAgreement memory rca,
        address notDataService,
        uint256 unboundedKey
    ) public {
        vm.assume(rca.dataService != notDataService);

        _authorizeAndAccept(rca, boundKey(unboundedKey));
        bytes memory expectedErr = abi.encodeWithSelector(
            IRecurringCollector.RecurringCollectorDataServiceNotAuthorized.selector,
            rca.agreementId,
            notDataService
        );
        vm.expectRevert(expectedErr);
        vm.prank(notDataService);
        _recurringCollector.cancel(rca.agreementId);
    }

    function test_Collect_Revert_WhenInvalidPaymentType(uint8 unboundedPaymentType, bytes memory data) public {
        uint256 lastPaymentType = uint256(IGraphPayments.PaymentTypes.IndexingRewards);

        IGraphPayments.PaymentTypes paymentType = IGraphPayments.PaymentTypes(
            bound(unboundedPaymentType, 0, lastPaymentType)
        );
        vm.assume(paymentType != IGraphPayments.PaymentTypes.IndexingFee);

        bytes memory expectedErr = abi.encodeWithSelector(
            IRecurringCollector.RecurringCollectorInvalidPaymentType.selector,
            paymentType
        );
        vm.expectRevert(expectedErr);
        _recurringCollector.collect(paymentType, data);

        // If I move this to the top of the function, the rest of the test does not run. Not sure why...
        {
            vm.expectRevert();
            IGraphPayments.PaymentTypes(lastPaymentType + 1);
        }
    }

    function test_Collect_Revert_WhenInvalidData(address caller, bytes memory data) public {
        bytes memory expectedErr = abi.encodeWithSelector(
            IRecurringCollector.RecurringCollectorInvalidCollectData.selector,
            data
        );
        vm.expectRevert(expectedErr);
        vm.prank(caller);
        _recurringCollector.collect(IGraphPayments.PaymentTypes.IndexingFee, data);
    }

    function test_Collect_Revert_WhenCallerNotDataService(
        IRecurringCollector.RecurringCollectionAgreement memory rca,
        IRecurringCollector.CollectParams memory params,
        uint256 unboundedKey,
        address notDataService
    ) public {
        vm.assume(rca.dataService != notDataService);
        params.agreementId = rca.agreementId;
        bytes memory data = _generateCollectData(params);

        _authorizeAndAccept(rca, boundKey(unboundedKey));
        bytes memory expectedErr = abi.encodeWithSelector(
            IRecurringCollector.RecurringCollectorDataServiceNotAuthorized.selector,
            params.agreementId,
            notDataService
        );
        vm.expectRevert(expectedErr);
        vm.prank(notDataService);
        _recurringCollector.collect(IGraphPayments.PaymentTypes.IndexingFee, data);
    }

    function test_Collect_Revert_WhenUnknownAgreement(TestCollectParams memory params) public {
        bytes memory data = _generateCollectData(params.collectData);

        bytes memory expectedErr = abi.encodeWithSelector(
            IRecurringCollector.RecurringCollectorAgreementInvalid.selector,
            params.collectData.agreementId,
            0
        );
        vm.expectRevert(expectedErr);
        vm.prank(params.dataService);
        _recurringCollector.collect(IGraphPayments.PaymentTypes.IndexingFee, data);
    }

    function test_Collect_Revert_WhenCanceledAgreement(
        IRecurringCollector.RecurringCollectionAgreement memory rca,
        TestCollectParams memory testCollectParams,
        uint256 unboundedKey
    ) public {
        IRecurringCollector.CollectParams memory fuzzyParams = testCollectParams.collectData;
        _authorizeAndAccept(rca, boundKey(unboundedKey));
        _cancel(rca);
        IRecurringCollector.CollectParams memory collectParams = _generateCollectParams(
            rca,
            fuzzyParams.collectionId,
            fuzzyParams.tokens,
            fuzzyParams.dataServiceCut
        );
        bytes memory data = _generateCollectData(collectParams);

        bytes memory expectedErr = abi.encodeWithSelector(
            IRecurringCollector.RecurringCollectorAgreementInvalid.selector,
            collectParams.agreementId,
            type(uint256).max
        );
        vm.expectRevert(expectedErr);
        vm.prank(rca.dataService);
        _recurringCollector.collect(IGraphPayments.PaymentTypes.IndexingFee, data);
    }

    function test_Collect_Revert_WhenAgreementElapsed(
        IRecurringCollector.RecurringCollectionAgreement memory rca,
        IRecurringCollector.CollectParams memory fuzzyParams,
        uint256 unboundedKey,
        uint256 unboundedAcceptAt,
        uint256 unboundedCollectAt
    ) public {
        rca = _sensibleRCA(rca);
        // ensure agreement is short lived
        rca.duration = bound(rca.duration, 0, rca.maxSecondsPerCollection * 100);
        // skip to sometime in the future when there is still plenty of time after the agreement elapsed
        skip(boundSkipCeil(unboundedAcceptAt, type(uint256).max - (rca.duration * 10)));
        uint256 agreementEnd = block.timestamp + rca.duration;
        _authorizeAndAccept(rca, boundKey(unboundedKey));
        // skip to sometime after agreement elapsed
        skip(boundSkip(unboundedCollectAt, rca.duration + 1, orTillEndOfTime(type(uint256).max)));

        IRecurringCollector.CollectParams memory collectParams = _generateCollectParams(
            rca,
            fuzzyParams.collectionId,
            fuzzyParams.tokens,
            fuzzyParams.dataServiceCut
        );
        bytes memory data = _generateCollectData(collectParams);

        bytes memory expectedErr = abi.encodeWithSelector(
            IRecurringCollector.RecurringCollectorAgreementElapsed.selector,
            collectParams.agreementId,
            agreementEnd
        );
        vm.expectRevert(expectedErr);
        vm.prank(rca.dataService);
        _recurringCollector.collect(IGraphPayments.PaymentTypes.IndexingFee, data);
    }

    function test_Collect_Revert_WhenCollectingTooSoon(
        IRecurringCollector.RecurringCollectionAgreement memory rca,
        IRecurringCollector.CollectParams memory fuzzyParams,
        uint256 unboundedKey,
        uint256 unboundedAcceptAt,
        uint256 unboundedSkip
    ) public {
        rca = _sensibleRCA(rca);
        // skip to sometime in the future when there are still plenty of collections left
        skip(boundSkipCeil(unboundedAcceptAt, type(uint256).max - (rca.maxSecondsPerCollection * 10)));
        _authorizeAndAccept(rca, boundKey(unboundedKey));

        skip(rca.minSecondsPerCollection);
        bytes memory data = _generateCollectData(
            _generateCollectParams(rca, fuzzyParams.collectionId, 1, fuzzyParams.dataServiceCut)
        );
        vm.prank(rca.dataService);
        _recurringCollector.collect(IGraphPayments.PaymentTypes.IndexingFee, data);

        uint256 collectionSeconds = boundSkipCeil(unboundedSkip, rca.minSecondsPerCollection - 1);
        skip(collectionSeconds);
        IRecurringCollector.CollectParams memory collectParams = _generateCollectParams(
            rca,
            fuzzyParams.collectionId,
            fuzzyParams.tokens,
            fuzzyParams.dataServiceCut
        );
        data = _generateCollectData(collectParams);
        bytes memory expectedErr = abi.encodeWithSelector(
            IRecurringCollector.RecurringCollectorCollectionTooSoon.selector,
            collectParams.agreementId,
            collectionSeconds,
            rca.minSecondsPerCollection
        );
        vm.expectRevert(expectedErr);
        vm.prank(rca.dataService);
        _recurringCollector.collect(IGraphPayments.PaymentTypes.IndexingFee, data);
    }

    function test_Collect_Revert_WhenCollectingTooLate(
        IRecurringCollector.RecurringCollectionAgreement memory rca,
        IRecurringCollector.CollectParams memory fuzzyParams,
        uint256 unboundedKey,
        uint256 unboundedAcceptAt,
        uint256 unboundedFirstCollectionSkip,
        uint256 unboundedSkip
    ) public {
        rca = _sensibleRCA(rca);
        // skip to sometime in the future when there are still plenty of collections left
        skip(boundSkipCeil(unboundedAcceptAt, type(uint256).max - (rca.maxSecondsPerCollection * 10)));
        uint256 acceptedAt = block.timestamp;
        _authorizeAndAccept(rca, boundKey(unboundedKey));

        // skip to collectable time
        skip(boundSkip(unboundedFirstCollectionSkip, rca.minSecondsPerCollection, rca.maxSecondsPerCollection));
        bytes memory data = _generateCollectData(
            _generateCollectParams(rca, fuzzyParams.collectionId, 1, fuzzyParams.dataServiceCut)
        );
        vm.prank(rca.dataService);
        _recurringCollector.collect(IGraphPayments.PaymentTypes.IndexingFee, data);

        uint256 durationLeft = orTillEndOfTime(rca.duration - (block.timestamp - acceptedAt));
        // skip beyond collectable time but still within the agreement duration
        uint256 collectionSeconds = boundSkip(unboundedSkip, rca.maxSecondsPerCollection + 1, durationLeft);
        skip(collectionSeconds);

        IRecurringCollector.CollectParams memory collectParams = _generateCollectParams(
            rca,
            fuzzyParams.collectionId,
            fuzzyParams.tokens,
            fuzzyParams.dataServiceCut
        );
        data = _generateCollectData(collectParams);
        bytes memory expectedErr = abi.encodeWithSelector(
            IRecurringCollector.RecurringCollectorCollectionTooLate.selector,
            collectParams.agreementId,
            collectionSeconds,
            rca.maxSecondsPerCollection
        );
        vm.expectRevert(expectedErr);
        vm.prank(rca.dataService);
        _recurringCollector.collect(IGraphPayments.PaymentTypes.IndexingFee, data);
    }

    function test_Collect_Revert_WhenCollectingTooMuch(
        IRecurringCollector.RecurringCollectionAgreement memory rca,
        IRecurringCollector.CollectParams memory fuzzyParams,
        uint256 unboundedKey,
        uint256 unboundedInitialCollectionSkip,
        uint256 unboundedCollectionSkip,
        uint256 unboundedTokens,
        bool testInitialCollection
    ) public {
        rca = _sensibleRCA(rca);
        _authorizeAndAccept(rca, boundKey(unboundedKey));

        if (!testInitialCollection) {
            // skip to collectable time
            skip(boundSkip(unboundedInitialCollectionSkip, rca.minSecondsPerCollection, rca.maxSecondsPerCollection));
            bytes memory initialData = _generateCollectData(
                _generateCollectParams(rca, fuzzyParams.collectionId, 1, fuzzyParams.dataServiceCut)
            );
            vm.prank(rca.dataService);
            _recurringCollector.collect(IGraphPayments.PaymentTypes.IndexingFee, initialData);
        }

        // skip to collectable time
        uint256 collectionSeconds = boundSkip(
            unboundedCollectionSkip,
            rca.minSecondsPerCollection,
            rca.maxSecondsPerCollection
        );
        skip(collectionSeconds);
        uint256 maxTokens = rca.maxOngoingTokensPerSecond * collectionSeconds;
        maxTokens += testInitialCollection ? rca.maxInitialTokens : 0;
        uint256 tokens = bound(unboundedTokens, maxTokens + 1, type(uint256).max);
        IRecurringCollector.CollectParams memory collectParams = _generateCollectParams(
            rca,
            fuzzyParams.collectionId,
            tokens,
            fuzzyParams.dataServiceCut
        );
        bytes memory data = _generateCollectData(collectParams);
        bytes memory expectedErr = abi.encodeWithSelector(
            IRecurringCollector.RecurringCollectorCollectAmountTooHigh.selector,
            collectParams.agreementId,
            tokens,
            maxTokens
        );
        vm.expectRevert(expectedErr);
        vm.prank(rca.dataService);
        _recurringCollector.collect(IGraphPayments.PaymentTypes.IndexingFee, data);
    }

    function test_Collect_OK(
        IRecurringCollector.RecurringCollectionAgreement memory rca,
        IRecurringCollector.CollectParams memory fuzzyParams,
        uint256 unboundedKey,
        uint256 unboundedCollectionSkip,
        uint256 unboundedTokens
    ) public {
        rca = _sensibleRCA(rca);
        _authorizeAndAccept(rca, boundKey(unboundedKey));

        (bytes memory data, uint256 collectionSeconds, uint256 tokens) = _generateValidCollection(
            rca,
            fuzzyParams,
            unboundedCollectionSkip,
            unboundedTokens
        );
        skip(collectionSeconds);
        _expectCollectCallAndEmit(rca, fuzzyParams, tokens);
        vm.prank(rca.dataService);
        uint256 collected = _recurringCollector.collect(IGraphPayments.PaymentTypes.IndexingFee, data);
        assertEq(collected, tokens);
    }

    function test_Upgrade_Revert_WhenUpgradeElapsed(
        IRecurringCollector.RecurringCollectionAgreement memory rca,
        uint256 unboundedUpgradeSkip
    ) public {
        rca = _sensibleRCA(rca);
        IRecurringCollector.RecurringCollectionAgreementUpgrade memory rcau = _sensibleRCAU(rca);

        boundSkipCeil(unboundedUpgradeSkip, type(uint256).max);
        rcau.upgradeDeadline = bound(rcau.upgradeDeadline, 0, block.timestamp - 1);
        IRecurringCollector.SignedRCAU memory signedRCAU = IRecurringCollector.SignedRCAU({
            rcau: rcau,
            signature: ""
        });

        bytes memory expectedErr = abi.encodeWithSelector(
            IRecurringCollector.RecurringCollectorAgreementUpgradeElapsed.selector,
            rcau.upgradeDeadline
        );
        vm.expectRevert(expectedErr);
        vm.prank(rca.dataService);
        _recurringCollector.upgrade(signedRCAU);
    }

    function test_Upgrade_Revert_WhenNeverAccepted(IRecurringCollector.RecurringCollectionAgreement memory rca) public {
        rca = _sensibleRCA(rca);
        IRecurringCollector.RecurringCollectionAgreementUpgrade memory rcau = _sensibleRCAU(rca);

        rcau.upgradeDeadline = block.timestamp;
        IRecurringCollector.SignedRCAU memory signedRCAU = IRecurringCollector.SignedRCAU({
            rcau: rcau,
            signature: ""
        });

        bytes memory expectedErr = abi.encodeWithSelector(
            IRecurringCollector.RecurringCollectorAgreementNeverAccepted.selector,
            rcau.agreementId
        );
        vm.expectRevert(expectedErr);
        vm.prank(rca.dataService);
        _recurringCollector.upgrade(signedRCAU);
    }

    function test_Upgrade_Revert_WhenDataServiceNotAuthorized(
        IRecurringCollector.RecurringCollectionAgreement memory rca,
        uint256 unboundedKey,
        uint256 unboundedUpgradeSkip,
        address notDataService
    ) public {
        vm.assume(rca.dataService != notDataService);
        rca = _sensibleRCA(rca);
        IRecurringCollector.RecurringCollectionAgreementUpgrade memory rcau = _sensibleRCAU(rca);
        uint256 signerKey = boundKey(unboundedKey);
        _authorizeAndAccept(rca, signerKey);

        boundSkipCeil(unboundedUpgradeSkip, type(uint256).max);
        rcau.upgradeDeadline = boundTimestampMin(rcau.upgradeDeadline, block.timestamp + 1);
        IRecurringCollector.SignedRCAU memory signedRCAU = _recurringCollectorHelper.generateSignedRCAU(
            rcau,
            signerKey
        );

        bytes memory expectedErr = abi.encodeWithSelector(
            IRecurringCollector.RecurringCollectorDataServiceNotAuthorized.selector,
            rcau.agreementId,
            notDataService
        );
        vm.expectRevert(expectedErr);
        vm.prank(notDataService);
        _recurringCollector.upgrade(signedRCAU);
    }

    function test_Upgrade_Revert_WhenInvalidSigner(
        IRecurringCollector.RecurringCollectionAgreement memory rca,
        uint256 unboundedKey,
        uint256 unboundedUpgradeSkip,
        uint256 unboundedInvalidSignerKey
    ) public {
        uint256 signerKey = boundKey(unboundedKey);
        uint256 invalidSignerKey = boundKey(unboundedInvalidSignerKey);
        vm.assume(signerKey != invalidSignerKey);

        rca = _sensibleRCA(rca);
        IRecurringCollector.RecurringCollectionAgreementUpgrade memory rcau = _sensibleRCAU(rca);
        _authorizeAndAccept(rca, signerKey);

        boundSkipCeil(unboundedUpgradeSkip, type(uint256).max);
        rcau.upgradeDeadline = boundTimestampMin(rcau.upgradeDeadline, block.timestamp + 1);

        IRecurringCollector.SignedRCAU memory signedRCAU = _recurringCollectorHelper.generateSignedRCAU(
            rcau,
            invalidSignerKey
        );

        vm.expectRevert(IRecurringCollector.RecurringCollectorInvalidSigner.selector);
        vm.prank(rca.dataService);
        _recurringCollector.upgrade(signedRCAU);
    }

    function test_Upgrade_OK(
        IRecurringCollector.RecurringCollectionAgreement memory rca,
        uint256 unboundedKey,
        uint256 unboundedUpgradeSkip
    ) public {
        rca = _sensibleRCA(rca);
        IRecurringCollector.RecurringCollectionAgreementUpgrade memory rcau = _sensibleRCAU(rca);
        uint256 signerKey = boundKey(unboundedKey);
        _authorizeAndAccept(rca, signerKey);

        boundSkipCeil(unboundedUpgradeSkip, type(uint256).max);
        rcau.upgradeDeadline = boundTimestampMin(rcau.upgradeDeadline, block.timestamp + 1);
        IRecurringCollector.SignedRCAU memory signedRCAU = _recurringCollectorHelper.generateSignedRCAU(
            rcau,
            signerKey
        );

        vm.prank(rca.dataService);
        _recurringCollector.upgrade(signedRCAU);

        IRecurringCollector.AgreementData memory agreement = _recurringCollector.getAgreement(rca.agreementId);
        assertEq(rcau.duration, agreement.duration);
        assertEq(rcau.maxInitialTokens, agreement.maxInitialTokens);
        assertEq(rcau.maxOngoingTokensPerSecond, agreement.maxOngoingTokensPerSecond);
        assertEq(rcau.minSecondsPerCollection, agreement.minSecondsPerCollection);
        assertEq(rcau.maxSecondsPerCollection, agreement.maxSecondsPerCollection);
    }

    /* solhint-enable graph/func-name-mixedcase */

    function _authorizeAndAccept(
        IRecurringCollector.RecurringCollectionAgreement memory _rca,
        uint256 _signerKey
    ) private returns (IRecurringCollector.SignedRCA memory) {
        vm.assume(_rca.payer != address(0));
        _recurringCollectorHelper.authorizeSignerWithChecks(_rca.payer, _signerKey);
        _rca.acceptDeadline = boundTimestampMin(_rca.acceptDeadline, block.timestamp + 1);
        IRecurringCollector.SignedRCA memory signedRCA = _recurringCollectorHelper.generateSignedRCA(_rca, _signerKey);

        vm.prank(_rca.dataService);
        _recurringCollector.accept(signedRCA);

        return signedRCA;
    }

    function _cancel(IRecurringCollector.RecurringCollectionAgreement memory _rca) private {
        vm.prank(_rca.dataService);
        _recurringCollector.cancel(_rca.agreementId);
    }

    function _expectCollectCallAndEmit(
        IRecurringCollector.RecurringCollectionAgreement memory _rca,
        IRecurringCollector.CollectParams memory _fuzzyParams,
        uint256 _tokens
    ) private {
        vm.expectCall(
            address(_paymentsEscrow),
            abi.encodeCall(
                _paymentsEscrow.collect,
                (
                    IGraphPayments.PaymentTypes.IndexingFee,
                    _rca.payer,
                    _rca.serviceProvider,
                    _tokens,
                    _rca.dataService,
                    _fuzzyParams.dataServiceCut
                )
            )
        );
        vm.expectEmit(address(_recurringCollector));
        emit IPaymentsCollector.PaymentCollected(
            IGraphPayments.PaymentTypes.IndexingFee,
            _fuzzyParams.collectionId,
            _rca.payer,
            _rca.serviceProvider,
            _rca.dataService,
            _tokens
        );

        vm.expectEmit(address(_recurringCollector));
        emit IRecurringCollector.RCACollected(
            _rca.dataService,
            _rca.payer,
            _rca.serviceProvider,
            _fuzzyParams.collectionId,
            _tokens,
            _fuzzyParams.dataServiceCut
        );
    }

    function _generateValidCollection(
        IRecurringCollector.RecurringCollectionAgreement memory _rca,
        IRecurringCollector.CollectParams memory _fuzzyParams,
        uint256 _unboundedCollectionSkip,
        uint256 _unboundedTokens
    ) private view returns (bytes memory, uint256, uint256) {
        uint256 collectionSeconds = boundSkip(
            _unboundedCollectionSkip,
            _rca.minSecondsPerCollection,
            _rca.maxSecondsPerCollection
        );
        uint256 tokens = bound(_unboundedTokens, 1, _rca.maxOngoingTokensPerSecond * collectionSeconds);
        bytes memory data = _generateCollectData(
            _generateCollectParams(_rca, _fuzzyParams.collectionId, tokens, _fuzzyParams.dataServiceCut)
        );

        return (data, collectionSeconds, tokens);
    }

    function _sensibleRCA(
        IRecurringCollector.RecurringCollectionAgreement memory _rca
    ) private pure returns (IRecurringCollector.RecurringCollectionAgreement memory) {
        _rca.minSecondsPerCollection = uint32(bound(_rca.minSecondsPerCollection, 60, 60 * 60 * 24));
        _rca.maxSecondsPerCollection = uint32(
            bound(_rca.maxSecondsPerCollection, _rca.minSecondsPerCollection * 2, 60 * 60 * 24 * 30)
        );
        _rca.duration = bound(_rca.duration, _rca.maxSecondsPerCollection * 10, type(uint256).max);
        _rca.maxInitialTokens = bound(_rca.maxInitialTokens, 0, 1e18 * 100_000_000);
        _rca.maxOngoingTokensPerSecond = bound(_rca.maxOngoingTokensPerSecond, 1, 1e18);

        return _rca;
    }

    function _sensibleRCAU(
        IRecurringCollector.RecurringCollectionAgreement memory _rca
    ) private pure returns (IRecurringCollector.RecurringCollectionAgreementUpgrade memory) {
        IRecurringCollector.RecurringCollectionAgreementUpgrade memory rcau;
        rcau.agreementId = _rca.agreementId;
        rcau.minSecondsPerCollection = uint32(bound(_rca.minSecondsPerCollection, 60, 60 * 60 * 24));
        rcau.maxSecondsPerCollection = uint32(
            bound(_rca.maxSecondsPerCollection, rcau.minSecondsPerCollection * 2, 60 * 60 * 24 * 30)
        );
        rcau.duration = bound(_rca.duration, rcau.maxSecondsPerCollection * 10, type(uint256).max);
        rcau.maxInitialTokens = bound(_rca.maxInitialTokens, 0, 1e18 * 100_000_000);
        rcau.maxOngoingTokensPerSecond = bound(_rca.maxOngoingTokensPerSecond, 1, 1e18);

        return rcau;
    }

    function _generateCollectParams(
        IRecurringCollector.RecurringCollectionAgreement memory _rca,
        bytes32 _collectionId,
        uint256 _tokens,
        uint256 _dataServiceCut
    ) private pure returns (IRecurringCollector.CollectParams memory) {
        return
            IRecurringCollector.CollectParams({
                agreementId: _rca.agreementId,
                collectionId: _collectionId,
                tokens: _tokens,
                dataServiceCut: _dataServiceCut
            });
    }

    function _generateCollectData(
        IRecurringCollector.CollectParams memory _params
    ) private pure returns (bytes memory) {
        return abi.encode(_params);
    }
}
