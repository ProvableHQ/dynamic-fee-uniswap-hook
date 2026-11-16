// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {BaseHook} from "@openzeppelin/uniswap-hooks/src/base/BaseHook.sol";
import {BaseDynamicFee} from "@openzeppelin/uniswap-hooks/src/fee/BaseDynamicFee.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {LPFeeLibrary} from "@uniswap/v4-core/src/libraries/LPFeeLibrary.sol";

/// @notice OpenZeppelin's owner-controlled dynamic-fee pattern, starting at 5 bps.
contract AleoDynamicFeeHook is BaseDynamicFee, Ownable {
    using LPFeeLibrary for uint24;

    uint24 public fee = 500;

    constructor(IPoolManager manager, address initialOwner) BaseHook(manager) Ownable(initialOwner) {}

    /// @notice Select the fee in pips; call poke(key) to apply it to an existing pool.
    function setFee(uint24 newFee) external onlyOwner {
        newFee.validate();
        fee = newFee;
    }

    /// @notice Anyone may apply the owner's selected fee to a pool using this hook.
    function poke(PoolKey calldata key) external {
        _poke(key);
    }

    function _getFee(PoolKey calldata) internal view override returns (uint24) {
        return fee;
    }
}
