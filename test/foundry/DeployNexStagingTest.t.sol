// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import {MockERC20} from "../../test/foundry/mocks/MockERC20.sol";
import {DeployNexStaging} from "../../script/DeployNexStaging.s.sol";
import {NexStaging} from "../../contracts/NexStaging.sol";

contract DeployNexStagingTest is Test {
    DeployNexStaging deployNexStaging;
    NexStaging nexStaging;
    MockERC20 nexLabsToken;
    MockERC20 indexToken1;
    MockERC20 indexToken2;
    ProxyAdmin proxyAdmin;

    function setUp() public {
        deployNexStaging = new DeployNexStaging();
    }

    function testDeployment() public {
        deployNexStaging.run();

        // Fetch the deployed contract addresses
        nexStaging = NexStaging(deployNexStaging.nexStaging());
        nexLabsToken = MockERC20(deployNexStaging.nexLabsToken());
        indexToken1 = MockERC20(deployNexStaging.indexToken1());
        indexToken2 = MockERC20(deployNexStaging.indexToken2());
        proxyAdmin = ProxyAdmin(deployNexStaging.proxyAdmin());

        // Check if the contracts are deployed correctly
        assert(address(nexStaging) != address(0));
        assert(address(nexLabsToken) != address(0));
        assert(address(indexToken1) != address(0));
        assert(address(indexToken2) != address(0));
        assert(address(proxyAdmin) != address(0));

        // Verify the initialization of NexStaging contract
        address nexLabsTokenAddress = address(nexStaging.nexLabs());
        assertEq(nexLabsTokenAddress, address(nexLabsToken));

        // Check the tokens and their APYs
        uint256 nexLabsTokenAPY = nexStaging.tokensAPY(address(nexLabsToken));
        uint256 indexToken1APY = nexStaging.tokensAPY(address(indexToken1));
        uint256 indexToken2APY = nexStaging.tokensAPY(address(indexToken2));

        assertEq(nexLabsTokenAPY, 15);
        assertEq(indexToken1APY, 10);
        assertEq(indexToken2APY, 20);

        // Verify the fee percentage
        uint256 feePercent = nexStaging.feePercent();
        assertEq(feePercent, 3);
    }
}
