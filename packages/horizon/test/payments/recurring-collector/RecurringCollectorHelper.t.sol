// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import { IRecurringCollector } from "../../../contracts/interfaces/IRecurringCollector.sol";
import { RecurringCollector } from "../../../contracts/payments/collectors/RecurringCollector.sol";
import { AuthorizableHelper } from "../../utilities/Authorizable.t.sol";

contract RecurringCollectorHelper is AuthorizableHelper {
    RecurringCollector public collector;

    constructor(
        RecurringCollector collector_
    ) AuthorizableHelper(collector_, collector_.REVOKE_AUTHORIZATION_THAWING_PERIOD()) {
        collector = collector_;
    }

    function generateSignedRCV(
        IRecurringCollector.RecurrentCollectionVoucher memory rcv,
        uint256 signerPrivateKey
    ) public view returns (IRecurringCollector.SignedRCV memory) {
        bytes32 messageHash = collector.encodeRCV(rcv);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPrivateKey, messageHash);
        bytes memory signature = abi.encodePacked(r, s, v);
        IRecurringCollector.SignedRCV memory signedRCV = IRecurringCollector.SignedRCV({
            rcv: rcv,
            signature: signature
        });

        return signedRCV;
    }
}
