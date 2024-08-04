// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {CalculationHelper} from "./libraries/CalculationHelper.sol";

contract NexStaging {
    using SafeERC20 for IERC20;

    IERC20 public nexLabs;
    uint256 public feePercent;

    uint176 private _nextId = 1;

    struct StakePositions {
        address owner;
        address stakeToken;
        address rewardToken;
        uint256 stakeAmount;
        uint256 rewardEarned;
        uint256 apy;
        uint256 startTime;
        bool autoCompound;
    }

    mapping(address => uint256) public tokensAPY;
    mapping(address => uint256) public numberOfStakersByTokenAddress;
    mapping(uint256 => StakePositions) private _positions;

    event Staked(
        uint256 indexed positionId,
        address indexed user,
        address token,
        address rewardToken,
        uint256 amount,
        bool autoCompound,
        uint256 timestamp
    );
    event StakedIncreased(
        uint256 indexed positionId, address indexed user, address token, uint256 amount, uint256 timestamp
    );
    event UnStaked(
        uint256 indexed positionId,
        address indexed user,
        address token,
        uint256 amountUstaked,
        uint256 rewardAmountUnstaked,
        uint256 timestamp
    );
    event RewardWithdrawn(uint256 indexed positionId, address indexed user, uint256 amount, uint256 timestamp);

    constructor(
        address _nexLabsAddress,
        address[] memory _tokenAddresses,
        uint256[] memory _tokenAPYs,
        uint256 _feePercent
    ) {
        require(_tokenAddresses.length == _tokenAPYs.length, "Mismatched token and APY lengths");
        nexLabs = IERC20(_nexLabsAddress);
        feePercent = _feePercent;

        for (uint256 i = 0; i < _tokenAddresses.length; i++) {
            tokensAPY[_tokenAddresses[i]] = _tokenAPYs[i];
        }
    }

    function positions(uint256 positionId)
        external
        view
        returns (
            address owner,
            address stakeToken,
            address rewardToken,
            uint256 stakeAmount,
            uint256 rewardEarned,
            uint256 apy,
            uint256 startTime,
            bool autoCompound
        )
    {
        StakePositions memory position = _positions[positionId];
        return (
            position.owner,
            position.stakeToken,
            position.rewardToken,
            position.stakeAmount,
            position.rewardEarned,
            position.apy,
            position.startTime,
            position.autoCompound
        );
    }

    function stake(address tokenAddress, address rewardToken, uint256 amount, bool autoCompound)
        external
        returns (uint256 positionId)
    {
        require(tokensAPY[tokenAddress] != 0, "Token not supported for staking.");
        require(amount > 0, "Staking amount must be greater than zero.");
        require(address(nexLabs) == rewardToken || tokenAddress == rewardToken, "Invalid reward token.");

        uint256 apy = tokensAPY[tokenAddress];
        (uint256 fee, uint256 amountAfterFee) = CalculationHelper.calculateAmountAfterFeeAndFee(amount, feePercent);

        IERC20 token = IERC20(tokenAddress);
        token.safeTransferFrom(msg.sender, address(this), amountAfterFee);
        token.safeTransferFrom(msg.sender, address(this), fee);

        positionId = _nextId++;

        _positions[positionId] = StakePositions({
            owner: msg.sender,
            stakeToken: tokenAddress,
            rewardToken: rewardToken,
            stakeAmount: amountAfterFee,
            rewardEarned: 0,
            apy: apy,
            startTime: block.timestamp,
            autoCompound: autoCompound
        });

        numberOfStakersByTokenAddress[tokenAddress] += 1;

        emit Staked(positionId, msg.sender, tokenAddress, rewardToken, amountAfterFee, autoCompound, block.timestamp);
    }

    function increaseStakeAmount(uint256 positionId, uint256 amount) external {
        StakePositions storage position = _positions[positionId];
        require(position.owner == msg.sender, "Only owner can increase the staked amount!");
        require(amount > 0, "Increase amount must be greater than zero.");

        (uint256 fee, uint256 amountAfterFee) = CalculationHelper.calculateAmountAfterFeeAndFee(amount, feePercent);

        IERC20 token = IERC20(position.stakeToken);
        token.safeTransferFrom(msg.sender, address(this), amountAfterFee);
        token.safeTransferFrom(msg.sender, address(this), fee);

        uint256 reward = CalculationHelper.calculateReward(position);
        position.stakeAmount += amountAfterFee;
        position.rewardEarned += reward;
        position.startTime = block.timestamp;

        emit StakedIncreased(positionId, msg.sender, position.stakeToken, amountAfterFee, block.timestamp);
    }

    function unStake(uint256 positionId) external {
        StakePositions storage position = _positions[positionId];
        require(position.owner == msg.sender, "You are not the owner of this position!");
        require(position.stakeAmount > 0, "No stake amount to unstake.");

        uint256 rewardAmount = position.rewardEarned + CalculationHelper.calculateReward(position);
        (uint256 fee, uint256 amountAfterFee) =
            CalculationHelper.calculateAmountAfterFeeAndFee(position.stakeAmount, feePercent);

        if (position.stakeToken == position.rewardToken) {
            uint256 totalAmount = amountAfterFee + rewardAmount;
            IERC20(position.stakeToken).safeTransfer(msg.sender, totalAmount);
            IERC20(position.stakeToken).safeTransfer(address(this), fee);
        } else {
            IERC20(position.stakeToken).safeTransfer(msg.sender, amountAfterFee);
            IERC20(position.rewardToken).safeTransfer(msg.sender, rewardAmount);
            IERC20(position.stakeToken).safeTransfer(address(this), fee);
        }

        numberOfStakersByTokenAddress[position.stakeToken] -= 1;

        emit UnStaked(positionId, msg.sender, position.stakeToken, amountAfterFee, rewardAmount, block.timestamp);

        delete _positions[positionId];
    }

    function withdrawReward(uint256 positionId) external {
        StakePositions storage position = _positions[positionId];
        require(position.owner == msg.sender, "You are not the owner of this position");
        uint256 rewardAmount = position.rewardEarned + CalculationHelper.calculateReward(position);

        if (position.autoCompound) {
            position.stakeAmount += rewardAmount;
        } else {
            IERC20(position.rewardToken).safeTransfer(msg.sender, rewardAmount);
        }

        position.rewardEarned = 0;
        position.startTime = block.timestamp;

        emit RewardWithdrawn(positionId, msg.sender, rewardAmount, block.timestamp);
    }
}
