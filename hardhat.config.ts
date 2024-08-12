import { HardhatUserConfig } from "hardhat/config";
import "@nomicfoundation/hardhat-toolbox";
require("@nomicfoundation/hardhat-foundry");

const config: HardhatUserConfig = {
  solidity: {
    version: "0.8.26",
    settings: {
      outputSelection: {
        "*": {
          "*": ["storageLayout"],
        },
      },
    },
  },
  // defender: {
  //   apiKey: process.env.DEFENDER_KEY,
  //   apiSecret: process.env.DEFENDER_SECRET,
  // },
};

export default config;
