import { ethers, upgrades } from "hardhat";

async function deployERC4626Factory() {
    const [deployer] = await ethers.getSigners();

    const ERC4626Factory = await ethers.getContractFactory("ERC4626Factory")

    const erc4626Factory = await upgrades.deployProxy(ERC4626Factory, [], { initializer: 'initialize' })

    await erc4626Factory.deployed()

    console.log(
        `FeeManager deployed: ${await erc4626Factory.address}`
    );
}

deployERC4626Factory().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});