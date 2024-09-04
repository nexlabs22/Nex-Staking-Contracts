// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {IUniswapV3Factory} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/contracts/access/OwnableUpgradeable.sol";
import {ISwapRouter} from "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import {IQuoter} from "@uniswap/v3-periphery/contracts/interfaces/IQuoter.sol";

import {ReentrancyGuardUpgradeable} from
    "@openzeppelin/contracts-upgradeable/contracts/utils/ReentrancyGuardUpgradeable.sol";

import {ERC4626Factory} from "./factory/ERC4626Factory.sol";
import {CalculationHelpers} from "./libraries/CalculationHelpers.sol";
import {SwapHelpers} from "./libraries/SwapHelpers.sol";
import {IWETH9} from "./interfaces/IWETH9.sol";
import {IUniswapV2Router02} from "./interfaces/IUniswapV2Router02.sol";
import {IUniswapV2Factory} from "./interfaces/IUniswapV2Factory.sol";
import {OracleLibrary} from "./libraries/OracleLibrary.sol";

contract NexStaking is OwnableUpgradeable, ReentrancyGuardUpgradeable {
    using SafeERC20 for IERC20;

    ERC4626Factory public erc4626Factory;
    ISwapRouter public routerV3;
    IUniswapV3Factory public factoryV3;
    IUniswapV2Router02 public routerV2;
    IUniswapV2Factory public factoryV2;
    IQuoter public quoter;
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

    event RewardsDistributed(address indexed tokenAddress, uint256 amount, uint256 timestamp);

    event RewardDistributionSkipped(address indexed tokenAddress, string reason);

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
        address _uniswapV3Factory,
        address _weth,
        uint8 _feePercent
    ) public initializer {
        __Ownable_init(msg.sender);
        __ReentrancyGuard_init();

        require(_nexLabsTokenAddress != address(0), "Invalid address for _nexLabsAddress");
        require(_erc4626Factory != address(0), "Invalid address for _erc4626Factory");
        require(_uniswapV3Router != address(0), "Invalid address for _uniswapRouter");
        require(_weth != address(0), "Invalid address for _weth");

        erc4626Factory = ERC4626Factory(_erc4626Factory);
        routerV3 = ISwapRouter(_uniswapV3Router);
        factoryV3 = IUniswapV3Factory(_uniswapV3Factory);
        weth = IWETH9(_weth);
        nexLabsToken = IERC20(_nexLabsTokenAddress);
        // rewardTokensAddresses = _rewardTokensAddresses;
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
        // token.safeTransferFrom(msg.sender, address(this), amountAfterFee);

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
        require(position.stakeAmount > 0, "No stake amount to unstake.");

        address vault = tokenAddressToVaultAddress[tokenAddress];
        uint256 shares = ERC4626(vault).balanceOf(msg.sender);
        // uint256 unstakeAmount = ERC4626(vault).convertToAssets(shares);

        uint256 redeemedAmount = ERC4626(vault).redeem(shares, address(this), msg.sender);

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

            uint256 rewardAmount = redeemedAmount - position.stakeAmount;
            uint256 stakedAmount = position.stakeAmount;

            (uint256 fee, uint256 amountAfterFee) = calculateAmountAfterFeeAndFee(redeemedAmount);
            IERC20(tokenAddress).safeTransfer(owner(), fee);
            IERC20(tokenAddress).safeTransfer(msg.sender, stakedAmount);
            uint256 swappedAmount = SwapHelpers.swapIndexToReward(routerV3, path, rewardAmount, msg.sender);

            emit RewardTokensSwapped(tokenAddress, rewardTokenAddress, rewardAmount, swappedAmount, msg.sender);
        }

        if (ERC4626(vault).balanceOf(msg.sender) == 0) {
            numberOfStakersByTokenAddress[tokenAddress] -= 1;
        }

        emit Unstaked(msg.sender, tokenAddress, redeemedAmount, vault, shares, block.timestamp);
    }

    function distributeRewards(address[] memory tokens) public {
        uint256 initialWethBalance = weth.balanceOf(address(this));

        uint256[] memory poolWeights = calculateWeightOfPools();

        for (uint256 i = 0; i < tokens.length; i++) {
            address vault = tokenAddressToVaultAddress[tokens[i]];

            uint256 wethAmountForPool = (initialWethBalance * poolWeights[i]) / 1e18;

            if (wethAmountForPool == 0) {
                emit RewardDistributionSkipped(tokens[i], "Weight is zero");
                continue;
            }

            uint256 convertedAmount = SwapHelpers.swapTokens(routerV3, address(weth), tokens[i], wethAmountForPool);

            IERC20(tokens[i]).approve(vault, convertedAmount);
            IERC20(tokens[i]).safeTransfer(vault, convertedAmount);

            emit RewardsDistributed(tokens[i], convertedAmount, block.timestamp);
        }
    }

    function getExactAmountOut(address tokenIn, address tokenOut, uint256 amountIn, uint8 _swapVersion)
        public
        returns (uint256 finalAmountOut)
    {
        if (_swapVersion == 3) {
            try quoter.quoteExactInputSingle(tokenIn, tokenOut, 3000, amountIn, 0) returns (uint256 _amount) {
                return _amount;
            } catch {
                revert("Uniswap V3 Quote failed");
            }
        } else {
            address[] memory path = new address[](2);
            path[0] = tokenIn;
            path[1] = tokenOut;
            try routerV2.getAmountsOut(amountIn, path) returns (uint256[] memory _amounts) {
                return _amounts[1];
            } catch {
                revert("Uniswap V2 Quote failed");
            }
        }
    }

    function getAmountOut(address tokenIn, address tokenOut, uint256 amountIn, uint8 _swapVersion)
        public
        view
        returns (uint256 finalAmountOut)
    {
        if (amountIn > 0) {
            if (_swapVersion == 3) {
                return estimateAmountOut(tokenIn, tokenOut, uint128(amountIn));
            } else {
                address[] memory path = new address[](2);
                path[0] = tokenIn;
                path[1] = tokenOut;
                uint256[] memory v2amountOut = routerV2.getAmountsOut(amountIn, path);
                return v2amountOut[1];
            }
        }
        return 0;
    }

    function estimateAmountOut(address tokenIn, address tokenOut, uint128 amountIn)
        public
        view
        returns (uint256 amountOut)
    {
        address _pool = factoryV3.getPool(tokenIn, tokenOut, 3000);
        int24 tick = OracleLibrary.getLatestTick(_pool);
        amountOut = OracleLibrary.getQuoteAtTick(tick, amountIn, tokenIn, tokenOut);
    }

    function getPortfolioBalance() public view returns (uint256 totalValue) {
        for (uint256 i = 0; i < poolTokensAddresses.length; i++) {
            address tokenAddress = poolTokensAddresses[i];
            address vault = tokenAddressToVaultAddress[tokenAddress];
            if (tokenAddress == address(weth)) {
                totalValue += IERC20(tokenAddress).balanceOf(vault);
            } else {
                uint256 value = getAmountOut(
                    tokenAddress, address(weth), IERC20(tokenAddress).balanceOf(vault), tokenSwapVersion[tokenAddress]
                );
                totalValue += value;
            }
        }
        return totalValue;
    }

    function calculateWeightOfPools() public view returns (uint256[] memory) {
        uint256 totalValueAcrossAllPools = getPortfolioBalance();
        uint256[] memory weights = new uint256[](poolTokensAddresses.length);

        for (uint256 i = 0; i < poolTokensAddresses.length; i++) {
            address vault = tokenAddressToVaultAddress[poolTokensAddresses[i]];
            uint256 balance = IERC20(poolTokensAddresses[i]).balanceOf(vault);
            uint256 poolValue =
                getAmountOut(poolTokensAddresses[i], address(weth), balance, tokenSwapVersion[poolTokensAddresses[i]]);
            if (poolValue == 0) {
                continue;
            }
            weights[i] = (poolValue * 1e18) / totalValueAcrossAllPools;
        }

        return weights;
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
