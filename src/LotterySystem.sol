// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.4;

import {VRFV2PlusWrapperConsumerBase} from "@chainlink/contracts/src/v0.8/vrf/dev/VRFV2PlusWrapperConsumerBase.sol";
import {VRFV2PlusClient} from "@chainlink/contracts/src/v0.8/vrf/dev/libraries/VRFV2PlusClient.sol";

contract LotterySystem is VRFV2PlusWrapperConsumerBase {
    struct Lottery {
        uint256 deadline;
        uint256 totalAmount;
        bool isFinished;
        address[] users;
    }

    mapping(uint256 => mapping(address => bool)) private alreadyParticipants;
    mapping(uint256 => uint256) private vrfRequests;
    Lottery[] private lotteryList;

    error LotteryIsEnded();
    error AlreadyParticipant();
    error InvalidDuration();
    error InvalidAmount();
    error InvalidLottery();
    error LotteryIsActive();
    error LotteryAlreadyFinished();
    error NotEnoughValueToCoverVRF(uint256 requestedAmount);

    event Created(uint256 id);
    event Bought(address buyer, uint256 amount, uint256 lotteryId);
    event Finished(address winner, uint256 amount, uint256 lotteryId);
    event FinishedEmpty(uint256 lotteryId);

    constructor(address vrfWrapper) VRFV2PlusWrapperConsumerBase(vrfWrapper) {}

    function createLottery(uint256 duration) external returns (uint256) {
        if (duration <= 0) revert InvalidDuration();

        Lottery memory lottery;
        lottery.deadline = block.timestamp + duration;

        lotteryList.push(lottery);
        uint256 lotteryId = lotteryList.length - 1;

        emit Created(lotteryId);
        return lotteryId;
    }

    function buy(uint256 lotteryId) external payable {
        if (msg.value <= 0) revert InvalidAmount();

        if (!isLotteryExist(lotteryId)) {
            revert InvalidLottery();
        }

        if (!isLotteryActive(lotteryId)) {
            revert LotteryIsEnded();
        }

        if (isAddressParticipant(msg.sender, lotteryId)) {
            revert AlreadyParticipant();
        }

        if (isLotteryFinished(lotteryId)) {
            revert LotteryAlreadyFinished();
        }

        Lottery storage lottery = lotteryList[lotteryId];

        lottery.users.push(msg.sender);
        lottery.totalAmount += msg.value;
        alreadyParticipants[lotteryId][msg.sender] = true;

        emit Bought(msg.sender, msg.value, lotteryId);
    }

    function requestFinish(uint256 lotteryId) external payable returns (uint256) {
        if (!isLotteryExist(lotteryId)) {
            revert InvalidLottery();
        }

        if (isLotteryActive(lotteryId)) {
            revert LotteryIsActive();
        }

        if (isLotteryFinished(lotteryId)) {
            revert LotteryAlreadyFinished();
        }

        Lottery storage lottery = lotteryList[lotteryId];
        lottery.isFinished = true;

        if (lottery.users.length == 0) {
            emit FinishedEmpty(lotteryId);
            return 0;
        } else if (lottery.users.length == 1) {
            address winner = lottery.users[0];
            uint256 amount = lottery.totalAmount;

            payable(winner).transfer(amount);
            emit Finished(winner, amount, lotteryId);
            return 0;
        }

        bytes memory extraArgs = VRFV2PlusClient._argsToBytes(VRFV2PlusClient.ExtraArgsV1({nativePayment: true}));
        (uint256 requestId, uint256 requestPriceInNative) = requestRandomnessPayInNative(30000, 3, 1, extraArgs);
        if (msg.value < requestPriceInNative) {
            revert NotEnoughValueToCoverVRF(requestPriceInNative);
        }

        uint256 refundAmount = msg.value - requestPriceInNative;
        payable(msg.sender).transfer(refundAmount);

        vrfRequests[requestId] = lotteryId;
        return requestId;
    }

    function fulfillRandomWords(uint256 requestId, uint256[] memory randomWords) internal override {
        uint256 seed = randomWords[0];
        uint256 lotteryId = vrfRequests[requestId];

        Lottery storage lottery = lotteryList[lotteryId];
        address winner = lottery.users[seed % lottery.users.length];
        uint256 amount = lottery.totalAmount;

        payable(winner).transfer(amount);
        emit Finished(winner, amount, lotteryId);
    }

    function getLottery(uint256 lotteryId) public view returns (Lottery memory) {
        return lotteryList[lotteryId];
    }

    function isLotteryExist(uint256 lotteryId) public view returns (bool) {
        return lotteryId >= 0 && lotteryId < lotteryList.length;
    }

    function isAddressParticipant(address addr, uint256 lotteryId) public view returns (bool) {
        return alreadyParticipants[lotteryId][addr];
    }

    function isLotteryActive(uint256 lotteryId) public view returns (bool) {
        return block.timestamp < lotteryList[lotteryId].deadline;
    }

    function isLotteryFinished(uint256 lotteryId) public view returns (bool) {
        return lotteryList[lotteryId].isFinished;
    }
}
