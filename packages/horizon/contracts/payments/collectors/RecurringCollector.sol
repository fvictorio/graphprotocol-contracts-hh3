// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.27;

import { EIP712 } from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import { ECDSA } from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

import { Authorizable } from "../../utilities/Authorizable.sol";
import { GraphDirectory } from "../../utilities/GraphDirectory.sol";
import { IRecurringCollector } from "../../interfaces/IRecurringCollector.sol";
import { IGraphPayments } from "../../interfaces/IGraphPayments.sol";
import { PPMMath } from "../../libraries/PPMMath.sol";

/**
 * @title RecurringCollector contract
 * @dev Implements the {IRecurringCollector} interface.
 * @notice A payments collector contract that can be used to collect payments using a RCV (Recurrent Collection Voucher).
 * @custom:security-contact Please email security+contracts@thegraph.com if you find any
 * bugs. We may have an active bug bounty program.
 */
contract RecurringCollector is EIP712, GraphDirectory, Authorizable, IRecurringCollector {
    using PPMMath for uint256;

    /// @notice The EIP712 typehash for the RecurrentCollectionVoucher struct
    bytes32 private constant EIP712_RCV_TYPEHASH =
        keccak256("RecurrentCollectionVoucher(address dataService,address serviceProvider,bytes metadata)");

    /// @notice Sentinel value to indicate an agreement has been canceled
    uint256 private constant CANCELED = type(uint256).max;

    /// @notice Tracks agreements
    mapping(address dataService => mapping(address payer => mapping(address serviceProvider => mapping(bytes16 agreementId => AgreementData data))))
        public agreements;

    /**
     * @notice Checks that msg sender is the data service
     * @param dataService The address of the dataService
     */
    modifier onlyDataService(address dataService) {
        require(dataService == msg.sender, RecurringCollectorCallerNotDataService(msg.sender, dataService));
        _;
    }

    /**
     * @notice Constructs a new instance of the RecurringCollector contract.
     * @param eip712Name The name of the EIP712 domain.
     * @param eip712Version The version of the EIP712 domain.
     * @param controller The address of the Graph controller.
     * @param revokeSignerThawingPeriod The duration (in seconds) in which a signer is thawing before they can be revoked.
     */
    constructor(
        string memory eip712Name,
        string memory eip712Version,
        address controller,
        uint256 revokeSignerThawingPeriod
    ) EIP712(eip712Name, eip712Version) GraphDirectory(controller) Authorizable(revokeSignerThawingPeriod) {}

    /**
     * @notice Initiate a payment collection through the payments protocol.
     * See {IGraphPayments.collect}.
     * @dev Caller must be the data service the RCV was issued to.
     */
    function collect(IGraphPayments.PaymentTypes paymentType, bytes calldata data) external returns (uint256) {
        require(
            paymentType == IGraphPayments.PaymentTypes.IndexingFee,
            RecurringCollectorInvalidPaymentType(paymentType)
        );
        try this.decodeCollectData(data) returns (CollectParams memory params) {
            return _collect(params);
        } catch {
            revert RecurringCollectorInvalidCollectData(data);
        }
    }

    /**
     * @notice Accept an indexing agreement.
     * See {IRecurringCollector.accept}.
     * @dev Caller must be the data service the RCV was issued to.
     */
    function accept(SignedRCV memory signedRCV) external onlyDataService(signedRCV.rcv.dataService) {
        require(
            signedRCV.rcv.acceptDeadline >= block.timestamp,
            RecurringCollectorAgreementAcceptanceElapsed(signedRCV.rcv.acceptDeadline)
        );

        // check that the voucher is signed by the payer (or proxy)
        _requireAuthorizedRCVSigner(signedRCV);

        AgreementKey memory key = AgreementKey({
            dataService: signedRCV.rcv.dataService,
            payer: signedRCV.rcv.payer,
            serviceProvider: signedRCV.rcv.serviceProvider,
            agreementId: signedRCV.rcv.agreementId
        });
        AgreementData storage agreement = _getForUpdateAgreement(key);
        // check that the agreement is not already accepted
        require(agreement.acceptedAt == 0, RecurringCollectorAgreementAlreadyAccepted(key));

        // accept the agreement
        agreement.acceptedAt = block.timestamp;
        // FIX-ME: These need to be validated to something that makes sense for the contract
        agreement.duration = signedRCV.rcv.duration;
        agreement.maxInitialTokens = signedRCV.rcv.maxInitialTokens;
        agreement.maxOngoingTokensPerSecond = signedRCV.rcv.maxOngoingTokensPerSecond;
        agreement.minSecondsPerCollection = signedRCV.rcv.minSecondsPerCollection;
        agreement.maxSecondsPerCollection = signedRCV.rcv.maxSecondsPerCollection;
    }

    /**
     * @notice Cancel an indexing agreement.
     * See {IRecurringCollector.cancel}.
     * @dev Caller must be the data service for the agreement.
     */
    function cancel(address payer, address serviceProvider, bytes16 agreementId) external {
        AgreementKey memory key = AgreementKey({
            dataService: msg.sender,
            payer: payer,
            serviceProvider: serviceProvider,
            agreementId: agreementId
        });
        AgreementData storage agreement = _getForUpdateAgreement(key);
        require(agreement.acceptedAt > 0, RecurringCollectorAgreementNeverAccepted(key));
        agreement.acceptedAt = CANCELED;
    }

    /**
     * @notice See {IRecurringCollector.recoverRCVSigner}
     */
    function recoverRCVSigner(SignedRCV calldata signedRCV) external view returns (address) {
        return _recoverRCVSigner(signedRCV);
    }

    /**
     * @notice See {IRecurringCollector.encodeRCV}
     */
    function encodeRCV(RecurrentCollectionVoucher calldata rcv) external view returns (bytes32) {
        return _encodeRCV(rcv);
    }

    /**
     * @notice Decodes the collect data.
     */
    function decodeCollectData(bytes calldata data) public pure returns (CollectParams memory) {
        return abi.decode(data, (CollectParams));
    }

    /**
     * @notice Collect payment through the payments protocol.
     * @dev Caller must be the data service the RCV was issued to.
     *
     * Emits {PaymentCollected} and {RCVCollected} events.
     *
     * @param _params The decoded parameters for the collection
     * @return The amount of tokens collected
     */
    function _collect(CollectParams memory _params) private onlyDataService(_params.key.dataService) returns (uint256) {
        _requireValidCollect(_params.key, _params.tokens);

        _graphPaymentsEscrow().collect(
            IGraphPayments.PaymentTypes.IndexingFee,
            _params.key.payer,
            _params.key.serviceProvider,
            _params.tokens,
            _params.key.dataService,
            _params.dataServiceCut
        );

        emit PaymentCollected(
            IGraphPayments.PaymentTypes.IndexingFee,
            _params.collectionId,
            _params.key.payer,
            _params.key.serviceProvider,
            _params.key.dataService,
            _params.tokens
        );

        emit RCVCollected(
            _params.key.dataService,
            _params.key.payer,
            _params.key.serviceProvider,
            _params.collectionId,
            _params.tokens,
            _params.dataServiceCut
        );

        return _params.tokens;
    }

    /**
     * @notice Requires that the agreement is valid for collection.
     */
    function _requireValidCollect(AgreementKey memory _key, uint256 _tokens) private {
        AgreementData storage agreement = _getForUpdateAgreement(_key);
        uint256 lastCollectionAt = agreement.lastCollectionAt;
        agreement.lastCollectionAt = block.timestamp;

        require(
            agreement.acceptedAt > 0 && agreement.acceptedAt != CANCELED,
            RecurringCollectorAgreementInvalid(_key, agreement.acceptedAt)
        );

        uint256 agreementEnd = agreement.duration < type(uint256).max - agreement.acceptedAt
            ? agreement.acceptedAt + agreement.duration
            : type(uint256).max;
        require(agreementEnd >= block.timestamp, RecurringCollectorAgreementElapsed(_key, agreementEnd));

        uint256 collectionSeconds = block.timestamp;
        collectionSeconds -= lastCollectionAt > 0 ? lastCollectionAt : agreement.acceptedAt;
        require(
            collectionSeconds >= agreement.minSecondsPerCollection,
            RecurringCollectorCollectionTooSoon(_key, collectionSeconds, agreement.minSecondsPerCollection)
        );
        require(
            collectionSeconds <= agreement.maxSecondsPerCollection,
            RecurringCollectorCollectionTooLate(_key, collectionSeconds, agreement.maxSecondsPerCollection)
        );

        uint256 maxTokens = agreement.maxOngoingTokensPerSecond * collectionSeconds;
        maxTokens += lastCollectionAt == 0 ? agreement.maxInitialTokens : 0;

        require(_tokens <= maxTokens, RecurringCollectorCollectAmountTooHigh(_key, _tokens, maxTokens));
    }

    /**
     * @notice See {IRecurringCollector.recoverRCVSigner}
     */
    function _recoverRCVSigner(SignedRCV memory _signedRCV) private view returns (address) {
        bytes32 messageHash = _encodeRCV(_signedRCV.rcv);
        return ECDSA.recover(messageHash, _signedRCV.signature);
    }

    /**
     * @notice See {IRecurringCollector.encodeRCV}
     */
    function _encodeRCV(RecurrentCollectionVoucher memory _rcv) private view returns (bytes32) {
        return
            _hashTypedDataV4(
                keccak256(
                    abi.encode(EIP712_RCV_TYPEHASH, _rcv.dataService, _rcv.serviceProvider, keccak256(_rcv.metadata))
                )
            );
    }

    /**
     * @notice Requires that the signer for the RCV is authorized
     * by the payer of the RCV.
     */
    function _requireAuthorizedRCVSigner(SignedRCV memory _signedRCV) private view returns (address) {
        address signer = _recoverRCVSigner(_signedRCV);
        require(_isAuthorized(_signedRCV.rcv.payer, signer), RecurringCollectorInvalidRCVSigner());

        return signer;
    }

    /**
     * @notice Gets an agreement to be updated.
     */
    function _getForUpdateAgreement(AgreementKey memory _key) private view returns (AgreementData storage) {
        return agreements[_key.dataService][_key.payer][_key.serviceProvider][_key.agreementId];
    }
}
