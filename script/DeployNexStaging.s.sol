// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/Test.sol";
import {NexStaging} from "../contracts/NexStaging.sol";
import {MockERC20} from "../test/foundry/mocks/MockERC20.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract DeployNexStaging is Script {
    function run() external {
        address deployer = vm.envAddress("DEPLOYER");
        vm.startBroadcast(deployer);

        MockERC20 nexLabsToken = new MockERC20("NexLabs", "NXL");
        MockERC20 indexToken1 = new MockERC20("Index Token 1", "IDX1");
        MockERC20 indexToken2 = new MockERC20("Index Token 2", "IDX2");

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

        ERC1967Proxy proxy = new ERC1967Proxy(address(nexStagingImplementation), data);

        // NexStaging nexStaging = NexStaging(address(proxy));

        vm.stopBroadcast();

        // Output the addresses
        console.log("NexStaging Proxy deployed to:", address(proxy));
        console.log("NexLabsToken deployed to:", address(nexLabsToken));
        console.log("IndexToken1 deployed to:", address(indexToken1));
        console.log("IndexToken2 deployed to:", address(indexToken2));
    }
}
