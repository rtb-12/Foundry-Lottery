// Layout of Contract:
// version
// imports
// errors
// interfaces, libraries, contracts
// Type declarations
// State variables
// Events
// Modifiers
// Functions

// Layout of Functions:
// constructor
// receive function (if exists)
// fallback function (if exists)
// external
// public
// internal
// private
// view & pure functions

// SPDX-License-Identifier: MIT License
pragma solidity ^0.8.18;

import {VRFCoordinatorV2Interface} from "@chainlink/contracts/src/v0.8/vrf/interfaces/VRFCoordinatorV2Interface.sol";
import {VRFConsumerBaseV2} from "@chainlink/contracts/src/v0.8/vrf/VRFConsumerBaseV2.sol";
import {AutomationCompatibleInterface} from "@chainlink/contracts/src/v0.8/automation/AutomationCompatible.sol";

/**
 * @title Raffle
 * @author Be4ST
 * @dev A contract for a raffle
 */

contract Raffle is VRFConsumerBaseV2 {
    /* State Variables */
    uint16 private constant REQUESTCONFORMATION = 2;
    uint32 private constant NUMWORDS = 1;

    VRFCoordinatorV2Interface private immutable i_vrfCoordinator;
    uint256 private immutable i_entranceFee;
    uint256 private s_lastTimeStamp;
    uint256 private immutable i_interval;
    bytes32 private i_gaslane;
    uint64 private i_subscriptionId;
    uint32 private i_callbackGasLimit;
    uint256 private s_recentWinner;
    address payable[] private s_participants;
    RaffleState private s_raffleState;

    /* Errors */
    error Raffle__NotEnoughEntranceFee();
    error Raffle__TransferFailed();
    error NotUpKeepNeeded(
        uint256 timestamp,
        uint256 lastTimeStamp,
        uint256 interval,
        RaffleState raffleState,
        uint256 participantsLength,
        uint256 balance
    );
    error Raffle__RaffleClosed();

    /* Type Declaration */
    enum RaffleState {
        OPEN,
        CALCULATING_WINNER
    }

    /* Events*/
    event enteredRaffle(address indexed participant);
    event winnerPicked(address indexed winner);

    constructor(
        uint256 entranceFee_,
        address vrfCoordinator_,
        uint256 interval_,
        bytes32 gaslane_,
        uint64 subscriptionId_,
        uint32 callbackGasLimit
    ) VRFConsumerBaseV2(vrfCoordinator_) {
        i_interval = interval_;
        i_vrfCoordinator = VRFCoordinatorV2Interface(vrfCoordinator_);
        i_entranceFee = entranceFee_;
        s_lastTimeStamp = block.timestamp;
        i_gaslane = gaslane_;
        i_subscriptionId = subscriptionId_;
        i_callbackGasLimit = callbackGasLimit;
        s_raffleState = RaffleState.OPEN;
    }

    function enterRaffle() public payable {
        if (msg.value < i_entranceFee) {
            revert Raffle__NotEnoughEntranceFee();
        }
        if (RaffleState.CALCULATING_WINNER == s_raffleState) {
            revert Raffle__RaffleClosed();
        }
        s_participants.push(payable(msg.sender));

        emit enteredRaffle(msg.sender);
        // Enter the raffle
    }

    function checkUpkeep(
        bytes memory /* checkData */
    ) public view returns (bool upkeepNeeded, bytes memory /* performData */) {
        bool timeHasPassed = block.timestamp - s_lastTimeStamp >= i_interval;
        bool raffleIsOpen = s_raffleState == RaffleState.OPEN;
        bool numberOfParticipants = s_participants.length > 0;
        bool balanceIsNotZero = address(this).balance > 0;
        upkeepNeeded =
            timeHasPassed &&
            raffleIsOpen &&
            numberOfParticipants &&
            balanceIsNotZero;
        return (upkeepNeeded, bytes("0x00"));
    }

    function performUpkeep(bytes calldata /* performData */) external {
        (bool upkeepNeeded, ) = checkUpkeep("");
        if (!upkeepNeeded) {
            revert NotUpKeepNeeded(
                block.timestamp,
                s_lastTimeStamp,
                i_interval,
                s_raffleState,
                s_participants.length,
                address(this).balance
            );
        }
        if (block.timestamp < s_lastTimeStamp + i_interval) {
            revert();
        }
        s_raffleState = RaffleState.CALCULATING_WINNER;
        uint256 requestId = i_vrfCoordinator.requestRandomWords(
            i_gaslane,
            i_subscriptionId,
            REQUESTCONFORMATION,
            i_callbackGasLimit,
            NUMWORDS
        );

        // Pick a winner
    }

    function fulfillRandomWords(
        uint256 _requestId,
        uint256[] memory _randomWords
    ) internal override {
        // Pick a winner
        uint256 winnerIndex = _randomWords[0] % s_participants.length;
        s_recentWinner = winnerIndex;
        (bool isSuccess, ) = s_participants[winnerIndex].call{
            value: address(this).balance
        }("");

        if (!isSuccess) {
            revert Raffle__TransferFailed();
        }
        s_raffleState = RaffleState.OPEN;
        s_participants = new address payable[](0);
        s_lastTimeStamp = block.timestamp;

        emit winnerPicked(s_participants[winnerIndex]);
    }

    /* getter function  */

    function getEntranceFee() external view returns (uint256) {
        return i_entranceFee;
    }

    function getState() external view returns (RaffleState) {
        return s_raffleState;
    }

    function getPlayers(uint256 index) external view returns (address payable) {
        return s_participants[index];
    }
}
