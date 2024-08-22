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
    }
    // uint256 weight;

    struct StakePositions {
        address owner;
        address vault;
        uint256 stakeAmount;
        uint256 shares;
        uint256 startTime;
    }

    // mapping(uint256 => Pools) public pools;
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

        for (uint256 i = 0; i < _tokenAddress.length; i++) {
            poolTokens.push(_tokenAddress[i]);
            pools[_tokenAddress[i]] = Pools({vault: _tokenAddress[i], totalStaked: 0});
        }
    }

    function positions(uint256 positionId)
        external
        view
        returns (address positionOwner, address stakeToken, uint256 stakeAmount, uint256 shares, uint256 startTime)
    {
        StakePositions memory position = _positions[positionId];
        return (position.owner, position.vault, position.stakeAmount, position.shares, position.startTime);
    }

    function stake(address tokenAddress, uint256 amount) external returns (uint256 positionId) {
        require(tokenAddress != address(0), "Token not supported for staking.");
        require(amount > 0, "Staking amount must be greater than zero.");

        (uint256 fee, uint256 amountAfterFee) = CalculationHelper.calculateAmountAfterFeeAndFee(amount, feePercent);

        IERC20 token = IERC20(tokenAddress);
        token.safeTransferFrom(msg.sender, address(this), amountAfterFee);
        token.safeTransferFrom(msg.sender, address(this), fee); // should transfer to the owner

        positionId = _nextId++;

        _positions[positionId] = StakePositions({
            owner: msg.sender,
            vault: tokenAddress,
            stakeAmount: amountAfterFee,
            shares: 0, // @audit
            startTime: block.timestamp
        });

        // Update the total staked in the corresponding pool
        pools[tokenAddress].totalStaked += amountAfterFee;
    }

    function unstake(uint256 positionId, address rewardToken) external {
        StakePositions storage position = _positions[positionId];
        require(position.owner == msg.sender, "You are not the owner of this position.");
        require(position.stakeAmount > 0, "No stake amount to unstake.");

        // (uint256 fee,uint256 rewardAmountAfterFee) = CalculationHelper.calculateAmountAfterFeeAndFee();

        if (position.vault == rewardToken) {
            // IERC20(position.vault).safeTransfer(msg.sender, rewardAmountAfterFee);
        }

        // emit UnStaked(
        //     positionId, msg.sender, position.stakeToken, position.stakeAmount, rewardAmountAfterFee, block.timestamp
        // );

        // Delete the position after unstaking
        delete _positions[positionId];
    }

    function calculateWeightOfPools() external view returns (uint256[] memory) {
        uint256 totalStakedAcrossAllPools = 0;
        uint256[] memory weights = new uint256[](poolTokens.length);

        for (uint256 i = 0; i < poolTokens.length; i++) {
            totalStakedAcrossAllPools += pools[poolTokens[i]].totalStaked;
        }

        for (uint256 i = 0; i < poolTokens.length; i++) {
            weights[i] = (pools[poolTokens[i]].totalStaked * 1e18) / totalStakedAcrossAllPools;
        }

        return weights;
    }
}
