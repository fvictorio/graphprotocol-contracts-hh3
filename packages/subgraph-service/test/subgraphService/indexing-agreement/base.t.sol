// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import { TransparentUpgradeableProxy } from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import { SubgraphServiceIndexingAgreementSharedTest } from "./shared.t.sol";

contract SubgraphServiceIndexingAgreementBaseTest is SubgraphServiceIndexingAgreementSharedTest {
    /*
     * TESTS
     */

    /* solhint-disable graph/func-name-mixedcase */
    function test_SubgraphService_Revert_WhenUnsafeAddress_WhenProxyAdmin(
        address indexer,
        address payer,
        bytes16 agreementId
    ) public {
        address operator = TRANSPARENT_UPGRADEABLE_PROXY_ADMIN;
        assertFalse(_isSafeSubgraphServiceCaller(operator));

        vm.expectRevert(TransparentUpgradeableProxy.ProxyDeniedAdminAccess.selector);
        resetPrank(address(operator));
        subgraphService.cancelIndexingAgreement(indexer, payer, agreementId);
    }

    function test_SubgraphService_Revert_WhenUnsafeAddress_WhenGraphProxyAdmin(uint256 unboundedTokens) public {
        address indexer = 0x15c603B7eaA8eE1a272a69C4af3462F926de777F; // GraphProxyAdmin
        assertFalse(_isSafeSubgraphServiceCaller(indexer));

        uint256 tokens = bound(unboundedTokens, minimumProvisionTokens, MAX_TOKENS);
        mint(indexer, tokens);
        resetPrank(indexer);
        vm.expectRevert("Cannot fallback to proxy target");
        staking.provision(indexer, address(subgraphService), tokens, maxSlashingPercentage, disputePeriod);
    }

    /* solhint-enable graph/func-name-mixedcase */
}
