import { expect } from 'chai'
import { ethers, ContractTransaction, BigNumber } from 'ethers'
import { defaultAbiCoder, parseEther } from 'ethers/lib/utils'

import {
  getAccounts,
  randomHexBytes,
  Account,
  toGRT,
  getL2SignerFromL1,
  setAccountBalance,
  latestBlock,
} from '../lib/testHelpers'
import { L2FixtureContracts, NetworkFixture } from '../lib/fixtures'
import { toBN } from '../lib/testHelpers'

import { L2GNS } from '../../build/types/L2GNS'
import { L2GraphTokenGateway } from '../../build/types/L2GraphTokenGateway'
import {
  buildSubgraph,
  buildSubgraphID,
  burnSignal,
  DEFAULT_RESERVE_RATIO,
  deprecateSubgraph,
  mintSignal,
  publishNewSubgraph,
  publishNewVersion,
  PublishSubgraph,
  Subgraph,
} from '../lib/gnsUtils'
import { L2Curation } from '../../build/types/L2Curation'
import { GraphToken } from '../../build/types/GraphToken'

const { HashZero } = ethers.constants

interface L1SubgraphParams {
  l1SubgraphId: string
  curatedTokens: BigNumber
  subgraphMetadata: string
  versionMetadata: string
}

describe('L2GNS', () => {
  let me: Account
  let other: Account
  let governor: Account
  let mockRouter: Account
  let mockL1GRT: Account
  let mockL1Gateway: Account
  let mockL1GNS: Account
  let mockL1Staking: Account
  let fixture: NetworkFixture

  let fixtureContracts: L2FixtureContracts
  let l2GraphTokenGateway: L2GraphTokenGateway
  let gns: L2GNS
  let curation: L2Curation
  let grt: GraphToken

  let newSubgraph0: PublishSubgraph
  let newSubgraph1: PublishSubgraph

  const tokens1000 = toGRT('1000')
  const tokens10000 = toGRT('10000')
  const tokens100000 = toGRT('100000')
  const curationTaxPercentage = 50000

  const gatewayFinalizeTransfer = async function (
    from: string,
    to: string,
    amount: BigNumber,
    callhookData: string,
  ): Promise<ContractTransaction> {
    const mockL1GatewayL2Alias = await getL2SignerFromL1(mockL1Gateway.address)
    // Eth for gas:
    await setAccountBalance(await mockL1GatewayL2Alias.getAddress(), parseEther('1'))

    const tx = l2GraphTokenGateway
      .connect(mockL1GatewayL2Alias)
      .finalizeInboundTransfer(mockL1GRT.address, from, to, amount, callhookData)
    return tx
  }

  const defaultL1SubgraphParams = async function (): Promise<L1SubgraphParams> {
    return {
      l1SubgraphId: await buildSubgraphID(me.address, toBN('1'), 1),
      curatedTokens: toGRT('1337'),
      subgraphMetadata: randomHexBytes(),
      versionMetadata: randomHexBytes(),
    }
  }
  const transferMockSubgraphFromL1 = async function (
    l1SubgraphId: string,
    curatedTokens: BigNumber,
    subgraphMetadata: string,
    versionMetadata: string,
  ) {
    const callhookData = defaultAbiCoder.encode(
      ['uint8', 'uint256', 'address'],
      [toBN(0), l1SubgraphId, me.address],
    )
    await gatewayFinalizeTransfer(mockL1GNS.address, gns.address, curatedTokens, callhookData)

    const l2SubgraphId = await gns.getAliasedL2SubgraphID(l1SubgraphId)
    await gns
      .connect(me.signer)
      .finishSubgraphTransferFromL1(
        l2SubgraphId,
        newSubgraph0.subgraphDeploymentID,
        subgraphMetadata,
        versionMetadata,
      )
  }

  before(async function () {
    newSubgraph0 = buildSubgraph()
    ;[me, other, governor, mockRouter, mockL1GRT, mockL1Gateway, mockL1GNS, mockL1Staking] =
      await getAccounts()

    fixture = new NetworkFixture()
    fixtureContracts = await fixture.loadL2(governor.signer)
    ;({ l2GraphTokenGateway, gns, curation, grt } = fixtureContracts)

    await grt.connect(governor.signer).mint(me.address, toGRT('10000'))
    await fixture.configureL2Bridge(
      governor.signer,
      fixtureContracts,
      mockRouter.address,
      mockL1GRT.address,
      mockL1Gateway.address,
      mockL1GNS.address,
      mockL1Staking.address,
    )
  })

  beforeEach(async function () {
    await fixture.setUp()
  })

  afterEach(async function () {
    await fixture.tearDown()
  })

  // Adapted from the L1 GNS tests but allowing curating to a pre-curated subgraph deployment
  describe('publishNewVersion', async function () {
    let subgraph: Subgraph

    beforeEach(async () => {
      newSubgraph0 = buildSubgraph()
      newSubgraph1 = buildSubgraph()
      // Give some funds to the signers and approve gns contract to use funds on signers behalf
      await grt.connect(governor.signer).mint(me.address, tokens100000)
      await grt.connect(governor.signer).mint(other.address, tokens100000)
      await grt.connect(me.signer).approve(gns.address, tokens100000)
      await grt.connect(me.signer).approve(curation.address, tokens100000)
      await grt.connect(other.signer).approve(gns.address, tokens100000)
      await grt.connect(other.signer).approve(curation.address, tokens100000)
      // Update curation tax to test the functionality of it in disableNameSignal()
      await curation.connect(governor.signer).setCurationTaxPercentage(curationTaxPercentage)
      subgraph = await publishNewSubgraph(me, newSubgraph0, gns)
      await mintSignal(me, subgraph.id, tokens10000, gns, curation)
    })

    it('should publish a new version on an existing subgraph', async function () {
      await publishNewVersion(me, subgraph.id, newSubgraph1, gns, curation)
    })

    it('should publish a new version on an existing subgraph with no current signal', async function () {
      const emptySignalSubgraph = await publishNewSubgraph(me, buildSubgraph(), gns)
      await publishNewVersion(me, emptySignalSubgraph.id, newSubgraph1, gns, curation)
    })

    it('should reject a new version with the same subgraph deployment ID', async function () {
      const tx = gns
        .connect(me.signer)
        .publishNewVersion(
          subgraph.id,
          newSubgraph0.subgraphDeploymentID,
          newSubgraph0.versionMetadata,
        )
      await expect(tx).revertedWith(
        'GNS: Cannot publish a new version with the same subgraph deployment ID',
      )
    })

    it('should reject publishing a version to a subgraph that does not exist', async function () {
      const tx = gns
        .connect(me.signer)
        .publishNewVersion(
          randomHexBytes(32),
          newSubgraph1.subgraphDeploymentID,
          newSubgraph1.versionMetadata,
        )
      await expect(tx).revertedWith('ERC721: owner query for nonexistent token')
    })

    it('reject if not the owner', async function () {
      const tx = gns
        .connect(other.signer)
        .publishNewVersion(
          subgraph.id,
          newSubgraph1.subgraphDeploymentID,
          newSubgraph1.versionMetadata,
        )
      await expect(tx).revertedWith('GNS: Must be authorized')
    })

    it('should NOT fail when upgrade tries to point to a pre-curated', async function () {
      // Curate directly to the deployment
      await curation.connect(me.signer).mint(newSubgraph1.subgraphDeploymentID, tokens1000, 0)

      await publishNewVersion(me, subgraph.id, newSubgraph1, gns, curation)
    })

    it('should upgrade version when there is no signal with no signal migration', async function () {
      await burnSignal(me, subgraph.id, gns, curation)
      const tx = gns
        .connect(me.signer)
        .publishNewVersion(
          subgraph.id,
          newSubgraph1.subgraphDeploymentID,
          newSubgraph1.versionMetadata,
        )
      await expect(tx)
        .emit(gns, 'SubgraphVersionUpdated')
        .withArgs(subgraph.id, newSubgraph1.subgraphDeploymentID, newSubgraph1.versionMetadata)
    })

    it('should fail when subgraph is deprecated', async function () {
      await deprecateSubgraph(me, subgraph.id, gns, curation, grt)
      const tx = gns
        .connect(me.signer)
        .publishNewVersion(
          subgraph.id,
          newSubgraph1.subgraphDeploymentID,
          newSubgraph1.versionMetadata,
        )
      // NOTE: deprecate burns the Subgraph NFT, when someone wants to publish a new version it won't find it
      await expect(tx).revertedWith('ERC721: owner query for nonexistent token')
    })
  })

  describe('receiving a subgraph from L1 (onTokenTransfer)', function () {
    it('cannot be called by someone other than the L2GraphTokenGateway', async function () {
      const { l1SubgraphId, curatedTokens } = await defaultL1SubgraphParams()
      const callhookData = defaultAbiCoder.encode(
        ['uint8', 'uint256', 'address'],
        [toBN(0), l1SubgraphId, me.address],
      )
      const tx = gns
        .connect(me.signer)
        .onTokenTransfer(mockL1GNS.address, curatedTokens, callhookData)
      await expect(tx).revertedWith('ONLY_GATEWAY')
    })
    it('rejects calls if the L1 sender is not the L1GNS', async function () {
      const { l1SubgraphId, curatedTokens } = await defaultL1SubgraphParams()
      const callhookData = defaultAbiCoder.encode(
        ['uint8', 'uint256', 'address'],
        [toBN(0), l1SubgraphId, me.address],
      )
      const tx = gatewayFinalizeTransfer(me.address, gns.address, curatedTokens, callhookData)

      await expect(tx).revertedWith('ONLY_L1_GNS_THROUGH_BRIDGE')
    })
    it('creates a subgraph in a disabled state', async function () {
      const { l1SubgraphId, curatedTokens } = await defaultL1SubgraphParams()
      const callhookData = defaultAbiCoder.encode(
        ['uint8', 'uint256', 'address'],
        [toBN(0), l1SubgraphId, me.address],
      )
      const tx = gatewayFinalizeTransfer(
        mockL1GNS.address,
        gns.address,
        curatedTokens,
        callhookData,
      )

      const l2SubgraphId = await gns.getAliasedL2SubgraphID(l1SubgraphId)

      await expect(tx)
        .emit(l2GraphTokenGateway, 'DepositFinalized')
        .withArgs(mockL1GRT.address, mockL1GNS.address, gns.address, curatedTokens)
      await expect(tx)
        .emit(gns, 'SubgraphReceivedFromL1')
        .withArgs(l1SubgraphId, l2SubgraphId, me.address, curatedTokens)

      const transferData = await gns.subgraphL2TransferData(l2SubgraphId)
      const subgraphData = await gns.subgraphs(l2SubgraphId)

      expect(transferData.tokens).eq(curatedTokens)
      expect(transferData.l2Done).eq(false)
      expect(transferData.subgraphReceivedOnL2BlockNumber).eq(await latestBlock())

      expect(subgraphData.vSignal).eq(0)
      expect(subgraphData.nSignal).eq(0)
      expect(subgraphData.subgraphDeploymentID).eq(HashZero)
      expect(subgraphData.reserveRatioDeprecated).eq(DEFAULT_RESERVE_RATIO)
      expect(subgraphData.disabled).eq(true)
      expect(subgraphData.withdrawableGRT).eq(0) // Important so that it's not the same as a deprecated subgraph!

      expect(await gns.ownerOf(l2SubgraphId)).eq(me.address)
    })
    it('returns the curation to the owner if it is under the minimum', async function () {
      const { l1SubgraphId } = await defaultL1SubgraphParams()
      const curatedTokens = toGRT('0.1')
      const callhookData = defaultAbiCoder.encode(
        ['uint8', 'uint256', 'address'],
        [toBN(0), l1SubgraphId, me.address],
      )
      const ownerBalanceBefore = await grt.balanceOf(me.address)
      const tx = gatewayFinalizeTransfer(
        mockL1GNS.address,
        gns.address,
        curatedTokens,
        callhookData,
      )

      const l2SubgraphId = await gns.getAliasedL2SubgraphID(l1SubgraphId)

      await expect(tx)
        .emit(l2GraphTokenGateway, 'DepositFinalized')
        .withArgs(mockL1GRT.address, mockL1GNS.address, gns.address, curatedTokens)
      await expect(tx)
        .emit(gns, 'SubgraphReceivedFromL1')
        .withArgs(l1SubgraphId, l2SubgraphId, me.address, curatedTokens)
      await expect(tx)
        .emit(gns, 'CuratorBalanceReturnedToBeneficiary')
        .withArgs(l1SubgraphId, me.address, curatedTokens)

      const transferData = await gns.subgraphL2TransferData(l2SubgraphId)
      const subgraphData = await gns.subgraphs(l2SubgraphId)

      expect(transferData.tokens).eq(0)
      expect(transferData.l2Done).eq(false)
      expect(transferData.subgraphReceivedOnL2BlockNumber).eq(await latestBlock())

      expect(subgraphData.vSignal).eq(0)
      expect(subgraphData.nSignal).eq(0)
      expect(subgraphData.subgraphDeploymentID).eq(HashZero)
      expect(subgraphData.reserveRatioDeprecated).eq(DEFAULT_RESERVE_RATIO)
      expect(subgraphData.disabled).eq(true)
      expect(subgraphData.withdrawableGRT).eq(0) // Important so that it's not the same as a deprecated subgraph!

      expect(await gns.ownerOf(l2SubgraphId)).eq(me.address)
      expect(await grt.balanceOf(me.address)).eq(ownerBalanceBefore.add(curatedTokens))
    })
    it('does not conflict with a locally created subgraph', async function () {
      const l2Subgraph = await publishNewSubgraph(me, newSubgraph0, gns)

      const { l1SubgraphId, curatedTokens } = await defaultL1SubgraphParams()
      const callhookData = defaultAbiCoder.encode(
        ['uint8', 'uint256', 'address'],
        [toBN(0), l1SubgraphId, me.address],
      )
      const tx = gatewayFinalizeTransfer(
        mockL1GNS.address,
        gns.address,
        curatedTokens,
        callhookData,
      )

      const l2SubgraphId = await gns.getAliasedL2SubgraphID(l1SubgraphId)

      await expect(tx)
        .emit(l2GraphTokenGateway, 'DepositFinalized')
        .withArgs(mockL1GRT.address, mockL1GNS.address, gns.address, curatedTokens)
      await expect(tx)
        .emit(gns, 'SubgraphReceivedFromL1')
        .withArgs(l1SubgraphId, l2SubgraphId, me.address, curatedTokens)

      const transferData = await gns.subgraphL2TransferData(l2SubgraphId)
      const subgraphData = await gns.subgraphs(l2SubgraphId)

      expect(transferData.tokens).eq(curatedTokens)
      expect(transferData.l2Done).eq(false)
      expect(transferData.subgraphReceivedOnL2BlockNumber).eq(await latestBlock())

      expect(subgraphData.vSignal).eq(0)
      expect(subgraphData.nSignal).eq(0)
      expect(subgraphData.subgraphDeploymentID).eq(HashZero)
      expect(subgraphData.reserveRatioDeprecated).eq(DEFAULT_RESERVE_RATIO)
      expect(subgraphData.disabled).eq(true)
      expect(subgraphData.withdrawableGRT).eq(0) // Important so that it's not the same as a deprecated subgraph!

      expect(await gns.ownerOf(l2SubgraphId)).eq(me.address)

      expect(l2Subgraph.id).not.eq(l2SubgraphId)
      const l2SubgraphData = await gns.subgraphs(l2Subgraph.id)
      expect(l2SubgraphData.vSignal).eq(0)
      expect(l2SubgraphData.nSignal).eq(0)
      expect(l2SubgraphData.subgraphDeploymentID).eq(l2Subgraph.subgraphDeploymentID)
      expect(l2SubgraphData.reserveRatioDeprecated).eq(DEFAULT_RESERVE_RATIO)
      expect(l2SubgraphData.disabled).eq(false)
      expect(l2SubgraphData.withdrawableGRT).eq(0)
    })
  })

  describe('finishing a subgraph transfer from L1', function () {
    it('publishes the transferred subgraph and mints signal with no tax', async function () {
      const { l1SubgraphId, curatedTokens, subgraphMetadata, versionMetadata } =
        await defaultL1SubgraphParams()
      const callhookData = defaultAbiCoder.encode(
        ['uint8', 'uint256', 'address'],
        [toBN(0), l1SubgraphId, me.address],
      )
      await gatewayFinalizeTransfer(mockL1GNS.address, gns.address, curatedTokens, callhookData)
      // Calculate expected signal before minting
      const expectedSignal = await curation.tokensToSignalNoTax(
        newSubgraph0.subgraphDeploymentID,
        curatedTokens,
      )
      const l2SubgraphId = await gns.getAliasedL2SubgraphID(l1SubgraphId)
      const tx = gns
        .connect(me.signer)
        .finishSubgraphTransferFromL1(
          l2SubgraphId,
          newSubgraph0.subgraphDeploymentID,
          subgraphMetadata,
          versionMetadata,
        )
      await expect(tx)
        .emit(gns, 'SubgraphPublished')
        .withArgs(l2SubgraphId, newSubgraph0.subgraphDeploymentID, DEFAULT_RESERVE_RATIO)
      await expect(tx).emit(gns, 'SubgraphMetadataUpdated').withArgs(l2SubgraphId, subgraphMetadata)
      await expect(tx)
        .emit(gns, 'SubgraphUpgraded')
        .withArgs(l2SubgraphId, expectedSignal, curatedTokens, newSubgraph0.subgraphDeploymentID)
      await expect(tx)
        .emit(gns, 'SubgraphVersionUpdated')
        .withArgs(l2SubgraphId, newSubgraph0.subgraphDeploymentID, versionMetadata)
      await expect(tx).emit(gns, 'SubgraphL2TransferFinalized').withArgs(l2SubgraphId)

      const subgraphAfter = await gns.subgraphs(l2SubgraphId)
      const transferDataAfter = await gns.subgraphL2TransferData(l2SubgraphId)
      expect(subgraphAfter.vSignal).eq(expectedSignal)
      expect(transferDataAfter.l2Done).eq(true)
      expect(subgraphAfter.disabled).eq(false)
      expect(subgraphAfter.subgraphDeploymentID).eq(newSubgraph0.subgraphDeploymentID)
      const expectedNSignal = await gns.vSignalToNSignal(l2SubgraphId, expectedSignal)
      expect(await gns.getCuratorSignal(l2SubgraphId, me.address)).eq(expectedNSignal)
      await expect(tx)
        .emit(gns, 'SignalMinted')
        .withArgs(l2SubgraphId, me.address, expectedNSignal, expectedSignal, curatedTokens)
    })
    it('cannot be called by someone other than the subgraph owner', async function () {
      const { l1SubgraphId, curatedTokens, subgraphMetadata, versionMetadata } =
        await defaultL1SubgraphParams()
      const callhookData = defaultAbiCoder.encode(
        ['uint8', 'uint256', 'address'],
        [toBN(0), l1SubgraphId, me.address],
      )
      await gatewayFinalizeTransfer(mockL1GNS.address, gns.address, curatedTokens, callhookData)
      const l2SubgraphId = await gns.getAliasedL2SubgraphID(l1SubgraphId)
      const tx = gns
        .connect(other.signer)
        .finishSubgraphTransferFromL1(
          l2SubgraphId,
          newSubgraph0.subgraphDeploymentID,
          subgraphMetadata,
          versionMetadata,
        )
      await expect(tx).revertedWith('GNS: Must be authorized')
    })
    it('rejects calls for a subgraph that does not exist', async function () {
      const l1SubgraphId = await buildSubgraphID(me.address, toBN('1'), 1)
      const metadata = randomHexBytes()
      const l2SubgraphId = await gns.getAliasedL2SubgraphID(l1SubgraphId)
      const tx = gns
        .connect(me.signer)
        .finishSubgraphTransferFromL1(
          l2SubgraphId,
          newSubgraph0.subgraphDeploymentID,
          metadata,
          metadata,
        )
      await expect(tx).revertedWith('ERC721: owner query for nonexistent token')
    })
    it('rejects calls for a subgraph that was not transferred from L1', async function () {
      const l2Subgraph = await publishNewSubgraph(me, newSubgraph0, gns)
      const metadata = randomHexBytes()

      const tx = gns
        .connect(me.signer)
        .finishSubgraphTransferFromL1(
          l2Subgraph.id,
          newSubgraph0.subgraphDeploymentID,
          metadata,
          metadata,
        )
      await expect(tx).revertedWith('INVALID_SUBGRAPH')
    })
    it('accepts calls to a pre-curated subgraph deployment', async function () {
      const { l1SubgraphId, curatedTokens, subgraphMetadata, versionMetadata } =
        await defaultL1SubgraphParams()
      const callhookData = defaultAbiCoder.encode(
        ['uint8', 'uint256', 'address'],
        [toBN(0), l1SubgraphId, me.address],
      )
      await gatewayFinalizeTransfer(mockL1GNS.address, gns.address, curatedTokens, callhookData)
      const l2SubgraphId = await gns.getAliasedL2SubgraphID(l1SubgraphId)

      // Calculate expected signal before minting
      const expectedSignal = await curation.tokensToSignalNoTax(
        newSubgraph0.subgraphDeploymentID,
        curatedTokens,
      )
      await grt.connect(me.signer).approve(curation.address, toGRT('100'))
      await curation
        .connect(me.signer)
        .mint(newSubgraph0.subgraphDeploymentID, toGRT('100'), toBN('0'))

      expect(await curation.getCurationPoolTokens(newSubgraph0.subgraphDeploymentID)).eq(
        toGRT('100'),
      )
      const tx = gns
        .connect(me.signer)
        .finishSubgraphTransferFromL1(
          l2SubgraphId,
          newSubgraph0.subgraphDeploymentID,
          subgraphMetadata,
          versionMetadata,
        )
      await expect(tx)
        .emit(gns, 'SubgraphPublished')
        .withArgs(l2SubgraphId, newSubgraph0.subgraphDeploymentID, DEFAULT_RESERVE_RATIO)
      await expect(tx).emit(gns, 'SubgraphMetadataUpdated').withArgs(l2SubgraphId, subgraphMetadata)
      await expect(tx)
        .emit(gns, 'SubgraphUpgraded')
        .withArgs(l2SubgraphId, expectedSignal, curatedTokens, newSubgraph0.subgraphDeploymentID)
      await expect(tx)
        .emit(gns, 'SubgraphVersionUpdated')
        .withArgs(l2SubgraphId, newSubgraph0.subgraphDeploymentID, versionMetadata)
      await expect(tx).emit(gns, 'SubgraphL2TransferFinalized').withArgs(l2SubgraphId)

      const subgraphAfter = await gns.subgraphs(l2SubgraphId)
      const transferDataAfter = await gns.subgraphL2TransferData(l2SubgraphId)
      expect(subgraphAfter.vSignal).eq(expectedSignal)
      expect(transferDataAfter.l2Done).eq(true)
      expect(subgraphAfter.disabled).eq(false)
      expect(subgraphAfter.subgraphDeploymentID).eq(newSubgraph0.subgraphDeploymentID)
      expect(await curation.getCurationPoolTokens(newSubgraph0.subgraphDeploymentID)).eq(
        toGRT('100').add(curatedTokens),
      )
    })
    it('rejects calls if the subgraph deployment ID is zero', async function () {
      const metadata = randomHexBytes()
      const { l1SubgraphId, curatedTokens } = await defaultL1SubgraphParams()
      const callhookData = defaultAbiCoder.encode(
        ['uint8', 'uint256', 'address'],
        [toBN(0), l1SubgraphId, me.address],
      )
      await gatewayFinalizeTransfer(mockL1GNS.address, gns.address, curatedTokens, callhookData)
      const l2SubgraphId = await gns.getAliasedL2SubgraphID(l1SubgraphId)
      const tx = gns
        .connect(me.signer)
        .finishSubgraphTransferFromL1(l2SubgraphId, HashZero, metadata, metadata)
      await expect(tx).revertedWith('GNS: deploymentID != 0')
    })
    it('rejects calls if the subgraph transfer was already finished', async function () {
      const metadata = randomHexBytes()
      const { l1SubgraphId, curatedTokens } = await defaultL1SubgraphParams()
      const callhookData = defaultAbiCoder.encode(
        ['uint8', 'uint256', 'address'],
        [toBN(0), l1SubgraphId, me.address],
      )
      await gatewayFinalizeTransfer(mockL1GNS.address, gns.address, curatedTokens, callhookData)
      const l2SubgraphId = await gns.getAliasedL2SubgraphID(l1SubgraphId)
      await gns
        .connect(me.signer)
        .finishSubgraphTransferFromL1(
          l2SubgraphId,
          newSubgraph0.subgraphDeploymentID,
          metadata,
          metadata,
        )

      const tx = gns
        .connect(me.signer)
        .finishSubgraphTransferFromL1(
          l2SubgraphId,
          newSubgraph0.subgraphDeploymentID,
          metadata,
          metadata,
        )
      await expect(tx).revertedWith('ALREADY_DONE')
    })
  })
  describe('claiming a curator balance with a message from L1 (onTokenTransfer)', function () {
    it('assigns a curator balance to a beneficiary', async function () {
      const mockL1GNSL2Alias = await getL2SignerFromL1(mockL1GNS.address)
      // Eth for gas:
      await setAccountBalance(await mockL1GNSL2Alias.getAddress(), parseEther('1'))

      const { l1SubgraphId, curatedTokens, subgraphMetadata, versionMetadata } =
        await defaultL1SubgraphParams()
      await transferMockSubgraphFromL1(
        l1SubgraphId,
        curatedTokens,
        subgraphMetadata,
        versionMetadata,
      )
      const l2SubgraphId = await gns.getAliasedL2SubgraphID(l1SubgraphId)
      const l2OwnerSignalBefore = await gns.getCuratorSignal(l2SubgraphId, me.address)

      const newCuratorTokens = toGRT('10')
      const callhookData = defaultAbiCoder.encode(
        ['uint8', 'uint256', 'address'],
        [toBN(1), l1SubgraphId, other.address],
      )
      const tx = await gatewayFinalizeTransfer(
        mockL1GNS.address,
        gns.address,
        newCuratorTokens,
        callhookData,
      )

      await expect(tx)
        .emit(gns, 'CuratorBalanceReceived')
        .withArgs(l1SubgraphId, l2SubgraphId, other.address, newCuratorTokens)

      const l2NewCuratorSignal = await gns.getCuratorSignal(l2SubgraphId, other.address)
      const expectedNewCuratorSignal = await gns.vSignalToNSignal(
        l2SubgraphId,
        await curation.tokensToSignalNoTax(newSubgraph0.subgraphDeploymentID, newCuratorTokens),
      )
      const l2OwnerSignalAfter = await gns.getCuratorSignal(l2SubgraphId, me.address)
      expect(l2OwnerSignalAfter).eq(l2OwnerSignalBefore)
      expect(l2NewCuratorSignal).eq(expectedNewCuratorSignal)
    })
    it('adds the signal to any existing signal for the beneficiary', async function () {
      const mockL1GNSL2Alias = await getL2SignerFromL1(mockL1GNS.address)
      // Eth for gas:
      await setAccountBalance(await mockL1GNSL2Alias.getAddress(), parseEther('1'))

      const { l1SubgraphId, curatedTokens, subgraphMetadata, versionMetadata } =
        await defaultL1SubgraphParams()
      await transferMockSubgraphFromL1(
        l1SubgraphId,
        curatedTokens,
        subgraphMetadata,
        versionMetadata,
      )

      const l2SubgraphId = await gns.getAliasedL2SubgraphID(l1SubgraphId)
      await grt.connect(governor.signer).mint(other.address, toGRT('10'))
      await grt.connect(other.signer).approve(gns.address, toGRT('10'))
      await gns.connect(other.signer).mintSignal(l2SubgraphId, toGRT('10'), toBN(0))
      const prevSignal = await gns.getCuratorSignal(l2SubgraphId, other.address)

      const newCuratorTokens = toGRT('10')
      const callhookData = defaultAbiCoder.encode(
        ['uint8', 'uint256', 'address'],
        [toBN(1), l1SubgraphId, other.address],
      )
      const tx = await gatewayFinalizeTransfer(
        mockL1GNS.address,
        gns.address,
        newCuratorTokens,
        callhookData,
      )

      await expect(tx)
        .emit(gns, 'CuratorBalanceReceived')
        .withArgs(l1SubgraphId, l2SubgraphId, other.address, newCuratorTokens)

      const expectedNewCuratorSignal = await gns.vSignalToNSignal(
        l2SubgraphId,
        await curation.tokensToSignalNoTax(newSubgraph0.subgraphDeploymentID, newCuratorTokens),
      )
      const l2CuratorBalance = await gns.getCuratorSignal(l2SubgraphId, other.address)
      expect(l2CuratorBalance).eq(prevSignal.add(expectedNewCuratorSignal))
    })
    it('cannot be called by someone other than the L2GraphTokenGateway', async function () {
      const { l1SubgraphId, curatedTokens, subgraphMetadata, versionMetadata } =
        await defaultL1SubgraphParams()
      await transferMockSubgraphFromL1(
        l1SubgraphId,
        curatedTokens,
        subgraphMetadata,
        versionMetadata,
      )
      const callhookData = defaultAbiCoder.encode(
        ['uint8', 'uint256', 'address'],
        [toBN(1), l1SubgraphId, me.address],
      )
      const tx = gns.connect(me.signer).onTokenTransfer(mockL1GNS.address, toGRT('1'), callhookData)
      await expect(tx).revertedWith('ONLY_GATEWAY')
    })
    it('rejects calls if the L1 sender is not the L1GNS', async function () {
      const { l1SubgraphId, curatedTokens, subgraphMetadata, versionMetadata } =
        await defaultL1SubgraphParams()
      await transferMockSubgraphFromL1(
        l1SubgraphId,
        curatedTokens,
        subgraphMetadata,
        versionMetadata,
      )
      const callhookData = defaultAbiCoder.encode(
        ['uint8', 'uint256', 'address'],
        [toBN(1), l1SubgraphId, me.address],
      )
      const tx = gatewayFinalizeTransfer(me.address, gns.address, toGRT('1'), callhookData)

      await expect(tx).revertedWith('ONLY_L1_GNS_THROUGH_BRIDGE')
    })
    it('if a subgraph does not exist, it returns the tokens to the beneficiary', async function () {
      const mockL1GNSL2Alias = await getL2SignerFromL1(mockL1GNS.address)
      // Eth for gas:
      await setAccountBalance(await mockL1GNSL2Alias.getAddress(), parseEther('1'))

      const { l1SubgraphId } = await defaultL1SubgraphParams()

      const callhookData = defaultAbiCoder.encode(
        ['uint8', 'uint256', 'address'],
        [toBN(1), l1SubgraphId, me.address],
      )
      const curatorTokensBefore = await grt.balanceOf(me.address)
      const gnsBalanceBefore = await grt.balanceOf(gns.address)
      const tx = gatewayFinalizeTransfer(mockL1GNS.address, gns.address, toGRT('1'), callhookData)
      await expect(tx)
        .emit(gns, 'CuratorBalanceReturnedToBeneficiary')
        .withArgs(l1SubgraphId, me.address, toGRT('1'))
      const curatorTokensAfter = await grt.balanceOf(me.address)
      expect(curatorTokensAfter).eq(curatorTokensBefore.add(toGRT('1')))
      const gnsBalanceAfter = await grt.balanceOf(gns.address)
      // gatewayFinalizeTransfer will mint the tokens that are sent to the curator,
      // so the GNS balance should be the same
      expect(gnsBalanceAfter).eq(gnsBalanceBefore)
    })
    it('returns tokens to the beneficiary if they are less than the minimum', async function () {
      const mockL1GNSL2Alias = await getL2SignerFromL1(mockL1GNS.address)
      // Eth for gas:
      await setAccountBalance(await mockL1GNSL2Alias.getAddress(), parseEther('1'))

      const { l1SubgraphId, curatedTokens, subgraphMetadata, versionMetadata } =
        await defaultL1SubgraphParams()
      await transferMockSubgraphFromL1(
        l1SubgraphId,
        curatedTokens,
        subgraphMetadata,
        versionMetadata,
      )
      const curatorTokensBefore = await grt.balanceOf(me.address)
      const gnsBalanceBefore = await grt.balanceOf(gns.address)
      const callhookData = defaultAbiCoder.encode(
        ['uint8', 'uint256', 'address'],
        [toBN(1), l1SubgraphId, me.address],
      )
      const tx = gatewayFinalizeTransfer(mockL1GNS.address, gns.address, toGRT('0.1'), callhookData)
      await expect(tx)
        .emit(gns, 'CuratorBalanceReturnedToBeneficiary')
        .withArgs(l1SubgraphId, me.address, toGRT('0.1'))
      const curatorTokensAfter = await grt.balanceOf(me.address)
      expect(curatorTokensAfter).eq(curatorTokensBefore.add(toGRT('0.1')))
      const gnsBalanceAfter = await grt.balanceOf(gns.address)
      // gatewayFinalizeTransfer will mint the tokens that are sent to the curator,
      // so the GNS balance should be the same
      expect(gnsBalanceAfter).eq(gnsBalanceBefore)
    })
    it('for an L2-native subgraph, it sends the tokens to the beneficiary', async function () {
      // This should never really happen unless there's a clash in subgraph IDs (which should
      // also never happen), but we test it anyway to ensure it's a well-defined behavior
      const mockL1GNSL2Alias = await getL2SignerFromL1(mockL1GNS.address)
      // Eth for gas:
      await setAccountBalance(await mockL1GNSL2Alias.getAddress(), parseEther('1'))

      const l2Subgraph = await publishNewSubgraph(me, newSubgraph0, gns)

      const callhookData = defaultAbiCoder.encode(
        ['uint8', 'uint256', 'address'],
        [toBN(1), l2Subgraph.id!, me.address],
      )
      const curatorTokensBefore = await grt.balanceOf(me.address)
      const gnsBalanceBefore = await grt.balanceOf(gns.address)
      const tx = gatewayFinalizeTransfer(mockL1GNS.address, gns.address, toGRT('1'), callhookData)
      await expect(tx)
        .emit(gns, 'CuratorBalanceReturnedToBeneficiary')
        .withArgs(l2Subgraph.id!, me.address, toGRT('1'))
      const curatorTokensAfter = await grt.balanceOf(me.address)
      expect(curatorTokensAfter).eq(curatorTokensBefore.add(toGRT('1')))
      const gnsBalanceAfter = await grt.balanceOf(gns.address)
      // gatewayFinalizeTransfer will mint the tokens that are sent to the curator,
      // so the GNS balance should be the same
      expect(gnsBalanceAfter).eq(gnsBalanceBefore)
    })
    it('if a subgraph transfer was not finished, it returns the tokens to the beneficiary', async function () {
      const mockL1GNSL2Alias = await getL2SignerFromL1(mockL1GNS.address)
      // Eth for gas:
      await setAccountBalance(await mockL1GNSL2Alias.getAddress(), parseEther('1'))

      const { l1SubgraphId, curatedTokens } = await defaultL1SubgraphParams()
      const callhookDataSG = defaultAbiCoder.encode(
        ['uint8', 'uint256', 'address'],
        [toBN(0), l1SubgraphId, me.address],
      )
      await gatewayFinalizeTransfer(mockL1GNS.address, gns.address, curatedTokens, callhookDataSG)

      // At this point the SG exists, but transfer is not finished

      const callhookData = defaultAbiCoder.encode(
        ['uint8', 'uint256', 'address'],
        [toBN(1), l1SubgraphId, me.address],
      )
      const curatorTokensBefore = await grt.balanceOf(me.address)
      const gnsBalanceBefore = await grt.balanceOf(gns.address)
      const tx = gatewayFinalizeTransfer(mockL1GNS.address, gns.address, toGRT('1'), callhookData)
      await expect(tx)
        .emit(gns, 'CuratorBalanceReturnedToBeneficiary')
        .withArgs(l1SubgraphId, me.address, toGRT('1'))
      const curatorTokensAfter = await grt.balanceOf(me.address)
      expect(curatorTokensAfter).eq(curatorTokensBefore.add(toGRT('1')))
      const gnsBalanceAfter = await grt.balanceOf(gns.address)
      // gatewayFinalizeTransfer will mint the tokens that are sent to the curator,
      // so the GNS balance should be the same
      expect(gnsBalanceAfter).eq(gnsBalanceBefore)
    })

    it('if a subgraph was deprecated after transfer, it returns the tokens to the beneficiary', async function () {
      const mockL1GNSL2Alias = await getL2SignerFromL1(mockL1GNS.address)
      // Eth for gas:
      await setAccountBalance(await mockL1GNSL2Alias.getAddress(), parseEther('1'))

      const { l1SubgraphId, curatedTokens, subgraphMetadata, versionMetadata } =
        await defaultL1SubgraphParams()
      await transferMockSubgraphFromL1(
        l1SubgraphId,
        curatedTokens,
        subgraphMetadata,
        versionMetadata,
      )
      const l2SubgraphId = await gns.getAliasedL2SubgraphID(l1SubgraphId)
      await gns.connect(me.signer).deprecateSubgraph(l2SubgraphId)

      // SG was transferred, but is deprecated now!

      const callhookData = defaultAbiCoder.encode(
        ['uint8', 'uint256', 'address'],
        [toBN(1), l1SubgraphId, me.address],
      )
      const curatorTokensBefore = await grt.balanceOf(me.address)
      const gnsBalanceBefore = await grt.balanceOf(gns.address)
      const tx = gatewayFinalizeTransfer(mockL1GNS.address, gns.address, toGRT('1'), callhookData)
      await expect(tx)
        .emit(gns, 'CuratorBalanceReturnedToBeneficiary')
        .withArgs(l1SubgraphId, me.address, toGRT('1'))
      const curatorTokensAfter = await grt.balanceOf(me.address)
      expect(curatorTokensAfter).eq(curatorTokensBefore.add(toGRT('1')))
      const gnsBalanceAfter = await grt.balanceOf(gns.address)
      // gatewayFinalizeTransfer will mint the tokens that are sent to the curator,
      // so the GNS balance should be the same
      expect(gnsBalanceAfter).eq(gnsBalanceBefore)
    })
  })
  describe('onTokenTransfer with invalid codes', function () {
    it('reverts', async function () {
      // This should never really happen unless the Arbitrum bridge is compromised,
      // so we test it anyway to ensure it's a well-defined behavior.
      // code 2 does not exist:
      const callhookData = defaultAbiCoder.encode(
        ['uint8', 'uint256', 'address'],
        [toBN(2), toBN(1337), me.address],
      )
      const tx = gatewayFinalizeTransfer(mockL1GNS.address, gns.address, toGRT('1'), callhookData)
      await expect(tx).revertedWith('INVALID_CODE')
    })
  })
  describe('getAliasedL2SubgraphID', function () {
    it('returns the L2 subgraph ID that is the L1 subgraph ID with an offset', async function () {
      const l1SubgraphId = ethers.BigNumber.from(
        '68799548758199140224151701590582019137924969401915573086349306511960790045480',
      )
      const l2SubgraphId = await gns.getAliasedL2SubgraphID(l1SubgraphId)
      const offset = ethers.BigNumber.from(
        '0x1111000000000000000000000000000000000000000000000000000000001111',
      )
      const base = ethers.constants.MaxUint256.add(1)
      const expectedL2SubgraphId = l1SubgraphId.add(offset).mod(base)
      expect(l2SubgraphId).eq(expectedL2SubgraphId)
    })
    it('wraps around MAX_UINT256 in case of overflow', async function () {
      const l1SubgraphId = ethers.constants.MaxUint256
      const l2SubgraphId = await gns.getAliasedL2SubgraphID(l1SubgraphId)
      const offset = ethers.BigNumber.from(
        '0x1111000000000000000000000000000000000000000000000000000000001111',
      )
      const base = ethers.constants.MaxUint256.add(1)
      const expectedL2SubgraphId = l1SubgraphId.add(offset).mod(base)
      expect(l2SubgraphId).eq(expectedL2SubgraphId)
    })
  })
})
