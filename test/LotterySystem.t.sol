// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.4;

import {Test} from "forge-std/Test.sol";
import {LotterySystem} from "../src/LotterySystem.sol";

contract LotterySystemTest is Test {
    LotterySystem lotterySystem;
    uint256 baseFork;
    uint256 constant MINUTE_DURATION = 60;
    address constant ALICE = address(0x1);
    address constant BOB = address(0x2);
    address constant JACK = address(0x3);
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
    }

    function test_buy() public {
        uint256 lotteryId = lotterySystem.createLottery(MINUTE_DURATION);
        assertEq(lotterySystem.getBalance(), 0);

        hoax(ALICE, 100 ether);
        lotterySystem.buy{value: 1 ether}(lotteryId);

        LotterySystem.Lottery memory lottery = lotterySystem.getLottery(lotteryId);
        assertEq(lotterySystem.getBalance(), 1 ether);
        assertEq(lottery.totalAmount, 1 ether);
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
        uint256 requestId = lotterySystem.requestFinish{value: 1 ether}(lotteryId);
        assert(lotterySystem.getLottery(lotteryId).isFinished);

        uint256[] memory randomWords = new uint256[](1);
        randomWords[0] = 1337;

        uint256 bobBalanceBefore = BOB.balance;
        vm.prank(BASE_VRF_WRAPPER);
        lotterySystem.rawFulfillRandomWords(requestId, randomWords);
        uint256 bobBalanceAfter = BOB.balance;

        assertEq(lotterySystem.getBalance(), 0);
        assertEq(bobBalanceAfter, bobBalanceBefore + 3 ether);
        assertEq(ALICE.balance, 99 ether);
    }
}
