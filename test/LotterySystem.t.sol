// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.4;

import {Test} from "forge-std/Test.sol";
import {LotterySystem} from "../src/LotterySystem.sol";

contract LotterySystemTest is Test {
    LotterySystem lotterySystem;
    uint256 baseFork;
    uint256 constant MINUTE_DURATION = 60;
    address constant ALICE = address(0x1111111111111111);
    address constant BOB = address(0x2111111111111111);
    address constant JACK = address(0x3111111111111111);
    address constant BASE_VRF_WRAPPER = address(0xb0407dbe851f8318bd31404A49e658143C982F23);

    function setUp() public {
        string memory rpcUrl = "https://mainnet.base.org";
        uint256 blockNumber = 27979710;

        baseFork = vm.createSelectFork(rpcUrl, blockNumber);
        lotterySystem = new LotterySystem(BASE_VRF_WRAPPER);
    }

    function test_createLottery() public {
        assert(!lotterySystem.isLotteryExist(0));

        uint256 lotteryId = lotterySystem.createLottery(MINUTE_DURATION);
        assert(lotterySystem.isLotteryExist(lotteryId));
        assertEq(lotteryId, 0);

        LotterySystem.Lottery memory lottery = lotterySystem.getLottery(lotteryId);
        assertEq(lottery.deadline, block.timestamp + MINUTE_DURATION);
    }

    function test_buy() public {
        uint256 lotteryId = lotterySystem.createLottery(MINUTE_DURATION);
        assertEq(lotterySystem.getBalance(), 0);

        LotterySystem.Lottery memory lottery = lotterySystem.getLottery(lotteryId);
        assertEq(lottery.totalAmount, 0);

        hoax(ALICE, 100 ether);
        lotterySystem.buy{value: 1 ether}(lotteryId);

        lottery = lotterySystem.getLottery(lotteryId);
        assertEq(lottery.totalAmount, 1 ether);
        assertEq(lotterySystem.getBalance(), 1 ether);
        assertEq(lottery.users.length, 1);
        assertEq(lottery.users[0], ALICE);
        assert(lotterySystem.isAddressParticipant(ALICE, lotteryId));
    }

    function test_requestFinish() public {
        uint256 lotteryId = lotterySystem.createLottery(MINUTE_DURATION);
        assertEq(lotterySystem.getBalance(), 0);

        hoax(ALICE, 100 ether);
        lotterySystem.buy{value: 1 ether}(lotteryId);
        assertEq(lotterySystem.getBalance(), 1 ether);

        hoax(BOB, 100 ether);
        lotterySystem.buy{value: 2 ether}(lotteryId);
        assertEq(lotterySystem.getBalance(), 3 ether);

        skip(MINUTE_DURATION);

        assert(!lotterySystem.getLottery(lotteryId).isFinished);
        hoax(JACK, 100 ether);
        uint256 balanceBefore = JACK.balance;
        lotterySystem.requestFinish{value: 1 ether}(lotteryId);
        assert(JACK.balance > (balanceBefore - 1 ether));
        assert(lotterySystem.getLottery(lotteryId).isFinished);
    }

    function test_requestFinishLotteryEmptyUsers() public {
        uint256 lotteryId = lotterySystem.createLottery(MINUTE_DURATION);

        skip(MINUTE_DURATION);
        assert(!lotterySystem.isLotteryFinished(lotteryId));

        hoax(ALICE, 100 ether);
        uint256 requestId = lotterySystem.requestFinish(lotteryId);

        assertEq(requestId, 0);
        assert(lotterySystem.isLotteryFinished(lotteryId));
    }

    function test_requestFinishLotterySingleUser() public {
        uint256 lotteryId = lotterySystem.createLottery(MINUTE_DURATION);

        hoax(ALICE, 100 ether);
        lotterySystem.buy{value: 1 ether}(lotteryId);
        assertEq(lotterySystem.getBalance(), 1 ether);

        skip(MINUTE_DURATION);

        hoax(BOB, 100 ether);
        uint256 requestId = lotterySystem.requestFinish(lotteryId);
        assertEq(ALICE.balance, 100 ether);
        assertEq(requestId, 0);
    }

    function test_fulfillRandomWords() public {
        uint256 lotteryId = lotterySystem.createLottery(MINUTE_DURATION);

        hoax(ALICE, 100 ether);
        lotterySystem.buy{value: 1 ether}(lotteryId);

        hoax(BOB, 100 ether);
        lotterySystem.buy{value: 2 ether}(lotteryId);

        assertEq(lotterySystem.getBalance(), 3 ether);

        skip(MINUTE_DURATION);

        hoax(JACK, 100 ether);
        uint256 requestId = lotterySystem.requestFinish{value: 1 ether}(lotteryId);

        uint256[] memory randomWords = new uint256[](1);
        randomWords[0] = 1337;

        uint256 balanceBefore = BOB.balance;
        vm.prank(BASE_VRF_WRAPPER);
        lotterySystem.rawFulfillRandomWords(requestId, randomWords);
        uint256 balanceAfter = BOB.balance;

        assertEq(lotterySystem.getBalance(), 0);
        assertEq(balanceAfter, balanceBefore + 3 ether);
        assertEq(ALICE.balance, 99 ether);
    }

    function testRevert_createLotteryInvalidDuration() public {
        vm.expectRevert(LotterySystem.InvalidDuration.selector);
        lotterySystem.createLottery(0);
    }

    function testRevert_buyInvalidAmount() public {
        uint256 lotteryId = lotterySystem.createLottery(MINUTE_DURATION);

        vm.expectRevert(LotterySystem.InvalidAmount.selector);
        vm.prank(ALICE);
        lotterySystem.buy(lotteryId);
    }

    function testRevert_buyInvalidLottery() public {
        vm.expectRevert(LotterySystem.InvalidLottery.selector);

        hoax(ALICE, 100 ether);
        lotterySystem.buy{value: 1 ether}(0);
    }

    function testRevert_buyLotteryIsEnded() public {
        uint256 lotteryId = lotterySystem.createLottery(MINUTE_DURATION);

        vm.expectRevert(LotterySystem.LotteryIsEnded.selector);

        skip(MINUTE_DURATION);

        hoax(ALICE, 100 ether);
        lotterySystem.buy{value: 1 ether}(lotteryId);
    }

    function testRevert_buyAlreadyParticipant() public {
        uint256 lotteryId = lotterySystem.createLottery(MINUTE_DURATION);

        hoax(ALICE, 100 ether);
        lotterySystem.buy{value: 1 ether}(lotteryId);

        vm.expectRevert(LotterySystem.AlreadyParticipant.selector);
        hoax(ALICE, 100 ether);
        lotterySystem.buy{value: 1 ether}(lotteryId);
    }

    function testRevert_requestFinishInvalidLottery() public {
        hoax(JACK, 100 ether);
        vm.expectRevert(LotterySystem.InvalidLottery.selector);
        lotterySystem.requestFinish{value: 1 ether}(0);
    }

    function testRevert_requestFinishLotteryIsActive() public {
        uint256 lotteryId = lotterySystem.createLottery(MINUTE_DURATION);

        hoax(JACK, 100 ether);
        vm.expectRevert(LotterySystem.LotteryIsActive.selector);
        lotterySystem.requestFinish{value: 1 ether}(lotteryId);
    }

    function testRevert_requestFinishLotteryAlreadyFinished() public {
        uint256 lotteryId = lotterySystem.createLottery(MINUTE_DURATION);

        hoax(ALICE, 100 ether);
        lotterySystem.buy{value: 1 ether}(lotteryId);

        hoax(BOB, 100 ether);
        lotterySystem.buy{value: 1 ether}(lotteryId);

        skip(MINUTE_DURATION);

        hoax(JACK, 100 ether);
        lotterySystem.requestFinish{value: 1 ether}(lotteryId);

        hoax(JACK, 100 ether);
        vm.expectRevert(LotterySystem.LotteryAlreadyFinished.selector);
        lotterySystem.requestFinish{value: 1 ether}(lotteryId);
    }

    function testRevert_requestFinishNotEnoughValueToCoverVRF() public {
        uint256 lotteryId = lotterySystem.createLottery(MINUTE_DURATION);

        hoax(ALICE, 100 ether);
        lotterySystem.buy{value: 1 ether}(lotteryId);

        hoax(BOB, 100 ether);
        lotterySystem.buy{value: 1 ether}(lotteryId);

        skip(MINUTE_DURATION);

        hoax(JACK, 100 ether);
        vm.expectRevert(abi.encodeWithSelector(LotterySystem.NotEnoughValueToCoverVRF.selector, 15226295827));
        lotterySystem.requestFinish(lotteryId);
    }
}
