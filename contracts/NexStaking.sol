// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/contracts/access/OwnableUpgradeable.sol";
import {ISwapRouter} from "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import {IQuoterV2} from "@uniswap/v3-periphery/contracts/interfaces/IQuoterV2.sol";
import {IQuoter} from "@uniswap/v3-periphery/contracts/interfaces/IQuoter.sol";
import {IUniswapV3Factory} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
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
    ISwapRouter public uniswapV3Router;
    IUniswapV2Router02 public uniswapV2Router;
    IUniswapV3Factory public factoryV3;
    IUniswapV2Factory public factoryV2;
    IQuoter public quoter;

    IWETH9 public weth;
    IERC20 public nexLabsToken;
    address[] public poolTokens;
    uint256 public feePercent;
    uint256 private _nextId;

    struct Pools {
        address vault;
        IERC20 indexToken;
        uint256 totalStaked;
        uint256 totalSupply;
    }

    struct StakePositions {
        address owner;
        address stakeToken;
        address vault;
        uint256 stakeAmount;
        uint256 shares;
        uint256 startTime;
    }

    mapping(address => uint8) public tokenSwapVersion;
    mapping(address => bool) public supportedTokens;
    mapping(address => Pools) public pools;
    mapping(uint256 => StakePositions) private _positions;
    mapping(address => uint256) public numberOfStakersByTokenAddress;
    mapping(address => uint256) public shareHolder;

    event Staked(
        uint256 indexed positionId,
        address indexed user,
        address indexed tokenAddress,
        address vault,
        uint256 amount,
        uint256 shares,
        uint256 timestamp
    );

    event Unstaked(
        uint256 indexed positionId,
        address indexed user,
        address indexed tokenAddress,
        address vault,
        uint256 amount,
        uint256 shares,
        uint256 timestamp
    );

    event RewardsDistributed(address indexed tokenAddress, uint256 amount, uint256 timestamp);

    event RewardDistributionSkipped(address indexed tokenAddress, string reason);

    function initialize(
        address _nexLabsAddress,
        address[] memory _tokenAddresses,
        address[] memory _indexTokens,
        uint256 _feePercent,
        address _erc4626Factory,
        address _uniswapV3Router,
        address _uniswapV2Router,
        address _quoter,
        address _factoryV3,
        address _weth
    ) public initializer {
        __Ownable_init(msg.sender);
        __ReentrancyGuard_init();

        require(_nexLabsAddress != address(0), "Invalid address for _nexLabsAddress");
        require(_erc4626Factory != address(0), "Invalid address for _erc4626Factory");
        require(_uniswapV3Router != address(0), "Invalid address for _uniswapRouter");
        require(_uniswapV2Router != address(0), "Invalid address for _uniswapV2Router");
        require(_weth != address(0), "Invalid address for _weth");
        require(_tokenAddresses.length == _indexTokens.length, "Token and index token length mismatch");

        erc4626Factory = ERC4626Factory(_erc4626Factory);
        uniswapV3Router = ISwapRouter(_uniswapV3Router);
        uniswapV2Router = IUniswapV2Router02(_uniswapV2Router);
        factoryV3 = IUniswapV3Factory(_factoryV3);
        quoter = IQuoter(_quoter);
        weth = IWETH9(_weth);
        nexLabsToken = IERC20(_nexLabsAddress);

        feePercent = _feePercent;
        _nextId = 1;

        _initializePools(_tokenAddresses);
    }

    function getPools(address tokenAddress)
        external
        view
        returns (address vault, address indexToken, uint256 totalStaked, uint256 totalSupply)
    {
        Pools storage pool = pools[tokenAddress];
        return (pool.vault, address(pool.indexToken), pool.totalStaked, pool.totalSupply);
    }

    function getPositions(uint256 positionId)
        external
        view
        returns (
            address positionOwner,
            address stakeToken,
            address vault,
            uint256 stakeAmount,
            uint256 shares,
            uint256 startTime
        )
    {
        StakePositions memory position = _positions[positionId];
        return (
            position.owner,
            position.stakeToken,
            position.vault,
            position.stakeAmount,
            position.shares,
            position.startTime
        );
    }

    function stake(address tokenAddress, uint256 amount) external nonReentrant returns (uint256 positionId) {
        require(tokenAddress != address(0) && supportedTokens[tokenAddress], "Token not supported for staking.");
        require(amount > 0, "Staking amount must be greater than zero.");

        Pools storage pool = pools[tokenAddress];
        require(pool.vault != address(0), "Pool not found for token.");

        (uint256 fee, uint256 amountAfterFee) = CalculationHelpers.calculateAmountAfterFeeAndFee(amount, feePercent);

        IERC20 token = IERC20(tokenAddress);
        token.safeTransferFrom(msg.sender, address(this), amountAfterFee);
        token.safeTransferFrom(msg.sender, owner(), fee); // Transfer fee to the owner

        uint256 shares = ERC4626(pool.vault).deposit(amountAfterFee, msg.sender);

        positionId = _nextId++;

        _positions[positionId] = StakePositions({
            owner: msg.sender,
            stakeToken: tokenAddress,
            vault: pools[tokenAddress].vault,
            stakeAmount: amountAfterFee,
            shares: shares,
            startTime: block.timestamp
        });

        shareHolder[msg.sender] += shares;
        pool.totalStaked += amountAfterFee;
        pool.totalSupply += shares;
        numberOfStakersByTokenAddress[tokenAddress] += 1;

        emit Staked(positionId, msg.sender, tokenAddress, pool.vault, amountAfterFee, shares, block.timestamp);
    }

    function unstake(uint256 positionId, address rewardToken /*, address receiver uint8 _swapVersion*/ )
        external
        nonReentrant
    {
        StakePositions storage position = _positions[positionId];
        require(position.owner == msg.sender, "You are not the owner of this position.");
        require(position.stakeAmount > 0, "No stake amount to unstake.");
        // require(receiver != address(0), "Invalid receiver address.");

        Pools storage pool = pools[position.stakeToken];

        uint256 redeemedAmount = ERC4626(pool.vault).redeem(position.shares, address(this), msg.sender);

        if (rewardToken == position.stakeToken) {
            (uint256 fee, uint256 rewardAmountAfterFee) =
                CalculationHelpers.calculateAmountAfterFeeAndFee(redeemedAmount, feePercent);
            IERC20(pool.indexToken).safeTransfer(msg.sender, rewardAmountAfterFee);
            IERC20(pool.indexToken).safeTransfer(owner(), fee);
        } else {
            uint256 swappedAmount =
                SwapHelpers.swapTokens(uniswapV3Router, position.stakeToken, rewardToken, redeemedAmount);
            (uint256 feeAmount, uint256 amountAfterFee) =
                CalculationHelpers.calculateAmountAfterFeeAndFee(swappedAmount, feePercent);
            IERC20(rewardToken).safeTransfer(msg.sender, amountAfterFee);
            IERC20(rewardToken).safeTransfer(owner(), feeAmount);
        }

        pool.totalStaked -= position.stakeAmount;
        pool.totalSupply -= position.shares;
        shareHolder[msg.sender] -= position.shares;

        emit Unstaked(
            positionId,
            msg.sender,
            position.stakeToken,
            pool.vault,
            position.stakeAmount,
            position.shares,
            block.timestamp
        );

        delete _positions[positionId];
    }

    function distributeRewards(address[] memory tokens) public {
        uint256 initialWethBalance = weth.balanceOf(address(this));

        if (initialWethBalance < 1e18) {
            return;
        }

        uint256[] memory poolWeights = calculateWeightOfPools();

        for (uint256 i = 0; i < tokens.length; i++) {
            Pools storage pool = pools[tokens[i]];

            uint256 wethAmountForPool = (initialWethBalance * poolWeights[i]) / 1e18;

            if (wethAmountForPool == 0) {
                emit RewardDistributionSkipped(tokens[i], "Weight is zero");
                continue;
            }

            uint256 convertedAmount =
                SwapHelpers.swapTokens(uniswapV3Router, address(weth), address(pool.indexToken), wethAmountForPool);

            IERC20(pool.indexToken).approve(pool.vault, convertedAmount);
            uint256 depositedShares = ERC4626(pool.vault).deposit(convertedAmount, address(this));

            pool.totalStaked += convertedAmount;

            emit RewardsDistributed(tokens[i], depositedShares, block.timestamp);
        }
    }

    // --------------------------------------------------------------------------------------------------------------

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
            try uniswapV2Router.getAmountsOut(amountIn, path) returns (uint256[] memory _amounts) {
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
                uint256[] memory v2amountOut = uniswapV2Router.getAmountsOut(amountIn, path);
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
        for (uint256 i = 0; i < poolTokens.length; i++) {
            address tokenAddress = poolTokens[i];
            if (tokenAddress == address(weth)) {
                totalValue += IERC20(tokenAddress).balanceOf(address(pools[tokenAddress].vault));
            } else {
                uint256 value = getAmountOut(
                    tokenAddress,
                    address(weth),
                    IERC20(tokenAddress).balanceOf(address(pools[tokenAddress].vault)),
                    tokenSwapVersion[tokenAddress]
                );
                totalValue += value;
            }
        }
        return totalValue;
    }

    function calculateWeightOfPools() public view returns (uint256[] memory) {
        uint256 totalValueAcrossAllPools = getPortfolioBalance();
        uint256[] memory weights = new uint256[](poolTokens.length);

        for (uint256 i = 0; i < poolTokens.length; i++) {
            Pools storage pool = pools[poolTokens[i]];
            uint256 poolValue =
                getAmountOut(poolTokens[i], address(weth), pool.totalStaked, tokenSwapVersion[poolTokens[i]]);
            if (poolValue == 0) {
                continue;
            }
            weights[i] = (poolValue * 1e18) / totalValueAcrossAllPools; // Normalize weights
        }

        return weights;
    }

    receive() external payable {
        distributeRewards(poolTokens);
    }

    fallback() external payable {
        distributeRewards(poolTokens);
    }

    function _initializePools(address[] memory _tokenAddresses) internal {
        for (uint256 i = 0; i < _tokenAddresses.length; i++) {
            address vault = erc4626Factory.createERC4626Vault(_tokenAddresses[i]);
            pools[_tokenAddresses[i]] =
                Pools({vault: vault, indexToken: IERC20(_tokenAddresses[i]), totalStaked: 0, totalSupply: 0});
            // poolTokens.push(_tokenAddresses[i]);
            supportedTokens[_tokenAddresses[i]] = true;
        }
        poolTokens = _tokenAddresses;
    }
}
