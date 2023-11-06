import { task } from 'hardhat/config'
import { HardhatRuntimeEnvironment, TaskArguments } from 'hardhat/types'
import { TASK_TEST } from 'hardhat/builtin-tasks/task-names'
import glob from 'glob'
import fs from 'fs'
import { runScriptWithHardhat } from 'hardhat/internal/util/scripts-runner'
import { isGraphL1ChainId } from '@graphprotocol/sdk'
import { GRE_TASK_PARAMS } from '@graphprotocol/sdk/gre'

const CONFIG_TESTS = 'e2e/deployment/config/**/*.test.ts'
const INIT_TESTS = 'e2e/deployment/init/**/*.test.ts'

// Built-in test & run tasks don't support GRE arguments
// so we pass them by overriding GRE config object
const setGraphConfig = async (args: TaskArguments, hre: HardhatRuntimeEnvironment) => {
  const greArgs = [
    'graphConfig',
    'l1GraphConfig',
    'l2GraphConfig',
    'addressBook',
    'disableSecureAccounts',
    'fork',
  ]

  for (const arg of greArgs) {
    if (args[arg]) {
      if (arg === 'graphConfig') {
        const l1 = isGraphL1ChainId(hre.config.networks[hre.network.name].chainId)
        hre.config.graph[l1 ? 'l1GraphConfig' : 'l2GraphConfig'] = args[arg]
      } else {
        hre.config.graph[arg] = args[arg]
      }
    }
  }
}

task('e2e', 'Run all e2e tests')
  .addOptionalParam('graphConfig', GRE_TASK_PARAMS.graphConfig.description)
  .addOptionalParam('l1GraphConfig', GRE_TASK_PARAMS.graphConfig.description)
  .addOptionalParam('l2GraphConfig', GRE_TASK_PARAMS.graphConfig.description)
  .addOptionalParam('addressBook', GRE_TASK_PARAMS.addressBook.description)
  .addFlag('skipBridge', 'Skip bridge tests')
  .setAction(async (args, hre: HardhatRuntimeEnvironment) => {
    let testFiles = [
      ...new glob.GlobSync(CONFIG_TESTS).found,
      ...new glob.GlobSync(INIT_TESTS).found,
    ]

    if (args.skipBridge) {
      testFiles = testFiles.filter((file) => !['l1', 'l2'].includes(file.split('/')[3]))
    }

    // Disable secure accounts, we don't need them for this task
    hre.config.graph.disableSecureAccounts = true

    setGraphConfig(args, hre)
    await hre.run(TASK_TEST, {
      testFiles: testFiles,
    })
  })

task('e2e:config', 'Run deployment configuration e2e tests')
  .addOptionalParam('graphConfig', GRE_TASK_PARAMS.graphConfig.description)
  .addOptionalParam('l1GraphConfig', GRE_TASK_PARAMS.graphConfig.description)
  .addOptionalParam('l2GraphConfig', GRE_TASK_PARAMS.graphConfig.description)
  .addOptionalParam('addressBook', GRE_TASK_PARAMS.addressBook.description)
  .setAction(async (args, hre: HardhatRuntimeEnvironment) => {
    const files = new glob.GlobSync(CONFIG_TESTS).found

    // Disable secure accounts, we don't need them for this task
    hre.config.graph.disableSecureAccounts = true

    setGraphConfig(args, hre)
    await hre.run(TASK_TEST, {
      testFiles: files,
    })
  })

task('e2e:init', 'Run deployment initialization e2e tests')
  .addOptionalParam('graphConfig', GRE_TASK_PARAMS.graphConfig.description)
  .addOptionalParam('l1GraphConfig', GRE_TASK_PARAMS.graphConfig.description)
  .addOptionalParam('l2GraphConfig', GRE_TASK_PARAMS.graphConfig.description)
  .addOptionalParam('addressBook', GRE_TASK_PARAMS.addressBook.description)
  .setAction(async (args, hre: HardhatRuntimeEnvironment) => {
    const files = new glob.GlobSync(INIT_TESTS).found

    // Disable secure accounts, we don't need them for this task
    hre.config.graph.disableSecureAccounts = true

    setGraphConfig(args, hre)
    await hre.run(TASK_TEST, {
      testFiles: files,
    })
  })

task('e2e:scenario', 'Run scenario scripts and e2e tests')
  .addPositionalParam('scenario', 'Name of the scenario to run')
  .addFlag('disableSecureAccounts', 'Disable secure accounts on GRE')
  .addOptionalParam('addressBook', GRE_TASK_PARAMS.addressBook.description)
  .addOptionalParam('graphConfig', GRE_TASK_PARAMS.graphConfig.description)
  .addOptionalParam('l1GraphConfig', GRE_TASK_PARAMS.graphConfig.description)
  .addOptionalParam('l2GraphConfig', GRE_TASK_PARAMS.graphConfig.description)
  .addFlag('skipScript', "Don't run scenario script")
  .setAction(async (args, hre: HardhatRuntimeEnvironment) => {
    setGraphConfig(args, hre)

    const script = `e2e/scenarios/${args.scenario}.ts`
    const test = `e2e/scenarios/${args.scenario}.test.ts`

    console.log(`> Running scenario: ${args.scenario}`)
    console.log(`- script file: ${script}`)
    console.log(`- test file: ${test}`)

    if (!args.skipScript) {
      if (fs.existsSync(script)) {
        await runScriptWithHardhat(hre.hardhatArguments, script, [
          args.addressBook,
          args.graphConfig,
          args.l1GraphConfig,
          args.l2GraphConfig,
          args.disableSecureAccounts,
        ])
      } else {
        console.log(`No script found for scenario ${args.scenario}`)
      }
    }

    if (fs.existsSync(test)) {
      await hre.run(TASK_TEST, {
        testFiles: [test],
      })
    } else {
      throw new Error(`No test found for scenario ${args.scenario}`)
    }
  })

task('e2e:upgrade', 'Run upgrade tests')
  .addPositionalParam('upgrade', 'Name of the upgrade to run')
  .addFlag('disableSecureAccounts', 'Disable secure accounts on GRE')
  .addFlag('fork', 'Enable fork behavior on GRE')
  .addFlag('post', 'Wether to run pre/post upgrade scripts')
  .addOptionalParam('addressBook', GRE_TASK_PARAMS.addressBook.description)
  .addOptionalParam('graphConfig', GRE_TASK_PARAMS.graphConfig.description)
  .addOptionalParam('l1GraphConfig', GRE_TASK_PARAMS.graphConfig.description)
  .addOptionalParam('l2GraphConfig', GRE_TASK_PARAMS.graphConfig.description)
  .setAction(async (args, hre: HardhatRuntimeEnvironment) => {
    setGraphConfig(args, hre)
    await runUpgrade(args, hre, args.post ? 'post' : 'pre')
  })

async function runUpgrade(args: any, hre: HardhatRuntimeEnvironment, type: 'pre' | 'post') {
  const script = `e2e/upgrades/${args.upgrade}/${type}-upgrade.ts`
  const test = `e2e/upgrades/${args.upgrade}/${type}-upgrade.test.ts`

  console.log(`> Running ${type}-upgrade: ${args.upgrade}`)
  console.log(`- script file: ${script}`)
  console.log(`- test file: ${test}`)

  // Run script
  if (fs.existsSync(script)) {
    console.log(`> Running ${type}-upgrade script: ${script}`)
    await runScriptWithHardhat(hre.hardhatArguments, script, [
      args.addressBook,
      args.graphConfig,
      args.l1GraphConfig,
      args.l2GraphConfig,
      args.disableSecureAccounts,
      args.fork,
    ])
  }

  // Run test
  if (fs.existsSync(test)) {
    console.log(`> Running ${type}-upgrade test: ${test}`)
    await hre.run(TASK_TEST, {
      testFiles: [test],
    })
  }
}
