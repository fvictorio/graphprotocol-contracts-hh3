// import { hardhatBaseConfig } from 'hardhat-graph-protocol/sdk'
// 
// // Hardhat plugins
// import '@nomicfoundation/hardhat-foundry'
// import '@nomicfoundation/hardhat-toolbox'
// import '@nomicfoundation/hardhat-ignition-ethers'
// import 'hardhat-storage-layout'
// import 'hardhat-contract-sizer'
// import 'hardhat-secure-accounts'
// import { HardhatUserConfig } from 'hardhat/types'
// 
// // Skip importing hardhat-graph-protocol when building the project, it has circular dependency
// if (process.env.BUILD_RUN !== 'true') {
//   require('hardhat-graph-protocol')
//   require('./tasks/deploy')
// }


import { HardhatUserConfig } from "hardhat/config"

const config: HardhatUserConfig = {
  solidity: {
    version: '0.8.27',
    settings: {
      optimizer: {
        enabled: true,
        runs: 20,
      },
    },
    remappings: [
"@graphprotocol/contracts/=node_modules/@graphprotocol/contracts/",
"forge-std/=lib/forge-std/src/",
"ds-test/=lib/forge-std/lib/ds-test/src/",
"eth-gas-reporter/=node_modules/eth-gas-reporter/",
"hardhat/=node_modules/hardhat/",
"@openzeppelin/contracts/=node_modules/@openzeppelin/contracts/",
"@openzeppelin/contracts-upgradeable/=node_modules/@openzeppelin/contracts-upgradeable/",
    ]
  },
  graph: {},
}

export default config
