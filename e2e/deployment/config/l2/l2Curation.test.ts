import { expect } from 'chai'
import hre from 'hardhat'
import { getItemValue } from '../../../../cli/config'
import GraphChain from '../../../../gre/helpers/chain'
import { toGRT } from '../../../../cli/network'

describe('[L2] L2Curation configuration', () => {
  const graph = hre.graph()
  const {
    graphConfig,
    contracts: { Controller, L2Curation, BancorFormula, GraphCurationToken },
  } = graph

  before(async function () {
    if (GraphChain.isL1(graph.chainId)) this.skip()
  })

  it('should be controlled by Controller', async function () {
    const controller = await L2Curation.controller()
    expect(controller).eq(Controller.address)
  })

  it('curationTokenMaster should match the GraphCurationToken deployment address', async function () {
    const gct = await L2Curation.curationTokenMaster()
    expect(gct).eq(GraphCurationToken.address)
  })

  it('defaultReserveRatio should be a constant 1000000', async function () {
    const value = await L2Curation.defaultReserveRatio()
    const expected = 1000000
    expect(value).eq(expected)
  })

  it('curationTaxPercentage should match "curationTaxPercentage" in the config file', async function () {
    const value = await L2Curation.curationTaxPercentage()
    const expected = getItemValue(graphConfig, 'contracts/L2Curation/init/curationTaxPercentage')
    expect(value).eq(expected)
  })

  it('minimumCurationDeposit should match the hardcoded value', async function () {
    const value = await L2Curation.minimumCurationDeposit()
    const expected = toGRT('1')
    expect(value).eq(expected)
  })
})
