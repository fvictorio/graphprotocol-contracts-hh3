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

    function test_Accept(IRecurringCollector.RecurrentCollectionVoucher memory rcv, uint256 unboundedKey) public {
        _authorizeAndAccept(rcv, boundKey(unboundedKey));
    }

    function test_Accept_Revert_WhenAcceptanceDeadlineElapsed(
        IRecurringCollector.SignedRCV memory signedRCV,
        uint256 skip
    ) public {
        boundSkip(skip, 1, type(uint256).max);
        signedRCV.rcv.acceptDeadline = bound(signedRCV.rcv.acceptDeadline, 0, block.timestamp - 1);
        bytes memory expectedErr = abi.encodeWithSelector(
            IRecurringCollector.RecurringCollectorAgreementAcceptanceElapsed.selector,
            signedRCV.rcv.acceptDeadline
        );
        vm.expectRevert(expectedErr);
        vm.prank(signedRCV.rcv.dataService);
        _recurringCollector.accept(signedRCV);
    }

    function test_Accept_Revert_WhenAlreadyAccepted(
        IRecurringCollector.RecurrentCollectionVoucher memory rcv,
        uint256 unboundedKey
    ) public {
        uint256 key = boundKey(unboundedKey);
        IRecurringCollector.SignedRCV memory signedRCV = _authorizeAndAccept(rcv, key);

        bytes memory expectedErr = abi.encodeWithSelector(
            IRecurringCollector.RecurringCollectorAgreementAlreadyAccepted.selector,
            IRecurringCollector.AgreementKey({
                dataService: signedRCV.rcv.dataService,
                payer: signedRCV.rcv.payer,
                serviceProvider: signedRCV.rcv.serviceProvider,
                agreementId: signedRCV.rcv.agreementId
            })
        );
        vm.expectRevert(expectedErr);
        vm.prank(signedRCV.rcv.dataService);
        _recurringCollector.accept(signedRCV);
    }

    function test_Cancel(IRecurringCollector.RecurrentCollectionVoucher memory rcv, uint256 unboundedKey) public {
        _authorizeAndAccept(rcv, boundKey(unboundedKey));
        _cancel(rcv);
    }

    function test_Cancel_Revert_WhenNotAccepted(IRecurringCollector.RecurrentCollectionVoucher memory rcv) public {
        bytes memory expectedErr = abi.encodeWithSelector(
            IRecurringCollector.RecurringCollectorAgreementNeverAccepted.selector,
            IRecurringCollector.AgreementKey({
                dataService: rcv.dataService,
                payer: rcv.payer,
                serviceProvider: rcv.serviceProvider,
                agreementId: rcv.agreementId
            })
        );
        vm.expectRevert(expectedErr);
        vm.prank(rcv.dataService);
        _recurringCollector.cancel(rcv.payer, rcv.serviceProvider, rcv.agreementId);
    }

    function test_Cancel_Revert_WhenNotDataService(
        IRecurringCollector.RecurrentCollectionVoucher memory rcv,
        address notDataService,
        uint256 unboundedKey
    ) public {
        vm.assume(rcv.dataService != notDataService);

        _authorizeAndAccept(rcv, boundKey(unboundedKey));
        bytes memory expectedErr = abi.encodeWithSelector(
            IRecurringCollector.RecurringCollectorAgreementNeverAccepted.selector,
            IRecurringCollector.AgreementKey({
                dataService: notDataService,
                payer: rcv.payer,
                serviceProvider: rcv.serviceProvider,
                agreementId: rcv.agreementId
            })
        );
        vm.expectRevert(expectedErr);
        vm.prank(notDataService);
        _recurringCollector.cancel(rcv.payer, rcv.serviceProvider, rcv.agreementId);
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
        IRecurringCollector.CollectParams memory params,
        address notDataService
    ) public {
        vm.assume(params.key.dataService != notDataService);

        bytes memory data = _generateCollectData(params);

        bytes memory expectedErr = abi.encodeWithSelector(
            IRecurringCollector.RecurringCollectorCallerNotDataService.selector,
            notDataService,
            params.key.dataService
        );
        vm.expectRevert(expectedErr);
        vm.prank(notDataService);
        _recurringCollector.collect(IGraphPayments.PaymentTypes.IndexingFee, data);
    }

    function test_Collect_Revert_WhenUnknownAgreement(IRecurringCollector.CollectParams memory params) public {
        bytes memory data = _generateCollectData(params);

        bytes memory expectedErr = abi.encodeWithSelector(
            IRecurringCollector.RecurringCollectorAgreementInvalid.selector,
            params.key,
            0
        );
        vm.expectRevert(expectedErr);
        vm.prank(params.key.dataService);
        _recurringCollector.collect(IGraphPayments.PaymentTypes.IndexingFee, data);
    }

    function test_Collect_Revert_WhenCanceledAgreement(
        IRecurringCollector.RecurrentCollectionVoucher memory rcv,
        IRecurringCollector.CollectParams memory fuzzyParams,
        uint256 unboundedKey
    ) public {
        _authorizeAndAccept(rcv, boundKey(unboundedKey));
        _cancel(rcv);
        IRecurringCollector.CollectParams memory collectParams = _generateCollectParams(
            rcv,
            fuzzyParams.collectionId,
            fuzzyParams.tokens,
            fuzzyParams.dataServiceCut
        );
        bytes memory data = _generateCollectData(collectParams);

        bytes memory expectedErr = abi.encodeWithSelector(
            IRecurringCollector.RecurringCollectorAgreementInvalid.selector,
            collectParams.key,
            type(uint256).max
        );
        vm.expectRevert(expectedErr);
        vm.prank(rcv.dataService);
        _recurringCollector.collect(IGraphPayments.PaymentTypes.IndexingFee, data);
    }

    function test_Collect_Revert_WhenAgreementElapsed(
        IRecurringCollector.RecurrentCollectionVoucher memory rcv,
        IRecurringCollector.CollectParams memory fuzzyParams,
        uint256 unboundedKey,
        uint256 unboundedAcceptAt,
        uint256 unboundedCollectAt
    ) public {
        rcv = _sensibleRCV(rcv);
        // ensure agreement is short lived
        rcv.duration = bound(rcv.duration, 0, rcv.maxSecondsPerCollection * 100);
        // skip to sometime in the future when there is still plenty of time after the agreement elapsed
        skip(boundSkipCeil(unboundedAcceptAt, type(uint256).max - (rcv.duration * 10)));
        uint256 agreementEnd = block.timestamp + rcv.duration;
        _authorizeAndAccept(rcv, boundKey(unboundedKey));
        // skip to sometime after agreement elapsed
        skip(boundSkip(unboundedCollectAt, rcv.duration + 1, orTillEndOfTime(type(uint256).max)));

        IRecurringCollector.CollectParams memory collectParams = _generateCollectParams(
            rcv,
            fuzzyParams.collectionId,
            fuzzyParams.tokens,
            fuzzyParams.dataServiceCut
        );
        bytes memory data = _generateCollectData(collectParams);

        bytes memory expectedErr = abi.encodeWithSelector(
            IRecurringCollector.RecurringCollectorAgreementElapsed.selector,
            collectParams.key,
            agreementEnd
        );
        vm.expectRevert(expectedErr);
        vm.prank(rcv.dataService);
        _recurringCollector.collect(IGraphPayments.PaymentTypes.IndexingFee, data);
    }

    function test_Collect_Revert_WhenCollectingTooSoon(
        IRecurringCollector.RecurrentCollectionVoucher memory rcv,
        IRecurringCollector.CollectParams memory fuzzyParams,
        uint256 unboundedKey,
        uint256 unboundedAcceptAt,
        uint256 unboundedSkip
    ) public {
        rcv = _sensibleRCV(rcv);
        // skip to sometime in the future when there are still plenty of collections left
        skip(boundSkipCeil(unboundedAcceptAt, type(uint256).max - (rcv.maxSecondsPerCollection * 10)));
        _authorizeAndAccept(rcv, boundKey(unboundedKey));

        skip(rcv.minSecondsPerCollection);
        bytes memory data = _generateCollectData(
            _generateCollectParams(rcv, fuzzyParams.collectionId, 1, fuzzyParams.dataServiceCut)
        );
        vm.prank(rcv.dataService);
        _recurringCollector.collect(IGraphPayments.PaymentTypes.IndexingFee, data);

        uint256 collectionSeconds = boundSkipCeil(unboundedSkip, rcv.minSecondsPerCollection - 1);
        skip(collectionSeconds);
        IRecurringCollector.CollectParams memory collectParams = _generateCollectParams(
            rcv,
            fuzzyParams.collectionId,
            fuzzyParams.tokens,
            fuzzyParams.dataServiceCut
        );
        data = _generateCollectData(collectParams);
        bytes memory expectedErr = abi.encodeWithSelector(
            IRecurringCollector.RecurringCollectorCollectionTooSoon.selector,
            collectParams.key,
            collectionSeconds,
            rcv.minSecondsPerCollection
        );
        vm.expectRevert(expectedErr);
        vm.prank(rcv.dataService);
        _recurringCollector.collect(IGraphPayments.PaymentTypes.IndexingFee, data);
    }

    function test_Collect_Revert_WhenCollectingTooLate(
        IRecurringCollector.RecurrentCollectionVoucher memory rcv,
        IRecurringCollector.CollectParams memory fuzzyParams,
        uint256 unboundedKey,
        uint256 unboundedAcceptAt,
        uint256 unboundedFirstCollectionSkip,
        uint256 unboundedSkip
    ) public {
        rcv = _sensibleRCV(rcv);
        // skip to sometime in the future when there are still plenty of collections left
        skip(boundSkipCeil(unboundedAcceptAt, type(uint256).max - (rcv.maxSecondsPerCollection * 10)));
        uint256 acceptedAt = block.timestamp;
        _authorizeAndAccept(rcv, boundKey(unboundedKey));

        // skip to collectable time
        skip(boundSkip(unboundedFirstCollectionSkip, rcv.minSecondsPerCollection, rcv.maxSecondsPerCollection));
        bytes memory data = _generateCollectData(
            _generateCollectParams(rcv, fuzzyParams.collectionId, 1, fuzzyParams.dataServiceCut)
        );
        vm.prank(rcv.dataService);
        _recurringCollector.collect(IGraphPayments.PaymentTypes.IndexingFee, data);

        uint256 durationLeft = orTillEndOfTime(rcv.duration - (block.timestamp - acceptedAt));
        // skip beyond collectable time but still within the agreement duration
        uint256 collectionSeconds = boundSkip(unboundedSkip, rcv.maxSecondsPerCollection + 1, durationLeft);
        skip(collectionSeconds);

        IRecurringCollector.CollectParams memory collectParams = _generateCollectParams(
            rcv,
            fuzzyParams.collectionId,
            fuzzyParams.tokens,
            fuzzyParams.dataServiceCut
        );
        data = _generateCollectData(collectParams);
        bytes memory expectedErr = abi.encodeWithSelector(
            IRecurringCollector.RecurringCollectorCollectionTooLate.selector,
            collectParams.key,
            collectionSeconds,
            rcv.maxSecondsPerCollection
        );
        vm.expectRevert(expectedErr);
        vm.prank(rcv.dataService);
        _recurringCollector.collect(IGraphPayments.PaymentTypes.IndexingFee, data);
    }

    function test_Collect_Revert_WhenCollectingTooMuch(
        IRecurringCollector.RecurrentCollectionVoucher memory rcv,
        IRecurringCollector.CollectParams memory fuzzyParams,
        uint256 unboundedKey,
        uint256 unboundedInitialCollectionSkip,
        uint256 unboundedCollectionSkip,
        uint256 unboundedTokens,
        bool testInitialCollection
    ) public {
        rcv = _sensibleRCV(rcv);
        _authorizeAndAccept(rcv, boundKey(unboundedKey));

        if (!testInitialCollection) {
            // skip to collectable time
            skip(boundSkip(unboundedInitialCollectionSkip, rcv.minSecondsPerCollection, rcv.maxSecondsPerCollection));
            bytes memory initialData = _generateCollectData(
                _generateCollectParams(rcv, fuzzyParams.collectionId, 1, fuzzyParams.dataServiceCut)
            );
            vm.prank(rcv.dataService);
            _recurringCollector.collect(IGraphPayments.PaymentTypes.IndexingFee, initialData);
        }

        // skip to collectable time
        uint256 collectionSeconds = boundSkip(
            unboundedCollectionSkip,
            rcv.minSecondsPerCollection,
            rcv.maxSecondsPerCollection
        );
        skip(collectionSeconds);
        uint256 maxTokens = rcv.maxOngoingTokensPerSecond * collectionSeconds;
        maxTokens += testInitialCollection ? rcv.maxInitialTokens : 0;
        uint256 tokens = bound(unboundedTokens, maxTokens + 1, type(uint256).max);
        IRecurringCollector.CollectParams memory collectParams = _generateCollectParams(
            rcv,
            fuzzyParams.collectionId,
            tokens,
            fuzzyParams.dataServiceCut
        );
        bytes memory data = _generateCollectData(collectParams);
        bytes memory expectedErr = abi.encodeWithSelector(
            IRecurringCollector.RecurringCollectorCollectAmountTooHigh.selector,
            collectParams.key,
            tokens,
            maxTokens
        );
        vm.expectRevert(expectedErr);
        vm.prank(rcv.dataService);
        _recurringCollector.collect(IGraphPayments.PaymentTypes.IndexingFee, data);
    }

    function test_Collect_OK(
        IRecurringCollector.RecurrentCollectionVoucher memory rcv,
        IRecurringCollector.CollectParams memory fuzzyParams,
        uint256 unboundedKey,
        uint256 unboundedCollectionSkip,
        uint256 unboundedTokens
    ) public {
        rcv = _sensibleRCV(rcv);
        _authorizeAndAccept(rcv, boundKey(unboundedKey));

        (bytes memory data, uint256 collectionSeconds, uint256 tokens) = _generateValidCollection(
            rcv,
            fuzzyParams,
            unboundedCollectionSkip,
            unboundedTokens
        );
        skip(collectionSeconds);
        _expectCollectCallAndEmit(rcv, fuzzyParams, tokens);
        vm.prank(rcv.dataService);
        uint256 collected = _recurringCollector.collect(IGraphPayments.PaymentTypes.IndexingFee, data);
        assertEq(collected, tokens);
    }

    /* solhint-enable graph/func-name-mixedcase */

    function _authorizeAndAccept(
        IRecurringCollector.RecurrentCollectionVoucher memory _rcv,
        uint256 _signerKey
    ) private returns (IRecurringCollector.SignedRCV memory) {
        vm.assume(_rcv.payer != address(0));
        _recurringCollectorHelper.authorizeSignerWithChecks(_rcv.payer, _signerKey);
        _rcv.acceptDeadline = boundTimestampMin(_rcv.acceptDeadline, block.timestamp + 1);
        IRecurringCollector.SignedRCV memory signedRCV = _recurringCollectorHelper.generateSignedRCV(_rcv, _signerKey);

        vm.prank(_rcv.dataService);
        _recurringCollector.accept(signedRCV);

        return signedRCV;
    }

    function _cancel(IRecurringCollector.RecurrentCollectionVoucher memory _rcv) private {
        vm.prank(_rcv.dataService);
        _recurringCollector.cancel(_rcv.payer, _rcv.serviceProvider, _rcv.agreementId);
    }

    function _expectCollectCallAndEmit(
        IRecurringCollector.RecurrentCollectionVoucher memory _rcv,
        IRecurringCollector.CollectParams memory _fuzzyParams,
        uint256 _tokens
    ) private {
        vm.expectCall(
            address(_paymentsEscrow),
            abi.encodeCall(
                _paymentsEscrow.collect,
                (
                    IGraphPayments.PaymentTypes.IndexingFee,
                    _rcv.payer,
                    _rcv.serviceProvider,
                    _tokens,
                    _rcv.dataService,
                    _fuzzyParams.dataServiceCut
                )
            )
        );
        vm.expectEmit(address(_recurringCollector));
        emit IPaymentsCollector.PaymentCollected(
            IGraphPayments.PaymentTypes.IndexingFee,
            _fuzzyParams.collectionId,
            _rcv.payer,
            _rcv.serviceProvider,
            _rcv.dataService,
            _tokens
        );

        vm.expectEmit(address(_recurringCollector));
        emit IRecurringCollector.RCVCollected(
            _rcv.dataService,
            _rcv.payer,
            _rcv.serviceProvider,
            _fuzzyParams.collectionId,
            _tokens,
            _fuzzyParams.dataServiceCut
        );
    }

    function _generateValidCollection(
        IRecurringCollector.RecurrentCollectionVoucher memory _rcv,
        IRecurringCollector.CollectParams memory _fuzzyParams,
        uint256 _unboundedCollectionSkip,
        uint256 _unboundedTokens
    ) private view returns (bytes memory, uint256, uint256) {
        uint256 collectionSeconds = boundSkip(
            _unboundedCollectionSkip,
            _rcv.minSecondsPerCollection,
            _rcv.maxSecondsPerCollection
        );
        uint256 tokens = bound(_unboundedTokens, 1, _rcv.maxOngoingTokensPerSecond * collectionSeconds);
        bytes memory data = _generateCollectData(
            _generateCollectParams(_rcv, _fuzzyParams.collectionId, tokens, _fuzzyParams.dataServiceCut)
        );

        return (data, collectionSeconds, tokens);
    }

    function _sensibleRCV(
        IRecurringCollector.RecurrentCollectionVoucher memory _rcv
    ) private pure returns (IRecurringCollector.RecurrentCollectionVoucher memory) {
        _rcv.minSecondsPerCollection = uint32(bound(_rcv.minSecondsPerCollection, 60, 60 * 60 * 24));
        _rcv.maxSecondsPerCollection = uint32(
            bound(_rcv.maxSecondsPerCollection, _rcv.minSecondsPerCollection * 2, 60 * 60 * 24 * 30)
        );
        _rcv.duration = bound(_rcv.duration, _rcv.maxSecondsPerCollection * 10, type(uint256).max);
        _rcv.maxInitialTokens = bound(_rcv.maxInitialTokens, 0, 1e18 * 100_000_000);
        _rcv.maxOngoingTokensPerSecond = bound(_rcv.maxOngoingTokensPerSecond, 1, 1e18);

        return _rcv;
    }

    function _generateCollectParams(
        IRecurringCollector.RecurrentCollectionVoucher memory _rcv,
        bytes32 _collectionId,
        uint256 _tokens,
        uint256 _dataServiceCut
    ) private pure returns (IRecurringCollector.CollectParams memory) {
        return
            IRecurringCollector.CollectParams({
                key: IRecurringCollector.AgreementKey({
                    dataService: _rcv.dataService,
                    payer: _rcv.payer,
                    serviceProvider: _rcv.serviceProvider,
                    agreementId: _rcv.agreementId
                }),
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
