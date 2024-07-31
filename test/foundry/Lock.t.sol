// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import "forge-std/Test.sol";
import "../../contracts/Lock.sol";

contract LockTestis is Test {
    Lock public lock;
    uint public unlockTime;

    function setUp() public {
        unlockTime = block.timestamp + 30 days;
        lock = new Lock{value: 1e18}(unlockTime);
    }

    function testLock() public {
        assertEq(lock.unlockTime(), unlockTime);
    }
}