// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import { IRecurringCollector } from "../../../contracts/interfaces/IRecurringCollector.sol";

import { RecurringCollectorSharedTest } from "./shared.t.sol";

contract RecurringCollectorCancelTest is RecurringCollectorSharedTest {
    /*
     * TESTS
     */

    /* solhint-disable graph/func-name-mixedcase */

    function test_Cancel(FuzzyAcceptableRCA memory fuzzyAcceptableRCA) public {
        _fuzzyAuthorizeAndAccept(fuzzyAcceptableRCA);
        _cancel(fuzzyAcceptableRCA.rca);
    }

    function test_Cancel_Revert_WhenNotAccepted(
        IRecurringCollector.RecurringCollectionAgreement memory fuzzyRCA
    ) public {
        bytes memory expectedErr = abi.encodeWithSelector(
            IRecurringCollector.RecurringCollectorAgreementNeverAccepted.selector,
            fuzzyRCA.agreementId
        );
        vm.expectRevert(expectedErr);
        vm.prank(fuzzyRCA.dataService);
        _recurringCollector.cancel(fuzzyRCA.agreementId);
    }

    function test_Cancel_Revert_WhenNotDataService(
        FuzzyAcceptableRCA memory fuzzyAcceptableRCA,
        address notDataService
    ) public {
        vm.assume(fuzzyAcceptableRCA.rca.dataService != notDataService);

        _fuzzyAuthorizeAndAccept(fuzzyAcceptableRCA);

        bytes memory expectedErr = abi.encodeWithSelector(
            IRecurringCollector.RecurringCollectorDataServiceNotAuthorized.selector,
            fuzzyAcceptableRCA.rca.agreementId,
            notDataService
        );
        vm.expectRevert(expectedErr);
        vm.prank(notDataService);
        _recurringCollector.cancel(fuzzyAcceptableRCA.rca.agreementId);
    }
    /* solhint-enable graph/func-name-mixedcase */
}
