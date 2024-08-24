// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/contracts/access/OwnableUpgradeable.sol";

import {ERC4626Factory} from "./factory/ERC4626Factory.sol";
import {CalculationHelper} from "./libraries/CalculationHelper.sol";

contract NexStaging is OwnableUpgradeable {
    using SafeERC20 for IERC20;

    ERC4626Factory erc4626Factory;
    IERC20 public nexLabsToken;
    address[] public poolTokens;
    uint256 public feePercent;
    uint256 private _nextId;

    struct Pools {
        address vault;
        uint256 totalStaked;
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

    event Staked(
        uint256 indexed positionId,
        address indexed user,
        address indexed tokenAddress,
        address vault,
        uint256 amount,
        uint256 timestamp
    );
    event UnStaked(
        uint256 indexed positionId,
        address indexed user,
        address indexed tokenAddress,
        address vault,
        uint256 amount,
        uint256 timestamp
    );

    constructor(address _nexLabsAddress, address[] memory _tokenAddress, uint256 _feePercent, address _erc4626Factory) {
        erc4626Factory = ERC4626Factory(_erc4626Factory);
        nexLabsToken = IERC20(_nexLabsAddress);
        feePercent = _feePercent;
        _nextId = 1;

        for (uint256 i = 0; i < _tokenAddress.length; i++) {
            poolTokens.push(_tokenAddress[i]);

            address vault = erc4626Factory.createERC4626Vault(_tokenAddress[i]);
            pools[_tokenAddress[i]] = Pools({vault: vault, totalStaked: 0});
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

        (uint256 fee, uint256 amountAfterFee) = CalculationHelper.calculateAmountAfterFeeAndFee(amount, feePercent);

        IERC20 token = IERC20(tokenAddress);
        token.safeTransferFrom(msg.sender, address(this), amountAfterFee);
        token.safeTransferFrom(msg.sender, address(this), fee); // should transfer to the owner

        positionId = _nextId++;

        _positions[positionId] = StakePositions({
            owner: msg.sender,
            stakeToken: tokenAddress,
            vault: pools[tokenAddress].vault, // should set the vault address
            stakeAmount: amountAfterFee,
            shares: 0, // @audit
            startTime: block.timestamp
        });

        // Update the total staked in the corresponding pool
        pools[tokenAddress].totalStaked += amountAfterFee;
        numberOfStakersByTokenAddress[tokenAddress] += 1;

        emit Staked(positionId, msg.sender, tokenAddress, pools[tokenAddress].vault, amountAfterFee, block.timestamp);
    }

    function unstake(uint256 positionId, address rewardToken) external {
        StakePositions storage position = _positions[positionId];
        require(position.owner == msg.sender, "You are not the owner of this position.");
        require(position.stakeAmount > 0, "No stake amount to unstake.");

        (uint256 fee, uint256 rewardAmountAfterFee) =
            CalculationHelper.calculateAmountAfterFeeAndFee(position.stakeAmount);

        if (position.vault == rewardToken) {
            // IERC20(position.vault).safeTransfer(msg.sender, rewardAmountAfterFee);
        }

        emit UnStaked(
            positionId, msg.sender, position.stakeToken, position.vault, position.stakeAmount, block.timestamp
        );

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
