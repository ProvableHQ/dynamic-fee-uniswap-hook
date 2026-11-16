// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {PoolManager} from "@uniswap/v4-core/src/PoolManager.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {StateLibrary} from "@uniswap/v4-core/src/libraries/StateLibrary.sol";
import {LPFeeLibrary} from "@uniswap/v4-core/src/libraries/LPFeeLibrary.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {ModifyLiquidityParams, SwapParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";
import {PoolModifyLiquidityTest} from "@uniswap/v4-core/src/test/PoolModifyLiquidityTest.sol";
import {PoolSwapTest} from "@uniswap/v4-core/src/test/PoolSwapTest.sol";
import {AleoDynamicFeeHook} from "../src/AleoDynamicFeeHook.sol";

contract MintableToken is ERC20 {
    constructor() ERC20("Fixture", "FIX") {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function decimals() public pure override returns (uint8) {
        return 6;
    }
}

contract AleoDynamicFeeHookTest is Test {
    using StateLibrary for IPoolManager;
    using PoolIdLibrary for PoolKey;

    address internal constant ALEO = 0x33fbC08bD84E61E04e51eA0F32885AA77F7D5ECa;
    address internal constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    IPoolManager internal manager;
    AleoDynamicFeeHook internal hook;
    PoolKey internal key;
    address internal owner = makeAddr("owner");
    address internal successor = makeAddr("successor");
    address internal outsider = makeAddr("outsider");

    function setUp() public {
        manager = IPoolManager(address(new PoolManager(address(this))));
        hook = _deploy(owner);
        key = PoolKey(Currency.wrap(ALEO), Currency.wrap(USDT), 8388608, 60, IHooks(address(hook)));
    }

    function _deploy(address controller) internal returns (AleoDynamicFeeHook result) {
        bytes32 codeHash =
            keccak256(abi.encodePacked(type(AleoDynamicFeeHook).creationCode, abi.encode(manager, controller)));
        for (uint256 nonce;; ++nonce) {
            bytes32 salt = bytes32(nonce);
            address candidate = vm.computeCreate2Address(salt, codeHash, address(this));
            if (uint160(candidate) & 0x3fff == 0x1000) {
                return new AleoDynamicFeeHook{salt: salt}(manager, controller);
            }
        }
    }

    function _initialize() internal {
        manager.initialize(key, uint160(1 << 96));
    }

    function _storedFee() internal view returns (uint24 fee) {
        (,,, fee) = manager.getSlot0(key.toId());
    }

    function testAnyoneMayInitializeAndInitialFeeIsFiveBps() public {
        vm.prank(outsider);
        manager.initialize(key, uint160(1 << 96));
        assertEq(_storedFee(), 500);
        assertEq(hook.owner(), owner);
    }

    function testOnlyOwnerSelectsFeeAndAnyoneCanRefreshIt() public {
        _initialize();
        vm.prank(owner);
        hook.setFee(2500);
        assertEq(hook.fee(), 2500);
        assertEq(_storedFee(), 500);
        vm.prank(outsider);
        hook.poke(key);
        assertEq(_storedFee(), 2500);
    }

    function testNonOwnerCannotSelectFee() public {
        vm.prank(outsider);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, outsider));
        hook.setFee(2500);
        assertEq(hook.fee(), 500);
    }

    function testFuzzOnlyNativeFeeLimitApplies(uint24 nextFee) public {
        _initialize();
        vm.prank(owner);
        if (nextFee > 1000000) {
            vm.expectRevert(abi.encodeWithSelector(LPFeeLibrary.LPFeeTooLarge.selector, nextFee));
            hook.setFee(nextFee);
            assertEq(hook.fee(), 500);
        } else {
            hook.setFee(nextFee);
            hook.poke(key);
            assertEq(_storedFee(), nextFee);
        }
    }

    function testZeroAndCoreMaximumFeesAreAllowed() public {
        _initialize();
        vm.prank(owner);
        hook.setFee(0);
        hook.poke(key);
        assertEq(_storedFee(), 0);
        vm.prank(owner);
        hook.setFee(1000000);
        hook.poke(key);
        assertEq(_storedFee(), 1000000);
    }

    function testAnotherPoolUsesSameSelectedFeeAndRefreshesIndependently() public {
        _initialize();
        PoolKey memory another = key;
        another.tickSpacing = 10;
        manager.initialize(another, uint160(1 << 96));
        vm.prank(owner);
        hook.setFee(2500);
        hook.poke(key);
        (,,, uint24 anotherFee) = manager.getSlot0(another.toId());
        assertEq(anotherFee, 500);
        hook.poke(another);
        (,,, anotherFee) = manager.getSlot0(another.toId());
        assertEq(anotherFee, 2500);
    }

    function testStandardOwnershipTransferImmediatelyMovesFeeControl() public {
        vm.prank(owner);
        hook.transferOwnership(successor);
        assertEq(hook.owner(), successor);
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, owner));
        hook.setFee(2500);
        vm.prank(successor);
        hook.setFee(2500);
        assertEq(hook.fee(), 2500);
    }

    function testStandardRenunciationDisablesFutureFeeSelection() public {
        vm.prank(owner);
        hook.renounceOwnership();
        assertEq(hook.owner(), address(0));
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, owner));
        hook.setFee(2500);
    }

    function testDirectCallbackCannotBypassManager() public {
        vm.expectRevert();
        hook.afterInitialize(owner, key, uint160(1 << 96), 0);
    }

    function testPoolMustUseDynamicMode() public {
        PoolKey memory wrong = key;
        wrong.fee = 500;
        vm.expectRevert();
        manager.initialize(wrong, uint160(1 << 96));
    }

    function testExistingPoolCannotBeReinitialized() public {
        _initialize();
        vm.expectRevert();
        manager.initialize(key, uint160(2 << 96));
        assertEq(_storedFee(), 500);
    }

    function testZeroOwnerRejected() public {
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableInvalidOwner.selector, address(0)));
        _deploy(address(0));
    }

    function testLiquidityAndBothSwapDirectionsRemainAvailableAfterFeeChange() public {
        _initialize();
        MintableToken implementation = new MintableToken();
        vm.etch(ALEO, address(implementation).code);
        vm.etch(USDT, address(implementation).code);
        MintableToken(ALEO).mint(address(this), 1e18);
        MintableToken(USDT).mint(address(this), 1e18);
        PoolModifyLiquidityTest liquidityRouter = new PoolModifyLiquidityTest(manager);
        PoolSwapTest swapRouter = new PoolSwapTest(manager);
        MintableToken(ALEO).approve(address(liquidityRouter), type(uint256).max);
        MintableToken(USDT).approve(address(liquidityRouter), type(uint256).max);
        MintableToken(ALEO).approve(address(swapRouter), type(uint256).max);
        MintableToken(USDT).approve(address(swapRouter), type(uint256).max);
        liquidityRouter.modifyLiquidity(key, ModifyLiquidityParams(-120, 120, 1e12, bytes32(0)), "");
        vm.prank(owner);
        hook.setFee(5000);
        hook.poke(key);
        swapRouter.swap(
            key, SwapParams(true, -10000, TickMath.MIN_SQRT_PRICE + 1), PoolSwapTest.TestSettings(false, false), ""
        );
        swapRouter.swap(
            key, SwapParams(false, -10000, TickMath.MAX_SQRT_PRICE - 1), PoolSwapTest.TestSettings(false, false), ""
        );
        liquidityRouter.modifyLiquidity(key, ModifyLiquidityParams(-120, 120, -int256(1e12), bytes32(0)), "");
        assertEq(_storedFee(), 5000);
    }
}
