// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

contract NexStagingV2 is Initializable, OwnableUpgradeable, UUPSUpgradeable {
    using SafeERC20 for IERC20;

    // ERC20 token used for rewards
    IERC20 public nexLabs;
    // Fee percentage for staking operations
    uint256 public feePercent;

    // Counter for generating unique position IDs
    uint256 private _nextId;

    /// @notice Struct to hold staking position details
    struct StakePosition {
        address owner; // Owner of the stake
        address stakeToken; // Token being staked
        address rewardToken; // Token given as reward
        uint256 stakeAmount; // Amount of tokens staked
        uint256 rewardEarned; // Amount of rewards earned
        uint256 apy; // Annual Percentage Yield // @audit should decrease the type number from 256
        uint256 startTime; // Start time of the staking
        bool autoCompound; // Whether rewards are auto-compounded
    }

    // Mapping to store APY for each token
    mapping(address => uint256) public tokensAPY;
    // Mapping to track number of stakers per token
    mapping(address => uint256) public numberOfStakersByTokenAddress;
    // Mapping to store staking positions by ID
    mapping(uint256 => StakePosition) private _positions;

    /// @notice Event emitted when tokens are staked
    /// @param positionId ID of the staking position
    /// @param user Address of the user staking the tokens
    /// @param token Address of the token being staked
    /// @param rewardToken Address of the token given as reward
    /// @param amount Amount of tokens staked
    /// @param autoCompound Whether rewards are auto-compounded
    /// @param timestamp Timestamp when the staking occurred
    event Staked(
        uint256 indexed positionId,
        address indexed user,
        address token,
        address rewardToken,
        uint256 amount,
        bool autoCompound,
        uint256 timestamp
    );

    /// @notice Event emitted when stake amount is increased
    /// @param positionId ID of the staking position
    /// @param user Address of the user increasing the stake
    /// @param token Address of the token being staked
    /// @param amount Amount of tokens added to the stake
    /// @param timestamp Timestamp when the stake increase occurred
    event StakedIncreased(
        uint256 indexed positionId, address indexed user, address token, uint256 amount, uint256 timestamp
    );

    /// @notice Event emitted when tokens are unstaked
    /// @param positionId ID of the staking position
    /// @param user Address of the user unstaking the tokens
    /// @param token Address of the token being unstaked
    /// @param amountUstaked Amount of tokens unstaked
    /// @param rewardAmountUnstaked Amount of reward tokens unstaked
    /// @param timestamp Timestamp when the unstaking occurred
    event UnStaked(
        uint256 indexed positionId,
        address indexed user,
        address token,
        uint256 amountUstaked,
        uint256 rewardAmountUnstaked,
        uint256 timestamp
    );

    /// @notice Event emitted when rewards are withdrawn
    /// @param positionId ID of the staking position
    /// @param user Address of the user withdrawing the rewards
    /// @param amount Amount of reward tokens withdrawn
    /// @param timestamp Timestamp when the reward withdrawal occurred
    event RewardWithdrawn(uint256 indexed positionId, address indexed user, uint256 amount, uint256 timestamp);

    /// @custom:oz-upgrades-from constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address _nexLabsAddress,
        address[] memory _tokenAddresses,
        uint256[] memory _tokenAPYs,
        uint256 _feePercent
    ) public initializer {
        require(_tokenAddresses.length == _tokenAPYs.length, "Mismatched token and APY lengths");

        __Ownable_init(msg.sender);
        __UUPSUpgradeable_init();

        nexLabs = IERC20(_nexLabsAddress);
        feePercent = _feePercent;
        _nextId = 1;

        for (uint256 i = 0; i < _tokenAddresses.length; i++) {
            tokensAPY[_tokenAddresses[i]] = _tokenAPYs[i];
        }
    }

    /// @notice Function to get details of a staking position
    /// @param positionId ID of the staking position
    /// @return positionOwner Address of the position owner
    /// @return stakeToken Address of the token being staked
    /// @return rewardToken Address of the token given as reward
    /// @return stakeAmount Amount of tokens staked
    /// @return rewardEarned Amount of rewards earned
    /// @return apy Annual Percentage Yield
    /// @return startTime Start time of the staking
    /// @return autoCompound Whether rewards are auto-compounded
    function positions(uint256 positionId)
        external
        view
        returns (
            address positionOwner,
            address stakeToken,
            address rewardToken,
            uint256 stakeAmount,
            uint256 rewardEarned,
            uint256 apy,
            uint256 startTime,
            bool autoCompound
        )
    {
        StakePosition memory position = _positions[positionId];
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

    /// @notice Function to stake tokens
    /// @param tokenAddress Address of the token to be staked
    /// @param rewardToken Address of the token to be given as reward
    /// @param amount Amount of tokens to be staked
    /// @param autoCompound Boolean indicating if rewards should be auto-compounded
    /// @return positionId ID of the created staking position
    function stake(address tokenAddress, address rewardToken, uint256 amount, bool autoCompound)
        external
        returns (uint256 positionId)
    {
        require(tokensAPY[tokenAddress] != 0, "Token not supported for staking.");
        require(amount > 0, "Staking amount must be greater than zero.");
        require(address(nexLabs) == rewardToken || tokenAddress == rewardToken, "Invalid reward token.");

        uint256 apy = tokensAPY[tokenAddress];
        (uint256 fee, uint256 amountAfterFee) = calculateAmountAfterFeeAndFee(amount, feePercent);

        // Transfer the staking amount and fee from the user to the contract
        IERC20 token = IERC20(tokenAddress);
        token.safeTransferFrom(msg.sender, address(this), amountAfterFee);
        token.safeTransferFrom(msg.sender, address(this), fee);

        positionId = _nextId++;

        // Create a new staking position
        _positions[positionId] = StakePosition({
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

    /// @notice Function to increase the stake amount
    /// @param positionId ID of the staking position
    /// @param amount Amount of tokens to be added to the stake
    function increaseStakeAmount(uint256 positionId, uint256 amount) external {
        StakePosition storage position = _positions[positionId];
        require(position.owner == msg.sender, "Only owner can increase the staked amount!");
        require(amount > 0, "Increase amount must be greater than zero.");
        uint256 apy = tokensAPY[position.stakeToken];

        (uint256 fee, uint256 amountAfterFee) = calculateAmountAfterFeeAndFee(amount, feePercent);

        // Transfer the additional staking amount and fee from the user to the contract
        IERC20 token = IERC20(position.stakeToken);
        token.safeTransferFrom(msg.sender, address(this), amountAfterFee);
        token.safeTransferFrom(msg.sender, address(this), fee);

        // Calculate and update the reward
        uint256 reward = calculateReward(position, apy);
        position.stakeAmount += amountAfterFee;
        position.rewardEarned += reward;
        position.startTime = block.timestamp;

        emit StakedIncreased(positionId, msg.sender, position.stakeToken, amountAfterFee, block.timestamp);
    }

    /// @notice Function to unstake tokens
    /// @param positionId ID of the staking position
    function unStake(uint256 positionId) external {
        StakePosition storage position = _positions[positionId];
        require(position.owner == msg.sender, "You are not the owner of this position!");
        require(position.stakeAmount > 0, "No stake amount to unstake.");
        uint256 apy = tokensAPY[position.stakeToken];

        // Calculate the total reward amount
        uint256 rewardAmount = position.rewardEarned + calculateReward(position, apy);

        (, uint256 rewardAmountAfterFee) = calculateAmountAfterFeeAndFee(rewardAmount, feePercent);

        // Transfer the unstaked amount and rewards to the user, and the fee to the contract
        if (position.stakeToken == position.rewardToken) {
            uint256 totalAmount = position.stakeAmount + rewardAmountAfterFee;
            IERC20(position.stakeToken).safeTransfer(msg.sender, totalAmount);
        } else {
            IERC20(position.stakeToken).safeTransfer(msg.sender, position.stakeAmount);
            IERC20(position.rewardToken).safeTransfer(msg.sender, rewardAmountAfterFee);
        }

        numberOfStakersByTokenAddress[position.stakeToken] -= 1;

        emit UnStaked(
            positionId, msg.sender, position.stakeToken, position.stakeAmount, rewardAmountAfterFee, block.timestamp
        );

        // Delete the position after unstaking
        delete _positions[positionId];
    }

    /// @notice Function to withdraw rewards
    /// @param positionId ID of the staking position
    function withdrawReward(uint256 positionId) external {
        StakePosition storage position = _positions[positionId];
        require(position.owner == msg.sender, "You are not the owner of this position");
        uint256 apy = tokensAPY[position.stakeToken];
        uint256 rewardAmount = position.rewardEarned + calculateReward(position, apy);

        // Auto-compound the reward if enabled, otherwise transfer to the user
        if (position.autoCompound) {
            position.stakeAmount += rewardAmount;
        } else {
            IERC20(position.rewardToken).safeTransfer(msg.sender, rewardAmount);
        }

        position.rewardEarned = 0;
        position.startTime = block.timestamp;

        emit RewardWithdrawn(positionId, msg.sender, rewardAmount, block.timestamp);
    }

    function calculateReward(StakePosition storage position, uint256 apy) internal view returns (uint256) {
        uint256 duration = block.timestamp - position.startTime;
        uint256 dailyRate = apy * 1e18 / 10;

        uint256 interval = 10 days; // Set the interval to 10 days
        uint256 intervalRate = dailyRate * 10; // Adjust the rate for the interval

        if (position.autoCompound) {
            uint256 compoundedStakeAmount = position.stakeAmount;
            uint256 numberOfIntervals = duration / interval;

            for (uint256 i = 0; i < numberOfIntervals; i++) {
                uint256 interest = (compoundedStakeAmount * intervalRate) / 1e20;
                compoundedStakeAmount += interest;
            }

            // Calculate remaining days that don't fit into the full interval
            uint256 remainingDays = (duration % interval) / 1 days;
            uint256 remainingInterest = (compoundedStakeAmount * dailyRate * remainingDays) / 1e20;
            compoundedStakeAmount += remainingInterest;

            return compoundedStakeAmount - position.stakeAmount;
        } else {
            return (position.stakeAmount * dailyRate * duration / 1 days) / 1e20;
        }
    }

    function calculateAmountAfterFeeAndFee(uint256 amount, uint256 feePercent)
        internal
        pure
        returns (uint256, uint256)
    {
        uint256 fee = (amount * feePercent) / 10000;
        uint256 amountAfterFee = amount - fee;
        return (fee, amountAfterFee);
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    function version() public view returns (uint256) {
        return 2;
    }
}
