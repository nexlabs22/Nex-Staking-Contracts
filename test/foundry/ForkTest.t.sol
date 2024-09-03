// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "forge-std/Test.sol";
// import "../../contracts/Swap.sol";
import "../../contracts/interfaces/IWETH9.sol";
// import "../../contracts/interfaces/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import "@uniswap/v3-periphery/contracts/libraries/TransferHelper.sol";
import "@uniswap/v3-periphery/contracts/interfaces/IQuoter.sol";

contract ForkTest is Test {
    // the identifiers of the forks
    uint256 mainnetFork;
    // uint256 optimismFork;

    address public constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address public constant WETH9 = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address public constant QUOTER = 0xb27308f9F90D607463bb33eA1BeBb41C27CE5AB6;

    ISwapRouter public constant swapRouter = ISwapRouter(0xE592427A0AEce92De3Edee1F18E0157C05861564);

    ERC20 public dai;
    IWETH9 public weth;

    // Swap public swap;
    IQuoter public quoter;
    //Access variables from .env file via vm.envString("varname")
    //Replace ALCHEMY_KEY by your alchemy key or Etherscan key, change RPC url if need
    //inside your .env file e.g:
    // MAINNET_RPC_URL = 'https://eth-mainnet.g.alchemy.com/v2/ALCHEMY_KEY'
    string MAINNET_RPC_URL = vm.envString("MAINNET_RPC_URL");
    // string OPTIMISM_RPC_URL = vm.envString("OPTIMISM_RPC_URL");

    // create two _different_ forks during setup
    function setUp() public {
        mainnetFork = vm.createFork(MAINNET_RPC_URL);
        // swap = new Swap();
        dai = ERC20(DAI);
        weth = IWETH9(WETH9);
        quoter = IQuoter(QUOTER);
        // optimismFork = vm.createFork(OPTIMISM_RPC_URL);
    }

    // select a specific fork
    function testCanSelectFork() public {
        // select the fork
        vm.selectFork(mainnetFork);
        assertEq(vm.activeFork(), mainnetFork);
    }

    // set `block.number` of a fork
    function testCanSetForkBlockNumber() public {
        vm.selectFork(mainnetFork);
        vm.rollFork(18462431);
        assertEq(block.number, 18462431);
        console.log(dai.name());
    }

    // set `block.number` of a fork
    function testSwap() public {
        vm.selectFork(mainnetFork);
        // vm.rollFork(18462431);
        weth.deposit{value: 1e17}();
        // assertEq(weth.balanceOf(address(this)), 1e17);
        weth.approve(address(swapRouter), 1e17);

        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams({
            tokenIn: WETH9,
            tokenOut: DAI,
            // pool fee 0.3%
            fee: 3000,
            recipient: address(this),
            deadline: block.timestamp,
            amountIn: 1e17,
            amountOutMinimum: 0,
            // NOTE: In production, this value can be used to set the limit
            // for the price the swap will push the pool to,
            // which can help protect against price impact
            sqrtPriceLimitX96: 0
        });
        console.log("Output amount ", swapRouter.exactInputSingle(params));
        console.log("Dai Balance ", dai.balanceOf(address(this)));
        console.log("Weth balance ", weth.balanceOf(address(this)));

        uint256 amountOut = quoter.quoteExactInputSingle(DAI, WETH9, 3000, dai.balanceOf(address(this)), 0);
        console.log("exptected amount", amountOut);
        dai.approve(address(swapRouter), dai.balanceOf(address(this)));

        ISwapRouter.ExactInputSingleParams memory params2 = ISwapRouter.ExactInputSingleParams({
            tokenIn: DAI,
            tokenOut: WETH9,
            // pool fee 0.3%
            fee: 3000,
            recipient: address(this),
            deadline: block.timestamp,
            amountIn: dai.balanceOf(address(this)),
            amountOutMinimum: 0,
            // NOTE: In production, this value can be used to set the limit
            // for the price the swap will push the pool to,
            // which can help protect against price impact
            sqrtPriceLimitX96: 0
        });

        console.log("Output amount ", swapRouter.exactInputSingle(params2));
        console.log("Dai Balance ", dai.balanceOf(address(this)));
        console.log("Weth balance ", weth.balanceOf(address(this)));
    }
}
