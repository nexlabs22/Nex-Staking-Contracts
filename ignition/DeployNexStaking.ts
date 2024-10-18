import { ethers, upgrades } from "hardhat";

import { AnfiAddress, ArbeiAddress, Crypto5Address, Mag7Address, SepoliaNexStakingProxy, SepoliaNonFungiblePositionManagerAddress, SepoliaUSDCAddress, SepoliaUSDTAddress, SepoliaUniswapV2Router, SepoliaUniswapV3Factory, SepoliaUniswapV3Router, SepoliaWethAddress, ERC4626FactoryAddress, FeePercent } from "../contractAddresses";


async function deployNexStaking() {
    const [deployer] = await ethers.getSigners();

    const NexStaking = await ethers.getContractFactory("NexStaking")

    const nexStaking = await upgrades.deployProxy(NexStaking, [
        [Mag7Address, AnfiAddress, Crypto5Address, ArbeiAddress],
        [SepoliaUSDTAddress],
        [3, 3, 3, 3],
        ERC4626FactoryAddress,
        SepoliaUniswapV3Router,
        SepoliaWethAddress,
        FeePercent
    ], { initializer: 'initialize' })

    await nexStaking.deployed()

    console.log(
        `NexStaking deployed: ${await nexStaking.address}`
    );
}

deployNexStaking().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});