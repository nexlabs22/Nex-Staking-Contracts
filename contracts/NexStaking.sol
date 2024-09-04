// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/contracts/access/OwnableUpgradeable.sol";
import {ISwapRouter} from "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import {ReentrancyGuardUpgradeable} from
    "@openzeppelin/contracts-upgradeable/contracts/utils/ReentrancyGuardUpgradeable.sol";

import {ERC4626Factory} from "./factory/ERC4626Factory.sol";
import {CalculationHelpers} from "./libraries/CalculationHelpers.sol";
import {SwapHelpers} from "./libraries/SwapHelpers.sol";
import {IWETH9} from "./interfaces/IWETH9.sol";

contract NexStaking is OwnableUpgradeable, ReentrancyGuardUpgradeable {
    using SafeERC20 for IERC20;

    ERC4626Factory public erc4626Factory;
    ISwapRouter public routerV3;
    IWETH9 public weth;
    IERC20 public nexLabsToken;

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
    mapping(address => address) public tokenAddressToVaultAddress;
    mapping(address => uint256) public numberOfStakersByTokenAddress;
    mapping(address => mapping(address => StakePositions)) public _positions;

    event Staked(
        address indexed user,
        address indexed tokenAddress,
        uint256 indexed amount,
        address vault,
        uint256 shares,
        uint256 timestamp
    );

    event Unstaked(
        address indexed user,
        address indexed tokenAddress,
        uint256 indexed amount,
        address vault,
        uint256 shares,
        uint256 timestamp
    );

    event RewardTokensSwapped(
        address indexed tokenIn, address indexed tokenOut, uint256 amountIn, uint256 amountOut, address user
    );

    function initialize(
        address _nexLabsTokenAddress,
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

        require(_nexLabsTokenAddress != address(0), "Invalid address for _nexLabsAddress");
        require(_erc4626Factory != address(0), "Invalid address for _erc4626Factory");
        require(_weth != address(0), "Invalid address for _weth");

        erc4626Factory = ERC4626Factory(_erc4626Factory);
        routerV3 = ISwapRouter(_uniswapV3Router);
        weth = IWETH9(_weth);
        nexLabsToken = IERC20(_nexLabsTokenAddress);
        feePercent = _feePercent;

        _initializePools(_indexTokensAddresses, _rewardTokensAddresses, _swapVersions);
    }

    function stake(address tokenAddress, uint256 amount) external nonReentrant {
        StakePositions storage position = _positions[msg.sender][tokenAddress];
        require(tokenAddress != address(0) && supportedTokens[tokenAddress], "Token not supported for staking.");
        require(amount > 0, "Staking amount must be greater than zero.");

        (uint256 fee, uint256 amountAfterFee) = calculateAmountAfterFeeAndFee(amount);

        IERC20(tokenAddress).safeTransferFrom(msg.sender, owner(), fee);
        address vault = tokenAddressToVaultAddress[tokenAddress];
        uint256 shares = ERC4626(vault).deposit(amountAfterFee, msg.sender);

        if (position.stakeAmount > 0) {
            position.stakeAmount += amountAfterFee;
        } else {
            _positions[msg.sender][tokenAddress] = StakePositions({
                owner: msg.sender,
                stakeToken: tokenAddress,
                vaultToken: vault,
                stakeAmount: amountAfterFee,
                startTime: block.timestamp
            });

            numberOfStakersByTokenAddress[tokenAddress] += 1;
        }

        emit Staked(msg.sender, tokenAddress, amountAfterFee, vault, shares, block.timestamp);
    }

    function unstake(address tokenAddress, address rewardTokenAddress, uint256 amount) external nonReentrant {
        StakePositions storage position = _positions[msg.sender][tokenAddress];
        require(position.owner == msg.sender, "You are not the owner of this position.");
        require(
            supportedTokens[tokenAddress] == true && supportedRewardTokens[rewardTokenAddress] == true,
            "UnSupported Tokens"
        );
        require(position.stakeAmount > 0, "No stake amount to unstake.");
        require(amount > 0 && amount <= position.stakeAmount, "Invalid amount to unstake.");

        address vault = tokenAddressToVaultAddress[tokenAddress];
        uint256 sharesToRedeem = ERC4626(vault).convertToShares(amount);
        require(sharesToRedeem > 0, "No shares to redeem for the requested amount.");

        position.stakeAmount -= amount;
        // uint256 shares = ERC4626(vault).balanceOf(msg.sender);

        uint256 redeemedAmount = ERC4626(vault).redeem(sharesToRedeem, address(this), msg.sender);

        if (rewardTokenAddress == position.stakeToken) {
            (uint256 fee, uint256 amountAfterFee) = calculateAmountAfterFeeAndFee(redeemedAmount);
            IERC20(tokenAddress).safeTransfer(msg.sender, amountAfterFee);
            IERC20(tokenAddress).safeTransfer(owner(), fee);
        } else {
            address[] memory path;
            path = new address[](3);
            path[0] = tokenAddress;
            path[1] = address(weth);
            path[2] = rewardTokenAddress;

            uint256 stakedAmount = position.stakeAmount;
            uint256 rewardAmount = redeemedAmount - stakedAmount;

            (uint256 fee, uint256 amountAfterFee) = calculateAmountAfterFeeAndFee(redeemedAmount);
            IERC20(tokenAddress).safeTransfer(msg.sender, amountAfterFee);
            IERC20(tokenAddress).safeTransfer(owner(), fee);

            uint256 swappedAmount = SwapHelpers.swapIndexToReward(routerV3, path, rewardAmount, msg.sender);

            emit RewardTokensSwapped(tokenAddress, rewardTokenAddress, rewardAmount, swappedAmount, msg.sender);
        }

        if (ERC4626(vault).balanceOf(msg.sender) == 0) {
            numberOfStakersByTokenAddress[tokenAddress] -= 1;
        }

        emit Unstaked(msg.sender, tokenAddress, redeemedAmount, vault, sharesToRedeem, block.timestamp);
    }

    function _initializePools(
        address[] memory _indexTokensAddresses,
        address[] memory _rewardTokensAddresses,
        uint8[] memory _swapVersions
    ) internal {
        for (uint256 i = 0; i < _indexTokensAddresses.length; i++) {
            address vault = erc4626Factory.createERC4626Vault(_indexTokensAddresses[i]);
            tokenAddressToVaultAddress[_indexTokensAddresses[i]] = vault;
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

    function getUserShares(address user, address tokenAddress) public view returns (uint256) {
        address vault = tokenAddressToVaultAddress[tokenAddress];
        uint256 shares = ERC4626(vault).balanceOf(user);
        return shares;
    }
}
