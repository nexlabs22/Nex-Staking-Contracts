// // SPDX-License-Identifier: MIT
// pragma solidity ^0.8.26;

// import {Test} from "forge-std/Test.sol";
// import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
// import {
//     TransparentUpgradeableProxy,
//     ITransparentUpgradeableProxy
// } from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
// import {NexStagingV2} from "../../contracts/NexStagingV2.sol";
// import {DeployNexStagingV2} from "../../script/DeployNexStagingV2.s.sol";

// contract UpgradeNexStagingTest is Test {
//     ProxyAdmin proxyAdmin;
//     ITransparentUpgradeableProxy proxy;
//     NexStagingV2 newImplementation;
//     DeployNexStagingV2 upgradeScript;

//     address deployer;
//     address proxyAdminAddress = address(0x51256F5459C1DdE0C794818AF42569030901a098); // Replace with actual ProxyAdmin address
//     address proxyAddress = address(0x54fab467C7Cad4D80707E845c611B599a2d33CF5); // Replace with actual Proxy address

//     function setUp() public {
//         // Set up the test environment
//         deployer = vm.addr(1);
//         vm.deal(deployer, 1 ether);

//         // Deploy the ProxyAdmin and proxy
//         proxyAdmin = ProxyAdmin(proxyAdminAddress);
//         proxy = ITransparentUpgradeableProxy(payable(proxyAddress));

//         // Deploy the upgrade script
//         upgradeScript = new DeployNexStagingV2();
//     }

//     function testUpgrade() public {
//         // Simulate the deployment script execution
//         vm.startPrank(deployer);

//         // Mock the new implementation contract
//         newImplementation = new NexStagingV2();

//         // Call the upgrade script's run function
//         upgradeScript.run();

//         // Check that the proxy was upgraded to the new implementation
//         proxyAdmin.upgradeAndCall(proxy, address(upgradeScript), "");
//         // assertEq(currentImplementation, address(newImplementation), "Proxy was not upgraded to the new implementation");

//         vm.stopPrank();
//     }
// }
