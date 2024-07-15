import type { HardhatUserConfig, NetworkUserConfig } from "hardhat/types";
import "@nomiclabs/hardhat-ethers";
import "@nomiclabs/hardhat-waffle";
import "@nomiclabs/hardhat-web3";
import "@nomiclabs/hardhat-truffle5";
import "@nomiclabs/hardhat-etherscan";
import 'hardhat-deploy'
import "hardhat-abi-exporter";
import "hardhat-contract-sizer";
//import "hardhat-gas-reporter";
import '@layerzerolabs/toolbox-hardhat'
import "solidity-coverage";
import "dotenv/config";

import { EndpointId } from '@layerzerolabs/lz-definitions'

const KEY_TESTNET = '';
const KEY_MAINNET = '';

const bscTestnet: NetworkUserConfig = {
  url: "https://data-seed-prebsc-1-s1.binance.org:8545/",
  chainId: 97,
  accounts: [KEY_TESTNET!],
  allowUnlimitedContractSize: true,
};

const sepolia: NetworkUserConfig = {
  url: "https://eth-sepolia.g.alchemy.com/v2/TGU5kpgvlidnj2XedQMW5gnsEu0l7cBq",
  chainId: 11155111,
  accounts: [KEY_TESTNET!],
  allowUnlimitedContractSize: true,
}

const bscMainnet: NetworkUserConfig = {
  url: "https://bsc-dataseed.binance.org/",
  chainId: 56,
  accounts: [KEY_MAINNET!],
  allowUnlimitedContractSize: true,
};

const arbitrum: NetworkUserConfig = {
  url: "https://arb-mainnet.g.alchemy.com/v2/MIxCiB0SQrdYBPnlBMv0Fb2ym65VL1rS",
  chainId: 42161,
  accounts: [KEY_MAINNET!],
};

const ethMainnet: NetworkUserConfig = {
  url: "https://mainnet.infura.io/v3/673e686ebb14446396f0f974cfed841d",
  chainId: 1,
  accounts: [KEY_MAINNET!],
  allowUnlimitedContractSize: true,
};

const config: HardhatUserConfig = {
  defaultNetwork: "hardhat",
  networks: {
    hardhat: {
      allowUnlimitedContractSize: true,
    },
    //testnet: sepolia,
    //mainnet: arbitrum
  },
  solidity: {
    compilers: [
      {
        version: "0.8.10",
        settings: {
          optimizer: {
            enabled: true,
            runs: 1,
          },
        },
      },
      {
        version: "0.8.20",
        settings: {
          optimizer: {
            enabled: true,
            runs: 1,
          },
        },
      },
      {
        version: "0.8.0",
        settings: {
          optimizer: {
            enabled: true,
            runs: 1,
          },
        },
      },
      {
        version: "0.6.12",
        settings: {
          optimizer: {
            enabled: true,
            runs: 1,
          },
        },
      },
      {
        version: "0.7.6",
        settings: {
          optimizer: {
            enabled: true,
            runs: 1,
          },
        },
      },
    ],
    overrides: {
      "contracts/VECake.sol": {
        version: "0.8.10",
        settings: {
          optimizer: {
            enabled: true,
            runs: 9,
          },
        },
      },
      "contracts/test/VECakeTest.sol": {
        version: "0.8.10",
        settings: {
          optimizer: {
            enabled: true,
            runs: 9,
          },
        },
      },
    },
  },
  // contractSizer: {
  //   alphaSort: true,
  //   runOnCompile: true,
  //   disambiguatePaths: false,
  // },
  paths: {
    sources: "./contracts",
    tests: "./test",
    cache: "./cache",
    artifacts: "./artifacts",
  },
  abiExporter: {
    path: "./data/abi",
    clear: true,
    flat: false,
  },
  etherscan: {
    apiKey: ""
  }
};

export default config;
