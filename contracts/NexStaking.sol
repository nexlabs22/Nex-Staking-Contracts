// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/contracts/access/OwnableUpgradeable.sol";
import {ISwapRouter} from "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import {ReentrancyGuardUpgradeable} from
    "@openzeppelin/contracts-upgradeable/contracts/utils/ReentrancyGuardUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/contracts/proxy/utils/Initializable.sol";

import {ERC4626Factory} from "./factory/ERC4626Factory.sol";
import {CalculationHelpers} from "./libraries/CalculationHelpers.sol";
import {SwapHelpers} from "./libraries/SwapHelpers.sol";
import {IWETH9} from "./interfaces/IWETH9.sol";

contract NexStaking is Initializable, OwnableUpgradeable, ReentrancyGuardUpgradeable {
    using SafeERC20 for IERC20;

    ERC4626Factory public erc4626Factory;
    ISwapRouter public routerV3;
    IWETH9 public weth;

    address[] public poolTokensAddresses;
    address[] public rewardTokensAddresses;
    uint8 public feePercent;

    struct StakePositions {
        address owner;
        address stakeToken;
        address vaultToken;
        uint256 stakeAmount;
        uint256 startTime;
    }

    mapping(address => uint8) public tokenSwapVersion;
    mapping(address => bool) public supportedTokens;
    mapping(address => bool) public supportedRewardTokens;
    mapping(address => uint256) public numberOfStakersByTokenAddress;
    mapping(address => mapping(address => StakePositions)) public positions;

    event Staked(
        address indexed user,
        address indexed tokenAddress,
        uint256 indexed amount,
        uint256 totalStakedAmount,
        uint256 poolSize,
        address vault,
        uint256 sharesMinted,
        uint256 timestamp
    );

    event Unstaked(
        address indexed user,
        address indexed tokenAddress,
        uint256 indexed amount,
        uint256 totalStakedAmount,
        uint256 rewardAmount,
        uint256 poolSize,
        address vault,
        uint256 sharesBurned,
        uint256 timestamp
    );

    event RewardTokensSwapped(
        address indexed tokenIn, address indexed tokenOut, uint256 amountIn, uint256 amountOut, address user
    );

    event RewardTokensUpdated(address[] newRewardTokens);

    event PoolTokensUpdated(address[] newPoolTokens);

    function initialize(
        address[] memory _indexTokensAddresses,
        address[] memory _rewardTokensAddresses,
        uint8[] memory _swapVersions,
        address _erc4626Factory,
        address _uniswapV3Router,
        address _weth,
        uint8 _feePercent
    ) public initializer {
        __Ownable_init(msg.sender);
        __ReentrancyGuard_init();

        require(_erc4626Factory != address(0), "Invalid address for _erc4626Factory");
        require(_weth != address(0), "Invalid address for _weth");

        erc4626Factory = ERC4626Factory(_erc4626Factory);
        routerV3 = ISwapRouter(_uniswapV3Router);
        weth = IWETH9(_weth);
        feePercent = _feePercent;

        require(
            _indexTokensAddresses.length == _swapVersions.length,
            "Index tokens and swap versions must have the same length"
        );

        _initializePools(_indexTokensAddresses, _rewardTokensAddresses, _swapVersions);
    }

    function stake(address tokenAddress, uint256 amount) external nonReentrant {
        StakePositions storage position = positions[msg.sender][tokenAddress];
        require(tokenAddress != address(0), "The token address is zero address");
        require(supportedTokens[tokenAddress], "Token not support for staking.");
        require(amount > 0, "Staking amount must be greater than zero.");

        (uint256 fee, uint256 amountAfterFee) = calculateAmountAfterFeeAndFee(amount);
        IERC20(tokenAddress).safeTransferFrom(msg.sender, owner(), fee);

        address vault = erc4626Factory.tokenAddressToVaultAddress(tokenAddress);

        IERC20(tokenAddress).approve(vault, amountAfterFee);
        IERC20(tokenAddress).safeTransferFrom(msg.sender, address(this), amountAfterFee);

        uint256 shares = ERC4626(vault).deposit(amountAfterFee, msg.sender);

        uint256 totalStakedAmount = 0;
        if (position.stakeAmount > 0) {
            position.stakeAmount += amountAfterFee;
            totalStakedAmount = position.stakeAmount;
        } else {
            positions[msg.sender][tokenAddress] = StakePositions({
                owner: msg.sender,
                stakeToken: tokenAddress,
                vaultToken: vault,
                stakeAmount: amountAfterFee,
                startTime: block.timestamp
            });

            numberOfStakersByTokenAddress[tokenAddress] += 1;

            totalStakedAmount = amountAfterFee;
        }

        uint256 poolSize = ERC4626(vault).totalAssets();

        emit Staked(
            msg.sender, tokenAddress, amountAfterFee, totalStakedAmount, poolSize, vault, shares, block.timestamp
        );
    }

    function unstake(address tokenAddress, address rewardTokenAddress, uint256 unstakeAmount) external nonReentrant {
        StakePositions storage position = positions[msg.sender][tokenAddress];
        require(position.owner == msg.sender, "You are not the owner of this position.");
        require(
            rewardTokenAddress == tokenAddress || supportedRewardTokens[rewardTokenAddress], "Unsupported reward token."
        );
        require(position.stakeAmount > 0, "No stake amount to unstake.");
        require(unstakeAmount > 0 && unstakeAmount <= position.stakeAmount, "Invalid amount to unstake.");

        address vault = erc4626Factory.tokenAddressToVaultAddress(tokenAddress);

        uint256 totalUserStake = position.stakeAmount;
        uint256 unstakePercentage = calculateUnstakePercentage(unstakeAmount, totalUserStake);

        uint256 sharesToRedeem = calculateSharesToRedeem(vault, unstakePercentage);

        uint256 redeemableTokens = ERC4626(vault).redeem(sharesToRedeem, address(this), msg.sender);

        uint256 stakedPortion = redeemableTokens < unstakeAmount ? redeemableTokens : unstakeAmount;
        uint256 totalReward = redeemableTokens > stakedPortion ? redeemableTokens - stakedPortion : 0;

        position.stakeAmount -= stakedPortion;

        IERC20(tokenAddress).safeTransfer(msg.sender, stakedPortion);

        uint256 fee = 0;
        uint256 rewardAfterFee = 0;

        if (totalReward > 0) {
            (fee, rewardAfterFee) = calculateAmountAfterFeeAndFee(totalReward);

            if (fee > 0) {
                IERC20(tokenAddress).safeTransfer(owner(), fee);
            }

            if (tokenAddress == rewardTokenAddress) {
                IERC20(tokenAddress).safeTransfer(msg.sender, rewardAfterFee);
            } else if (rewardAfterFee > 0) {
                address[] memory path;
                path = new address[](3);
                path[0] = tokenAddress;
                path[1] = address(weth);
                path[2] = rewardTokenAddress;

                uint256 swappedRewardAmount = SwapHelpers.swapIndexToReward(routerV3, path, rewardAfterFee, msg.sender);

                emit RewardTokensSwapped(
                    tokenAddress, rewardTokenAddress, rewardAfterFee, swappedRewardAmount, msg.sender
                );
            }
        }

        if (ERC4626(vault).balanceOf(msg.sender) == 0) {
            delete positions[msg.sender][tokenAddress];
            numberOfStakersByTokenAddress[tokenAddress] -= 1;
        }

        uint256 poolSize = ERC4626(vault).totalAssets();
        uint256 totalStaked = position.stakeAmount;

        emit Unstaked(
            msg.sender,
            tokenAddress,
            stakedPortion,
            totalStaked,
            rewardAfterFee,
            poolSize,
            vault,
            sharesToRedeem,
            block.timestamp
        );
    }

    function _setERC4626Factory(ERC4626Factory _erc4626Factory) external onlyOwner {
        erc4626Factory = _erc4626Factory;
    }

    function setFeePercent(uint8 newFeePercent) external onlyOwner {
        require(newFeePercent <= 100, "Fee percent must be between 0 and 100.");
        feePercent = newFeePercent;
    }

    function getUserShares(address user, address tokenAddress) public view returns (uint256) {
        address vault = erc4626Factory.tokenAddressToVaultAddress(tokenAddress);
        uint256 shares = ERC4626(vault).balanceOf(user);
        return shares;
    }

    function getPureRewardAmount(address tokenAddress, address userAddress, uint256 amount)
        public
        view
        returns (uint256)
    {
        StakePositions storage position = positions[userAddress][tokenAddress];
        uint256 totalUserStake = position.stakeAmount;

        require(totalUserStake > 0, "No stake amount to unstake.");
        require(amount > 0 && amount <= totalUserStake, "Invalid amount to unstake.");

        address vault = erc4626Factory.tokenAddressToVaultAddress(tokenAddress);
        uint256 unstakePercentage = calculateUnstakePercentage(amount, totalUserStake);
        uint256 sharesToRedeem = calculateSharesToRedeemForUser(vault, userAddress, unstakePercentage);
        uint256 redeemAmount = ERC4626(vault).previewRedeem(sharesToRedeem);
        uint256 rewardAmount = redeemAmount > amount ? redeemAmount - amount : 0;

        return rewardAmount;
    }

    function getSharesToRedeemAmount(address tokenAddress, address userAddress, uint256 amount)
        public
        view
        returns (uint256)
    {
        StakePositions storage position = positions[userAddress][tokenAddress];
        uint256 totalUserStake = position.stakeAmount;

        require(totalUserStake > 0, "No stake amount to unstake.");
        require(amount > 0 && amount <= totalUserStake, "Invalid amount to unstake.");

        address vault = erc4626Factory.tokenAddressToVaultAddress(tokenAddress);
        uint256 unstakePercentage = calculateUnstakePercentage(amount, totalUserStake);
        uint256 sharesToRedeem = calculateSharesToRedeemForUser(vault, userAddress, unstakePercentage);
        return sharesToRedeem;
    }

    function setRewardTokensAddresses(address[] memory _newRewardTokensAddresses) external onlyOwner {
        require(_newRewardTokensAddresses.length > 0, "New reward tokens array cannot be empty");
        rewardTokensAddresses = _newRewardTokensAddresses;
        for (uint256 i = 0; i < rewardTokensAddresses.length; i++) {
            supportedRewardTokens[rewardTokensAddresses[i]] = true;
        }

        emit RewardTokensUpdated(_newRewardTokensAddresses);
    }

    function setPoolTokensAddresses(address[] memory _newPoolTokensAddresses) external onlyOwner {
        require(_newPoolTokensAddresses.length > 0, "New pool tokens array cannot be empty");
        poolTokensAddresses = _newPoolTokensAddresses;
        for (uint256 i = 0; i < poolTokensAddresses.length; i++) {
            supportedTokens[poolTokensAddresses[i]] = true;
        }

        emit PoolTokensUpdated(_newPoolTokensAddresses);
    }

    function setRouterV3(ISwapRouter _routerV3) external onlyOwner {
        routerV3 = _routerV3;
    }

    function _initializePools(
        address[] memory _indexTokensAddresses,
        address[] memory _rewardTokensAddresses,
        uint8[] memory _swapVersions
    ) internal {
        for (uint256 i = 0; i < _indexTokensAddresses.length; i++) {
            supportedTokens[_indexTokensAddresses[i]] = true;
            tokenSwapVersion[_indexTokensAddresses[i]] = _swapVersions[i];
        }

        for (uint256 i = 0; i < _rewardTokensAddresses.length; i++) {
            supportedRewardTokens[_rewardTokensAddresses[i]] = true;
        }
        rewardTokensAddresses = _rewardTokensAddresses;
        poolTokensAddresses = _indexTokensAddresses;
    }

    function calculateAmountAfterFeeAndFee(uint256 amount)
        internal
        view
        returns (uint256 fee, uint256 amountAfterFee)
    {
        (fee, amountAfterFee) = CalculationHelpers.calculateAmountAfterFeeAndFee(amount, feePercent);
    }

    function calculateUnstakePercentage(uint256 unstakeAmount, uint256 totalUserStake)
        internal
        pure
        returns (uint256)
    {
        return (unstakeAmount * 1e18) / totalUserStake;
    }

    function calculateSharesToRedeem(address vault, uint256 unstakePercentage) internal view returns (uint256) {
        uint256 userShares = ERC4626(vault).balanceOf(msg.sender);
        return (userShares * unstakePercentage) / 1e18;
    }

    function calculateSharesToRedeemForUser(address vault, address userAddress, uint256 unstakePercentage)
        internal
        view
        returns (uint256)
    {
        uint256 userShares = ERC4626(vault).balanceOf(userAddress);
        return (userShares * unstakePercentage) / 1e18;
    }
}
