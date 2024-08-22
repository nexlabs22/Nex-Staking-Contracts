// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

import {CalculationHelper} from "./libraries/CalculationHelper.sol";

contract NexStaging is OwnableUpgradeable {
    using SafeERC20 for IERC20;

    IERC20 public nexLabsToken;
    address[] public poolTokens;
    uint256 public feePercent;
    uint256 private _nextId;

    struct Pools {
        address vault;
        uint256 totalStaked;
        uint256 weight;
    }

    struct StakePositions {
        address owner;
        address vault;
        uint256 stakeAmount;
        uint256 shares;
        uint256 startTime;
    }

    mapping(address => Pools) public pools;
    mapping(uint256 => StakePositions) private _positions;

    event Staked(
        uint256 indexed positionId, address indexed user, address indexed pool, uint256 amount, uint256 timestamp
    );
    event StakeIncreased(
        uint256 indexed positionId, address indexed user, address indexed vault, uint256 amount, uint256 timestamp
    );
    event UnStaked(
        uint256 indexed positionId, address indexed user, address indexed vault, uint256 amount, uint256 timestamp
    );

    constructor(address _nexLabsAddress, address[] memory _tokenAddress, uint256 _feePercent) {
        nexLabsToken = IERC20(_nexLabsAddress);
        feePercent = _feePercent;
        _nextId = 1;

        // for (uint256 i = 0; i < _tokenAddress.length; i++) {
        //     ERC4626 token = new ERC4626(IERC20(_tokenAddress[i]));
        // }
    }

    function positions(uint256 positionId)
        external
        view
        returns (address positionOwner, address stakeToken, uint256 stakeAmount, uint256 shares, uint256 startTime)
    {
        StakePositions memory position = _positions[positionId];
        return (position.owner, position.vault, position.stakeAmount, position.shares, position.startTime);
    }

    function stake(address tokenAddress, uint256 amount) external returns (uint256 positionId) {}

    function unstake(uint256 positionId, address rewardToken) external {}
}
