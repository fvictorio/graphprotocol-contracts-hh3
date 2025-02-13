// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;
import { IAuthorizable } from "@graphprotocol/horizon/contracts/interfaces/IAuthorizable.sol";
import { IRecurringCollector } from "@graphprotocol/horizon/contracts/interfaces/IRecurringCollector.sol";

import { ISubgraphService } from "../../../contracts/interfaces/ISubgraphService.sol";

import { Bounder } from "@graphprotocol/horizon/test/utils/Bounder.t.sol";
import { SubgraphServiceTest } from "../SubgraphService.t.sol";

contract SubgraphServiceIndexingAgreementSharedTest is SubgraphServiceTest, Bounder {
    struct SetupTestIndexerParams {
        address indexer;
        uint256 unboundedTokens;
        uint256 unboundedAllocationPrivateKey;
        bytes32 subgraphDeploymentId;
    }

    struct TestIndexerParams {
        address indexer;
        address allocationId;
        bytes32 subgraphDeploymentId;
        uint256 tokens;
    }

    address internal constant TRANSPARENT_UPGRADEABLE_PROXY_ADMIN = 0xE1C5264f10fad5d1912e5Ba2446a26F5EfdB7482;

    mapping(address indexer => bool registered) internal _registeredIndexers;

    mapping(address allocationId => bool used) internal _allocationIds;

    modifier withSafeIndexerOrOperator(address operator) {
        vm.assume(_isSafeSubgraphServiceCaller(operator));
        _;
    }

    /*
     * HELPERS
     */

    function _resetPrank(address _addr) internal returns (address) {
        address originalPrankAddress = msg.sender;
        resetPrank(_addr);

        return originalPrankAddress;
    }

    function _stopOrResetPrank(address _originalSender) internal {
        if (_originalSender == 0x1804c8AB1F12E6bbf3894d4083f33e07309d1f38) {
            vm.stopPrank();
        } else {
            resetPrank(_originalSender);
        }
    }

    function _acceptAgreement(
        TestIndexerParams memory _params,
        IRecurringCollector.SignedRCV memory _signedRCV
    ) internal returns (IRecurringCollector.SignedRCV memory) {
        ISubgraphService.RCVMetadata memory metadata = _createAgreementMetadata(_params.subgraphDeploymentId);
        _signedRCV.rcv.serviceProvider = _params.indexer;
        _signedRCV.rcv.dataService = address(subgraphService);
        _signedRCV.rcv.metadata = abi.encode(metadata);

        _mockCollectorAccept(address(recurringCollector), _signedRCV);

        vm.expectEmit(address(subgraphService));
        emit ISubgraphService.IndexingAgreementAccepted(
            _signedRCV.rcv.serviceProvider,
            _signedRCV.rcv.payer,
            _signedRCV.rcv.agreementId,
            _params.allocationId,
            metadata.subgraphDeploymentId,
            metadata.tokensPerSecond,
            metadata.tokensPerEntityPerSecond
        );

        resetPrank(_params.indexer);
        subgraphService.acceptIndexingAgreement(_params.allocationId, _signedRCV);
        return _signedRCV;
    }

    function _cancelAgreementBy(address _indexer, address _payer, bytes16 _agreementId, bool _byIndexer) internal {
        vm.expectEmit(address(subgraphService));
        emit ISubgraphService.IndexingAgreementCanceled(_indexer, _payer, _agreementId, _byIndexer ? _indexer : _payer);
        _byIndexer
            ? _cancelAgreementByIndexer(_indexer, _payer, _agreementId)
            : _cancelAgreementByPayer(_indexer, _payer, _agreementId);
    }

    function _cancelAgreementByPayer(address _indexer, address _payer, bytes16 _agreementId) internal {
        _mockCollectorIsAuthorized(address(recurringCollector), _payer, _payer, true);

        _mockCollectorCancel(address(recurringCollector), _payer, _indexer, _agreementId);
        vm.assume(_isSafeSubgraphServiceCaller(_payer));
        resetPrank(_payer);
        subgraphService.cancelIndexingAgreementByPayer(_indexer, _payer, _agreementId);
    }

    function _cancelAgreementByIndexer(address _indexer, address _payer, bytes16 _agreementId) internal {
        _mockCollectorCancel(address(recurringCollector), _payer, _indexer, _agreementId);
        resetPrank(_indexer);
        subgraphService.cancelIndexingAgreement(_indexer, _payer, _agreementId);
    }

    function _setupTestIndexer(SetupTestIndexerParams calldata _params) internal returns (TestIndexerParams memory) {
        vm.assume(_isSafeSubgraphServiceCaller(_params.indexer) && !_registeredIndexers[_params.indexer]);
        _registeredIndexers[_params.indexer] = true;

        (uint256 allocationKey, address allocationId) = boundKeyAndAddr(_params.unboundedAllocationPrivateKey);
        vm.assume(!_allocationIds[allocationId]);
        _allocationIds[allocationId] = true;

        uint256 tokens = bound(_params.unboundedTokens, minimumProvisionTokens, MAX_TOKENS);
        mint(_params.indexer, tokens);

        address originalPrank = _resetPrank(_params.indexer);
        _createProvision(_params.indexer, tokens, maxSlashingPercentage, disputePeriod);
        _register(_params.indexer, abi.encode("url", "geoHash", address(0)));
        bytes memory data = _createSubgraphAllocationData(
            _params.indexer,
            _params.subgraphDeploymentId,
            allocationKey,
            tokens
        );
        _startService(_params.indexer, data);
        _stopOrResetPrank(originalPrank);

        return
            TestIndexerParams({
                indexer: _params.indexer,
                allocationId: allocationId,
                subgraphDeploymentId: _params.subgraphDeploymentId,
                tokens: tokens
            });
    }

    function _mockCollectorIsAuthorized(
        address _recurringCollector,
        address _payer,
        address _indexer,
        bool _result
    ) internal {
        vm.mockCall(
            address(_recurringCollector),
            abi.encodeWithSelector(IAuthorizable.isAuthorized.selector, _payer, _indexer),
            abi.encode(_result)
        );
        vm.expectCall(address(_recurringCollector), abi.encodeCall(IAuthorizable.isAuthorized, (_payer, _indexer)));
    }

    function _mockCollectorCancel(
        address _recurringCollector,
        address _payer,
        address _indexer,
        bytes16 _agreementId
    ) internal {
        vm.mockCall(
            _recurringCollector,
            abi.encodeWithSelector(IRecurringCollector.cancel.selector, _payer, _indexer, _agreementId),
            new bytes(0)
        );
        vm.expectCall(
            _recurringCollector,
            abi.encodeCall(IRecurringCollector.cancel, (_payer, _indexer, _agreementId))
        );
    }

    function _mockCollectorAccept(
        address _recurringCollector,
        IRecurringCollector.SignedRCV memory _signedRCV
    ) internal {
        vm.mockCall(
            _recurringCollector,
            abi.encodeWithSelector(IRecurringCollector.accept.selector, _signedRCV),
            new bytes(0)
        );
        vm.expectCall(address(recurringCollector), abi.encodeCall(IRecurringCollector.accept, (_signedRCV)));
    }

    function _isSafeSubgraphServiceCaller(address _candidate) internal view returns (bool) {
        return
            _candidate != address(0) &&
            _candidate != address(TRANSPARENT_UPGRADEABLE_PROXY_ADMIN) &&
            _candidate != address(proxyAdmin);
    }

    function _createAgreementMetadata(
        bytes32 _subgraphDeploymentId
    ) internal pure returns (ISubgraphService.RCVMetadata memory) {
        return
            ISubgraphService.RCVMetadata({
                tokensPerSecond: 0,
                tokensPerEntityPerSecond: 0,
                subgraphDeploymentId: _subgraphDeploymentId
            });
    }
}
