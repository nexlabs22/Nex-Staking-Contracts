// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/Test.sol";
import {NexStaging} from "../contracts/NexStaging.sol";
import {MockERC20} from "../test/foundry/mocks/MockERC20.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

contract DeployNexStaging is Script {
    NexStaging public nexStaging;
    MockERC20 public nexLabsToken;
    MockERC20 public indexToken1;
    MockERC20 public indexToken2;
    ProxyAdmin public proxyAdmin;

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

        NexStaging nexStagingImplementation = new NexStaging();

        bytes memory data = abi.encodeWithSignature(
            "initialize(address,address[],uint256[],uint256)",
            address(nexLabsToken),
            tokenAddresses,
            tokenAPYs,
            feePercent
        );

        proxyAdmin = new ProxyAdmin(msg.sender);
        TransparentUpgradeableProxy proxy =
            new TransparentUpgradeableProxy(address(nexStagingImplementation), address(proxyAdmin), data);

        nexStaging = NexStaging(address(proxy));

        vm.stopBroadcast();

        console.log("NexStaging deployed to:", address(nexStaging));
        console.log("NexStaging Proxy deployed to:", address(proxy));
        console.log("ProxyAdmin deployed to:", address(proxyAdmin));
        console.log("NexLabsToken deployed to:", address(nexLabsToken));
        console.log("IndexToken1 deployed to:", address(indexToken1));
        console.log("IndexToken2 deployed to:", address(indexToken2));
    }
}

// import {Script} from "forge-std/Script.sol";
// import {console} from "forge-std/Test.sol";
// import {NexStaging} from "../contracts/NexStaging.sol";
// import {MockERC20} from "../test/foundry/mocks/MockERC20.sol";
// import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
// import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
// import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
// import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

// contract DeployNexStaging is Script {
//     // UUPSUpgradeable proxy;
//     NexStaging public nexStaging;
//     MockERC20 public nexLabsToken;
//     MockERC20 public indexToken1;
//     MockERC20 public indexToken2;

//     function run() external {
//         uint256 deployerKey = vm.envUint("PRIVATE_KEY");
//         vm.startBroadcast(deployerKey);

//         nexLabsToken = new MockERC20("NexLabs", "NXL");
//         indexToken1 = new MockERC20("Index Token 1", "IDX1");
//         indexToken2 = new MockERC20("Index Token 2", "IDX2");

//         address[] memory tokenAddresses = new address[](3);
//         tokenAddresses[0] = address(nexLabsToken);
//         tokenAddresses[1] = address(indexToken1);
//         tokenAddresses[2] = address(indexToken2);

//         uint256[] memory tokenAPYs = new uint256[](3);
//         tokenAPYs[0] = 15;
//         tokenAPYs[1] = 10;
//         tokenAPYs[2] = 20;

//         uint256 feePercent = 3;

//         NexStaging nexStagingImplementation = new NexStaging();

//         bytes memory data = abi.encodeWithSignature(
//             "initialize(address,address[],uint256[],uint256)",
//             address(nexLabsToken),
//             tokenAddresses,
//             tokenAPYs,
//             feePercent
//         );

//         nexStaging = new NexStaging();
//         ProxyAdmin proxyAdmin = ProxyAdmin(msg.sender);
//         TransparentUpgradeableProxy proxy =
//             new TransparentUpgradeableProxy(address(nexStagingImplementation), address(proxyAdmin), data);

//         nexStaging = NexStaging(address(proxy));

//         vm.stopBroadcast();

//         console.log("NexStaging deployed to:", address(nexStaging));
//         console.log("NexStaging Proxy deployed to:", address(proxy));
//         console.log("ProxyAdmin deployed to:", address(proxyAdmin));
//         console.log("NexLabsToken deployed to:", address(nexLabsToken));
//         console.log("IndexToken1 deployed to:", address(indexToken1));
//         console.log("IndexToken2 deployed to:", address(indexToken2));
//     }
// }
