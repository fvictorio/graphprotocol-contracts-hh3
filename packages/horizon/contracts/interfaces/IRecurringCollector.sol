// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.27;

import { IPaymentsCollector } from "./IPaymentsCollector.sol";
import { IGraphPayments } from "./IGraphPayments.sol";
import { IAuthorizable } from "./IAuthorizable.sol";

/**
 * @title Interface for the {RecurringCollector} contract
 * @dev Implements the {IPaymentCollector} interface as defined by the Graph
 * Horizon payments protocol.
 * @notice Implements a payments collector contract that can be used to collect
 * recurrent payments.
 */
interface IRecurringCollector is IAuthorizable, IPaymentsCollector {
    /// @notice A representation of a signed Recurrent Collection Voucher (RCV)
    struct SignedRCV {
        // The RCV
        RecurrentCollectionVoucher rcv;
        // Signature - 65 bytes: r (32 Bytes) || s (32 Bytes) || v (1 Byte)
        bytes signature;
    }

    /// @notice The Recurrent Collection Voucher (RCV)
    struct RecurrentCollectionVoucher {
        // The agreement ID of the RCV
        bytes16 agreementId;
        // The deadline for accepting the RCV
        uint256 acceptDeadline;
        // The duration of the RCV in seconds
        uint256 duration;
        // The address of the payer the RCV was issued by
        address payer;
        // The address of the data service the RCV was issued to
        address dataService;
        // The address of the service provider the RCV was issued to
        address serviceProvider;
        // The maximum amount of tokens that can be collected in the first collection
        // on top of the amount allowed for subsequent collections
        uint256 maxInitialTokens;
        // The maximum amount of tokens that can be collected in a single collection
        // except for the first collection
        uint256 maxOngoingTokensPerSecond;
        // The minimum amount of seconds that must pass between collections
        uint32 minSecondsPerCollection;
        // The maximum amount of seconds that can pass between collections
        uint32 maxSecondsPerCollection;
        // Arbitrary metadata to extend functionality if a data service requires it
        bytes metadata;
    }

    /// @notice The data for an agreement
    struct AgreementData {
        // The timestamp when the agreement was accepted
        uint256 acceptedAt;
        // The timestamp when the agreement was last collected at
        uint256 lastCollectionAt;
        // The duration of the agreement in seconds
        uint256 duration;
        // The maximum amount of tokens that can be collected in the first collection
        // on top of the amount allowed for subsequent collections
        uint256 maxInitialTokens;
        // The maximum amount of tokens that can be collected in a single collection
        // except for the first collection
        uint256 maxOngoingTokensPerSecond;
        // The minimum amount of seconds that must pass between collections
        uint32 minSecondsPerCollection;
        // The maximum amount of seconds that can pass between collections
        uint32 maxSecondsPerCollection;
    }

    /// @notice The key for a stored agreement
    struct AgreementKey {
        // The address of the data service the agreement was issued to
        address dataService;
        // The address of the payer the agreement was issued by
        address payer;
        // The address of the service provider the agreement was issued to
        address serviceProvider;
        // The ID of the agreement
        bytes16 agreementId;
    }

    /// @notice The params for collecting an agreement
    struct CollectParams {
        // The agreement key that uniquely identifies it
        AgreementKey key;
        // The collection ID
        bytes32 collectionId;
        // The amount of tokens to collect
        uint256 tokens;
        // The data service cut in PPM
        uint256 dataServiceCut;
    }

    /**
     * @notice Emitted when an RCV is collected
     * @param dataService The address of the data service
     * @param payer The address of the payer
     * @param serviceProvider The address of the service provider
     */
    event RCVCollected(
        address indexed dataService,
        address indexed payer,
        address indexed serviceProvider,
        bytes32 collectionId,
        uint256 tokens,
        uint256 dataServiceCut
    );

    /**
     * Thrown when calling accept() for an agreement with an elapsed acceptance deadline
     * @param elapsedAt The timestamp when the acceptance deadline elapsed
     */
    error RecurringCollectorAgreementAcceptanceElapsed(uint256 elapsedAt);

    /**
     * Thrown when the RCV signer is invalid
     */
    error RecurringCollectorInvalidRCVSigner();

    /**
     * Thrown when the payment type is not IndexingFee
     * @param paymentType The provided payment type
     */
    error RecurringCollectorInvalidPaymentType(IGraphPayments.PaymentTypes paymentType);

    /**
     * Thrown when the caller is not the data service the RCV was issued to
     * @param caller The address of the caller
     * @param dataService The address of the data service
     */
    error RecurringCollectorCallerNotDataService(address caller, address dataService);

    /**
     * Thrown when calling collect() with invalid data
     * @param data The invalid data
     */
    error RecurringCollectorInvalidCollectData(bytes data);

    /**
     * Thrown when calling accept() for an already accepted agreement
     * @param key The agreement key
     */
    error RecurringCollectorAgreementAlreadyAccepted(AgreementKey key);

    /**
     * Thrown when calling cancel() for a never accepted agreement
     * @param key The agreement key
     */
    error RecurringCollectorAgreementNeverAccepted(AgreementKey key);

    /**
     * Thrown when calling collect() on an invalid agreement
     * @param key The agreement key
     * @param acceptedAt The agreement accepted timestamp
     */
    error RecurringCollectorAgreementInvalid(AgreementKey key, uint256 acceptedAt);

    /**
     * Thrown when calling collect() on an elapsed agreement
     * @param key The agreement key
     * @param agreementEnd The agreement end timestamp
     */
    error RecurringCollectorAgreementElapsed(AgreementKey key, uint256 agreementEnd);

    /**
     * Thrown when calling collect() too soon
     * @param key The agreement key
     * @param secondsSinceLast Seconds since last collection
     * @param minSeconds Minimum seconds between collections
     */
    error RecurringCollectorCollectionTooSoon(AgreementKey key, uint256 secondsSinceLast, uint256 minSeconds);

    /**
     * Thrown when calling collect() too late
     * @param key The agreement key
     * @param secondsSinceLast Seconds since last collection
     * @param maxSeconds Maximum seconds between collections
     */
    error RecurringCollectorCollectionTooLate(AgreementKey key, uint256 secondsSinceLast, uint256 maxSeconds);

    /**
     * Thrown when calling collect() too late
     * @param key The agreement key
     * @param tokens The amount of tokens to collect
     * @param maxTokens The maximum amount of tokens allowed to collect
     */
    error RecurringCollectorCollectAmountTooHigh(AgreementKey key, uint256 tokens, uint256 maxTokens);

    /**
     * @dev Accept an indexing agreement.
     * @param signedRCV The signed Recurrent Collection Voucher which is to be accepted.
     */
    function accept(SignedRCV memory signedRCV) external;

    /**
     * @dev Cancel an indexing agreement.
     * @param payer The address of the payer for the agreement.
     * @param serviceProvider The address of the serviceProvider for the agreement.
     * @param agreementId The agreement's ID.
     */
    function cancel(address payer, address serviceProvider, bytes16 agreementId) external;

    /**
     * @dev Computes the hash of a RecurrentCollectionVoucher (RCV).
     * @param rcv The RCV for which to compute the hash.
     * @return The hash of the RCV.
     */
    function encodeRCV(RecurrentCollectionVoucher calldata rcv) external view returns (bytes32);

    /**
     * @dev Recovers the signer address of a signed RecurrentCollectionVoucher (RCV).
     * @param signedRCV The SignedRCV containing the RCV and its signature.
     * @return The address of the signer.
     */
    function recoverRCVSigner(SignedRCV calldata signedRCV) external view returns (address);
}
