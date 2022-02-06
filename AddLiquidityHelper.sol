// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol";

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";


// AddLiquidityHelper, allows anyone to add or remove MP liquidity tax free
// Also allows the MP Token to do buy backs tax free via an external contract.
contract AddLiquidityHelper is ReentrancyGuard, Ownable {
    using SafeERC20 for ERC20;

    address public MPAddress;

    IUniswapV2Router02 public immutable MPSwapRouter;

    // To receive ETH when swapping
    receive() external payable {}

    event SetMPAddress(address MPAddress);

    /**
     * @notice Constructs the AddLiquidityHelper contract.
     */
    constructor(address _router) public  {
        require(_router != address(0), "_router is the zero address");
        MPSwapRouter = IUniswapV2Router02(_router);
    }

    function addMPETHLiquidity(uint256 nativeAmount) external payable nonReentrant {
        require(msg.value > 0, "!sufficient funds");

        ERC20(MPAddress).safeTransferFrom(msg.sender, address(this), nativeAmount);

        // approve token transfer to cover all possible scenarios
        ERC20(MPAddress).approve(address(MPSwapRouter), nativeAmount);

        // add the liquidity
        MPSwapRouter.addLiquidityETH{value: msg.value}(
            MPAddress,
            nativeAmount,
            0, // slippage is unavoidable
            0, // slippage is unavoidable
            msg.sender,
            block.timestamp
        );

        if (address(this).balance > 0) {
            // not going to require/check return value of this transfer as reverting behaviour is undesirable.
            payable(address(msg.sender)).call{value: address(this).balance}("");
        }

        uint256 MPBalance = ERC20(MPAddress).balanceOf(address(this));

        if (MPBalance > 0)
            ERC20(MPAddress).transfer(msg.sender, MPBalance);
    }

    function addMPLiquidity(address baseTokenAddress, uint256 baseAmount, uint256 nativeAmount) external nonReentrant {
        ERC20(baseTokenAddress).safeTransferFrom(msg.sender, address(this), baseAmount);
        ERC20(MPAddress).safeTransferFrom(msg.sender, address(this), nativeAmount);

        // approve token transfer to cover all possible scenarios
        ERC20(baseTokenAddress).approve(address(MPSwapRouter), baseAmount);
        ERC20(MPAddress).approve(address(MPSwapRouter), nativeAmount);

        // add the liquidity
        MPSwapRouter.addLiquidity(
            baseTokenAddress,
            MPAddress,
            baseAmount,
            nativeAmount ,
            0, // slippage is unavoidable
            0, // slippage is unavoidable
            msg.sender,
            block.timestamp
        );

        if (ERC20(baseTokenAddress).balanceOf(address(this)) > 0)
            ERC20(baseTokenAddress).safeTransfer(msg.sender, ERC20(baseTokenAddress).balanceOf(address(this)));

        if (ERC20(MPAddress).balanceOf(address(this)) > 0)
            ERC20(MPAddress).transfer(msg.sender, ERC20(MPAddress).balanceOf(address(this)));
    }

    function removeMPLiquidity(address baseTokenAddress, uint256 liquidity) external nonReentrant {
        address lpTokenAddress = IUniswapV2Factory(MPSwapRouter.factory()).getPair(baseTokenAddress, MPAddress);
        require(lpTokenAddress != address(0), "pair hasn't been created yet, so can't remove liquidity!");

        ERC20(lpTokenAddress).safeTransferFrom(msg.sender, address(this), liquidity);
        // approve token transfer to cover all possible scenarios
        ERC20(lpTokenAddress).approve(address(MPSwapRouter), liquidity);

        // add the liquidity
        MPSwapRouter.removeLiquidity(
            baseTokenAddress,
            MPAddress,
            liquidity,
            0, // slippage is unavoidable
            0, // slippage is unavoidable
            msg.sender,
            block.timestamp
        );
    }

    /// @dev Swap tokens for eth
    function swapTokensForEth(address saleTokenAddress, uint256 tokenAmount) internal {
        // generate the MPSwap pair path of token -> weth
        address[] memory path = new address[](2);
        path[0] = saleTokenAddress;
        path[1] = MPSwapRouter.WETH();

        ERC20(saleTokenAddress).approve(address(MPSwapRouter), tokenAmount);

        // make the swap
        MPSwapRouter.swapExactTokensForETHSupportingFeeOnTransferTokens(
            tokenAmount,
            0, // accept any amount of ETH
            path,
            address(this),
            block.timestamp
        );
    }


    function swapETHForTokens(uint256 ethAmount, address wantedTokenAddress) internal {
        require(address(this).balance >= ethAmount, "insufficient fantom provided!");
        require(wantedTokenAddress != address(0), "wanted token address can't be the zero address!");

        // generate the MPSwap pair path of token -> weth
        address[] memory path = new address[](2);
        path[0] = MPSwapRouter.WETH();
        path[1] = wantedTokenAddress;

        // make the swap
        MPSwapRouter.swapExactETHForTokensSupportingFeeOnTransferTokens{value: ethAmount}(
            0,
            path,
            // cannot send tokens to the token contract of the same type as the output token
            address(this),
            block.timestamp
        );
    }

    /**
     * @dev set the MP address.
     * Can only be called by the current owner.
     */
    function setMPAddress(address _MPAddress) external onlyOwner {
        require(_MPAddress != address(0), "_MPddress is the zero address");
        require(MPAddress == address(0), "MPAddress already set!");

        MPAddress = _MPAddress;

        emit SetMPAddress(MPAddress);
    }
}
