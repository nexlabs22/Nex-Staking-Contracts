// // SPDX-License-Identifier: MIT
// pragma solidity ^0.8.26;

// import {Script} from "forge-std/Script.sol";
// import {NexStaging} from "../contracts/NexStaging.sol";
// import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

// contract DeployNexStaging is Script {
//     function run() external returns (address) {
//         address proxy = deployNexStaging();
//         return proxy;
//     }

//     function deployNexStaging() public returns (address) {
//         vm.startBroadcast();
//         NexStaging nexStaging = new NexStaging();
//         ERC1967Proxy proxy = new ERC1967Proxy(address(nexStaging), "");
//         NexStaging(address(proxy)).initialize();
//         vm.stopBroadcast();
//         return address(proxy);
//     }
// }
