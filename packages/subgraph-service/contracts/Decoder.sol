// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.27;

import { ISubgraphService } from "./interfaces/ISubgraphService.sol";

contract Decoder {
    function decodeCollectIndexingFeeData(bytes calldata data) external pure returns (bytes16, bytes memory) {
        return abi.decode(data, (bytes16, bytes));
    }

    /**
     * @notice Decodes the indexing agreement metadata.
     *
     * @param data The data to decode. See {ISubgraphService.RCAIndexingAgreementMetadata}
     * @return The decoded data
     */
    function decodeRCAMetadata(
        bytes calldata data
    ) external pure returns (ISubgraphService.RCAIndexingAgreementMetadata memory) {
        return abi.decode(data, (ISubgraphService.RCAIndexingAgreementMetadata));
    }

    function decodeCollectIndexingFeeDataV1(bytes memory data) external pure returns (uint256 entities, bytes32 poi) {
        return abi.decode(data, (uint256, bytes32));
    }

    function decodeAcceptIndexingAgreementTermsV1(
        bytes memory data
    ) external pure returns (ISubgraphService.IndexingAgreementTermsV1 memory) {
        return abi.decode(data, (ISubgraphService.IndexingAgreementTermsV1));
    }

    function _decodeCollectIndexingFeeData(bytes memory _data) internal view returns (bytes16, bytes memory) {
        try this.decodeCollectIndexingFeeData(_data) returns (bytes16 agreementId, bytes memory data) {
            return (agreementId, data);
        } catch {
            revert ISubgraphService.SubgraphServiceDecoderInvalidData("_decodeCollectIndexingFeeData", _data);
        }
    }

    function _decodeRCAMetadata(
        bytes memory _data
    ) internal view returns (ISubgraphService.RCAIndexingAgreementMetadata memory) {
        try this.decodeRCAMetadata(_data) returns (ISubgraphService.RCAIndexingAgreementMetadata memory metadata) {
            return metadata;
        } catch {
            revert ISubgraphService.SubgraphServiceDecoderInvalidData("_decodeRCAMetadata", _data);
        }
    }

    function _decodeCollectIndexingFeeDataV1(bytes memory _data) internal view returns (uint256, bytes32) {
        try this.decodeCollectIndexingFeeDataV1(_data) returns (uint256 entities, bytes32 poi) {
            return (entities, poi);
        } catch {
            revert ISubgraphService.SubgraphServiceDecoderInvalidData("_decodeCollectIndexingFeeDataV1", _data);
        }
    }

    function _decodeAcceptIndexingAgreementTermsV1(
        bytes memory _data
    ) internal view returns (ISubgraphService.IndexingAgreementTermsV1 memory) {
        try this.decodeAcceptIndexingAgreementTermsV1(_data) returns (
            ISubgraphService.IndexingAgreementTermsV1 memory terms
        ) {
            return terms;
        } catch {
            revert ISubgraphService.SubgraphServiceDecoderInvalidData("_decodeCollectIndexingFeeData", _data);
        }
    }
}
