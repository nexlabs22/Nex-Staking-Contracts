// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/contracts/access/OwnableUpgradeable.sol";
import {ISwapRouter} from "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import {IQuoterV2} from "@uniswap/v3-periphery/contracts/interfaces/IQuoterV2.sol";

import {ERC4626Factory} from "./factory/ERC4626Factory.sol";
import {CalculationHelper} from "./libraries/CalculationHelper.sol";
import {SwapHelpers} from "./libraries/SwapHelpers.sol";
import {IWETH9} from "./interfaces/IWETH9.sol";

contract NexStaging is OwnableUpgradeable {
    using SafeERC20 for IERC20;

    ERC4626Factory erc4626Factory;
    ISwapRouter public uniswapRouter;
    IQuoterV2 public qouterV2;

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

    function initialize(
        address _nexLabsAddress,
        address[] memory _tokenAddresses,
        address[] memory _indexTokens,
        uint256 _feePercent,
        address _erc4626Factory,
        address _uniswapRouter
    ) public initializer {
        __Ownable_init(msg.sender);

        require(_tokenAddresses.length == _indexTokens.length, "Token and index token length mismatch");

        erc4626Factory = ERC4626Factory(_erc4626Factory);
        uniswapRouter = ISwapRouter(_uniswapRouter);
        nexLabsToken = IERC20(_nexLabsAddress);
        feePercent = _feePercent;
        _nextId = 1;

        for (uint256 i = 0; i < _tokenAddresses.length; i++) {
            address vault = erc4626Factory.createERC4626Vault(_tokenAddresses[i]);
            pools[_tokenAddresses[i]] =
                Pools({vault: vault, indexToken: IERC20(_tokenAddresses[i]), totalStaked: 0, totalSupply: 0});
        }
    }

    function positions(uint256 positionId)
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

    function stake(address tokenAddress, uint256 amount) external returns (uint256 positionId) {
        require(tokenAddress != address(0), "Token not supported for staking.");
        require(amount > 0, "Staking amount must be greater than zero.");

        Pools storage pool = pools[tokenAddress];
        require(pool.vault != address(0), "Pool not found for token.");

        (uint256 fee, uint256 amountAfterFee) = CalculationHelper.calculateAmountAfterFeeAndFee(amount, feePercent);

        IERC20 token = IERC20(tokenAddress);
        token.safeTransferFrom(msg.sender, address(this), amountAfterFee);
        token.safeTransferFrom(msg.sender, owner(), fee); // Transfer fee to the owner

        ERC4626(pool.vault).mint(amountAfterFee, msg.sender);

        uint256 shares = amountAfterFee;

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
        numberOfStakersByTokenAddress[tokenAddress] += 1;

        emit Staked(positionId, msg.sender, tokenAddress, pool.vault, amountAfterFee, shares, block.timestamp);
    }

    function unstake(uint256 positionId, address rewardToken, address receiver) external {
        StakePositions storage position = _positions[positionId];
        require(position.owner == msg.sender, "You are not the owner of this position.");
        require(position.stakeAmount > 0, "No stake amount to unstake.");

        Pools storage pool = pools[position.stakeToken];

        (uint256 fee, uint256 rewardAmountAfterFee) =
            CalculationHelper.calculateAmountAfterFeeAndFee(position.stakeAmount, feePercent);

        ERC4626(pool.vault).withdraw(position.shares, receiver, msg.sender);
        if (rewardToken == position.stakeToken) {
            IERC20(pool.indexToken).safeTransfer(msg.sender, rewardAmountAfterFee);
            IERC20(pool.indexToken).safeTransfer(owner(), fee);
        } else {
            uint256 amountOut = SwapHelpers.swapIndexTokensForRewardToken(
                uniswapRouter, position.stakeToken, rewardToken, position.stakeAmount
            );
            (uint256 feeAmount, uint256 amountAfterFee) =
                CalculationHelper.calculateAmountAfterFeeAndFee(amountOut, feePercent);
            IERC20(rewardToken).safeTransfer(msg.sender, amountAfterFee);
            IERC20(rewardToken).safeTransfer(owner(), feeAmount);
        }

        emit Unstaked(
            positionId,
            msg.sender,
            position.stakeToken,
            pool.vault,
            position.stakeAmount,
            position.shares,
            block.timestamp
        );

        pool.totalStaked -= position.stakeAmount;
        shareHolder[msg.sender] -= position.shares;

        delete _positions[positionId];
    }

    function distributeRewards(address[] memory tokens) internal {
        uint256[] memory poolWeights = calculateWeightOfPools();

        for (uint256 i = 0; i < tokens.length; i++) {
            Pools storage pool = pools[tokens[i]];
            // uint256 ethAmountForPool = address(this).balance * poolWeights[i] / 1e18;
            uint256 wethAmountForPool = weth.balanceOf(address(this)) * poolWeights[i];
            uint256 convertedAmount = SwapHelpers.swapTokensForPoolIndexToken(
                uniswapRouter, address(weth), address(pool.indexToken), wethAmountForPool, 3000
            );

            pool.totalStaked += convertedAmount;
            emit RewardsDistributed(tokens[i], convertedAmount, block.timestamp);
        }
    }

    function calculateWeightOfPools() internal view returns (uint256[] memory) {
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

    receive() external payable {
        distributeRewards(poolTokens);
    }

    fallback() external payable {
        distributeRewards(poolTokens);
    }

    function qouter(address tokenIn, address tokenOut, uint256 amount, uint24 fee)
        external
        returns (uint256 amountOut)
    {
        IQuoterV2.QuoteExactInputSingleParams memory params = IQuoterV2.QuoteExactInputSingleParams({
            tokenIn: tokenIn,
            tokenOut: tokenOut,
            amountIn: amount,
            fee: fee,
            sqrtPriceLimitX96: 0 // @audit
        });
        (amountOut,,,) = qouterV2.quoteExactInputSingle(params);
        return amountOut;
    }
}
