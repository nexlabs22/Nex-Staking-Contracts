import { ethers, upgrades } from "hardhat";
import { AnfiAddress, ArbeiAddress, Crypto5Address, Mag7Address, SepoliaNexStakingProxy, SepoliaNonFungiblePositionManagerAddress, SepoliaUSDCAddress, SepoliaUSDTAddress, SepoliaUniswapV2Router, SepoliaUniswapV3Factory, SepoliaUniswapV3Router, SepoliaWethAddress, ERC4626FactoryAddress, FeePercent, Threshold } from "../contractAddresses";

async function deployFeeManager() {
    const [deployer] = await ethers.getSigners();

    const FeeManager = await ethers.getContractFactory("FeeManager")

    const feeManager = await upgrades.deployProxy(FeeManager, [
        [Mag7Address, AnfiAddress, Crypto5Address, ArbeiAddress],
        [Mag7Address, AnfiAddress, Crypto5Address, ArbeiAddress, SepoliaUSDTAddress],
        [3, 3, 3, 3],
        SepoliaUniswapV3Router,
        SepoliaUniswapV2Router,
        SepoliaUniswapV3Factory,
        SepoliaNonFungiblePositionManagerAddress,
        SepoliaWethAddress,
        SepoliaUSDCAddress,
        Threshold
    ], { initializer: 'initialize' })

    await feeManager.deployed()

    console.log(
        `FeeManager deployed: ${await feeManager.address}`
    );
}

deployFeeManager().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});