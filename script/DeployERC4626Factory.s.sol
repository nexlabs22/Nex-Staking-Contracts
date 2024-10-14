// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import "../contracts/factory/ERC4626Factory.sol";

contract DeployERC4626Factory is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        address[] memory indexTokensAddresses = getIndexTokens();

        vm.startBroadcast(deployerPrivateKey);

        ERC4626Factory factory = new ERC4626Factory();

        factory.initialize(indexTokensAddresses);

        console.log("ERC4626Factory deployed at:", address(factory));

        console.log("Msg Sender: ", msg.sender);

        vm.stopBroadcast();
    }

    function getIndexTokens() internal pure returns (address[] memory) {
        address[] memory indexTokens = new address[](4);
        indexTokens[0] = 0x5Cd93F5C4ECE56b7faC31ABb3c1933f6a6FE7182; // ANFI
        indexTokens[1] = 0xeCBa11929312420414b6a9a70f206f90789f3069; // ARBEI
        indexTokens[2] = 0x1e881F3c8bF7A161E884B4D86Fe8810290d3095D; // MAG7
        indexTokens[3] = 0xA16FEC5964aDE6563624C16d0b2EDeC95bEEB63b; // CRYPTO5
        return indexTokens;
    }
}
