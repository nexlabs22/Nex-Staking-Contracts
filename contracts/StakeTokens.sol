// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/interfaces/IERC20.sol";

contract StakeTokens {
    using SafeERC20 for IERC20;

    IERC20 public nexLabs;
    IERC20 public usdc;
    IERC20 public dinariUsdc;

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
    event UnStaked(uint256 indexed positionId, address indexed user, address token, uint256 amount, uint256 timestamp);
    event RewardWithdrawn(uint256 indexed positionId, address indexed user, uint256 amount, uint256 timestamp);

    constructor(
        address _nexLabsAddress,
        address _usdcAddress,
        address _dinariUsdcAddress,
        uint256 _nexLabsAPY,
        uint256 _usdcAPY,
        uint256 _dinariUsdcAPY
    ) {
        nexLabs = IERC20(_nexLabsAddress);
        usdc = IERC20(_usdcAddress);
        dinariUsdc = IERC20(_dinariUsdcAddress);

        tokensAPY[_nexLabsAddress] = _nexLabsAPY;
        tokensAPY[_usdcAddress] = _usdcAPY;
        tokensAPY[_dinariUsdcAddress] = _dinariUsdcAPY;
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
        IERC20 token = IERC20(tokenAddress);
        token.safeTransferFrom(msg.sender, address(this), amount);

        positionId = _nextId++;

        _positions[positionId] = StakePositions({
            owner: msg.sender,
            stakeToken: tokenAddress,
            rewardToken: rewardToken,
            stakeAmount: amount,
            rewardEarned: 0,
            apy: apy,
            startTime: block.timestamp,
            autoCompound: autoCompound
        });

        numberOfStakersByTokenAddress[tokenAddress] += 1;

        emit Staked(positionId, msg.sender, tokenAddress, rewardToken, amount, autoCompound, block.timestamp);
    }

    function increaseStakeAmount(uint256 positionId, uint256 amount) external {
        StakePositions storage position = _positions[positionId];
        require(position.owner == msg.sender, "Only owner can increase the staked amount!");
        require(amount > 0, "Increase amount must be greater than zero.");

        IERC20 token = IERC20(position.stakeToken);
        token.safeTransferFrom(msg.sender, address(this), amount);

        uint256 reward = calculateReward(position);
        position.stakeAmount += amount;
        position.rewardEarned += reward;
        position.startTime = block.timestamp;

        emit StakedIncreased(positionId, msg.sender, position.stakeToken, amount, block.timestamp);
    }

    function unStake(uint256 positionId) external {
        StakePositions storage position = _positions[positionId];
        require(position.stakeAmount > 0, "No stake amount to unstake.");

        uint256 rewardAmount = position.rewardEarned + calculateReward(position);

        if (position.stakeToken == position.rewardToken) {
            uint256 totalAmount = position.stakeAmount + rewardAmount;
            IERC20(position.stakeToken).safeTransfer(msg.sender, totalAmount);
        } else {
            IERC20(position.stakeToken).safeTransfer(msg.sender, position.stakeAmount);
            IERC20(position.rewardToken).safeTransfer(msg.sender, rewardAmount);
        }

        numberOfStakersByTokenAddress[position.stakeToken] -= 1;

        emit UnStaked(positionId, msg.sender, position.stakeToken, position.stakeAmount, block.timestamp);

        delete _positions[positionId];
    }

    function withdrawReward(uint256 positionId) external {
        StakePositions storage position = _positions[positionId];
        require(position.owner == msg.sender, "You are not the owner of this position");
        uint256 rewardAmount = position.rewardEarned + calculateReward(position);
        require(rewardAmount > 0, "You did not earn any rewards!");

        if (position.autoCompound) {
            position.stakeAmount += rewardAmount;
        } else {
            IERC20(position.rewardToken).safeTransfer(msg.sender, rewardAmount);
        }

        position.rewardEarned = 0;
        position.startTime = block.timestamp;

        emit RewardWithdrawn(positionId, msg.sender, rewardAmount, block.timestamp);
    }

    function calculateReward(StakePositions storage position) internal view returns (uint256) {
        uint256 duration = block.timestamp - position.startTime;
        uint256 periodCount = duration / 365 days;

        if (periodCount > 0 && position.autoCompound) {
            uint256 compoundedStakeAmount = position.stakeAmount;
            for (uint256 i = 0; i < periodCount; i++) {
                uint256 reward = (compoundedStakeAmount * position.apy) / 100;
                compoundedStakeAmount += reward;
            }
            return compoundedStakeAmount - position.stakeAmount;
        } else {
            return (position.stakeAmount * position.apy * duration) / (365 days * 100);
        }
    }
}
