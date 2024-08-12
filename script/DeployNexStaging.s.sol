// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/Test.sol";
import {NexStaging} from "../contracts/NexStaging.sol";
import {MockERC20} from "../test/foundry/mocks/MockERC20.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";
import {Options} from "openzeppelin-foundry-upgrades/Options.sol";
import {Defender, ApprovalProcessResponse} from "openzeppelin-foundry-upgrades/Defender.sol";

contract DeployNexStaging is Script {
    NexStaging public nexStaging;
    MockERC20 public nexLabsToken;
    MockERC20 public indexToken1;
    MockERC20 public indexToken2;
    ProxyAdmin public proxyAdmin;

    function setUp() public {}

    function run() external {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerKey);

        nexLabsToken = new MockERC20("NexLabs", "NXL");
        indexToken1 = new MockERC20("Index Token 1", "IDX1");
        indexToken2 = new MockERC20("Index Token 2", "IDX2");

        address[] memory tokenAddresses = new address[](3);
        tokenAddresses[0] = address(nexLabsToken);
        tokenAddresses[1] = address(indexToken1);
        tokenAddresses[2] = address(indexToken2);

        uint256[] memory tokenAPYs = new uint256[](3);
        tokenAPYs[0] = 15;
        tokenAPYs[1] = 10;
        tokenAPYs[2] = 20;

        uint256 feePercent = 3;

        bytes memory data = abi.encodeWithSignature(
            "initialize(address,address[],uint256[],uint256)",
            address(nexLabsToken),
            tokenAddresses,
            tokenAPYs,
            feePercent
        );

        // ApprovalProcessResponse memory upgradeApprovalProcess = Defender.getUpgradeApprovalProcess();

        // if (upgradeApprovalProcess.via == address(0)) {
        //     revert(
        //         string.concat(
        //             "Upgrade approval process with id ",
        //             upgradeApprovalProcess.approvalProcessId,
        //             " has no assigned address"
        //         )
        //     );
        // }

        // Options memory opts;
        // opts.defender.useDefenderDeploy = true;

        // address proxy = Upgrades.deployUUPSProxy("NexStaging.sol", data, opts);
        address proxy =
            Upgrades.deployTransparentProxy("NexStaging.sol", 0x51256F5459C1DdE0C794818AF42569030901a098, data);

        vm.stopBroadcast();

        console.log("Deployed proxy to address", proxy);
    }
}
