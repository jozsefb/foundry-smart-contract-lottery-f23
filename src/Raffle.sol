// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.18;

import {VRFCoordinatorV2Interface} from "@chainLink/contracts/src/v0.8/interfaces/VRFCoordinatorV2Interface.sol";
import {VRFConsumerBaseV2} from "@chainLink/contracts/src/v0.8/VRFConsumerBaseV2.sol";

/**
 * @title Raffle
 * @author Jozsef Benczedi
 * @notice
 */
contract Raffle is VRFConsumerBaseV2 {
    /** Errors */
    error Raffle__NotEnoughEthSent();
    error Raffle__TransferFailed();
    error Raffle_NotOpen();
    error Raffle_UpkeepNotNeeded(uint256 currentBalance, uint256 numPlayers, RaffleState raffleState);

    /** Type Declaratons */
    enum RaffleState {
        OPEN, // 0
        CALCULATING, // 1
        CLOSED // 2
    }

    /** State Variables */
    uint16 private constant REQUEST_CONFIRMATIONS = 3;
    uint32 private constant NUM_WORDS = 1;

    uint256 private immutable entranceFee;
    uint256 private immutable interval;
    VRFCoordinatorV2Interface private immutable vrfCoordinator;
    bytes32 private immutable gasLane;
    uint64 private immutable subscriptionId;
    uint32 private immutable callbackGasLimit;

    address payable[] private players;
    uint256 private lastTimestamp;
    address private recentWinner;
    RaffleState private raffleState = RaffleState.OPEN;

    /** Events */
    event EnteredRaffle(address indexed player);
    event PickedWinner(address indexed winner);
    event RequestRaffleWinner(uint256 indexed requestId);

    /** Functions */
    constructor(
        uint256 _entranceFee,
        uint256 _interval,
        address _vrfCoordinator,
        bytes32 _gasLane,
        uint64 _subscriptionId,
        uint32 _callbackGasLimit
    ) VRFConsumerBaseV2(_vrfCoordinator) {
        entranceFee = _entranceFee;
        interval = _interval;
        lastTimestamp = block.timestamp;
        vrfCoordinator = VRFCoordinatorV2Interface(_vrfCoordinator);
        gasLane = _gasLane;
        subscriptionId = _subscriptionId;
        callbackGasLimit = _callbackGasLimit;
    }

    function enterRaffle() external payable {
        if (msg.value < entranceFee) {
            revert Raffle__NotEnoughEthSent();
        }
        if (raffleState != RaffleState.OPEN) {
            revert Raffle_NotOpen();
        }
        players.push(payable(msg.sender));
        emit EnteredRaffle(msg.sender);
    }

    /** When is the winner supposed to be picked */
    function checkUpkeep(bytes memory /* checkData */) public view returns (bool upkeepNeeded, bytes memory /* checkData */) {
        bool timePassed = block.timestamp - lastTimestamp >= interval;
        bool isOpen = raffleState == RaffleState.OPEN;
        bool hasPlayers = players.length > 0;
        bool hasBalance = address(this).balance > 0;
        upkeepNeeded = timePassed && isOpen && hasPlayers && hasBalance;
    }

    function performUpkeep(bytes calldata /* performData */) external {
        (bool upkeepNeeded, ) = checkUpkeep("");
        if (!upkeepNeeded) {
            revert Raffle_UpkeepNotNeeded(address(this).balance, players.length, raffleState);
        }
        if (block.timestamp - lastTimestamp < interval) {
            revert();
        }
        raffleState = RaffleState.CALCULATING;
        // 1. request random number
        // 2. callback function: pick winner
        uint256 requestId = vrfCoordinator.requestRandomWords(
            gasLane,
            subscriptionId,
            REQUEST_CONFIRMATIONS,
            callbackGasLimit,
            NUM_WORDS
        );
        emit RequestRaffleWinner(requestId);
    }

    // CEI: Checks, Effects, Interactions
    function fulfillRandomWords(
        uint256 requestId,
        uint256[] memory randomWords
    ) internal override {
        // Checks
        // require -> revert
        // Effects
        uint256 randomWinnerIndex = randomWords[0] % players.length;
        address payable winner = players[randomWinnerIndex];
        recentWinner = winner;
        players = new address payable[](0);
        lastTimestamp = block.timestamp;
        raffleState = RaffleState.OPEN;
        emit PickedWinner(winner); // events before interactions or after?
        // Interactions (Other contracts)
        (bool success, ) = winner.call{value: address(this).balance}("");
        if (!success) {
            revert Raffle__TransferFailed();
        }
    }

    /**
     * Getters & Setters
     */

    function getEntranceFee() external view returns (uint256) {
        return entranceFee;
    }

    function getRaffleState() external view returns (RaffleState) {
        return raffleState;
    }

    function getPlayer(uint256 index) external view returns (address) {
        return players[index];
    }

    function getLastTimestamp() external view returns (uint256) {
        return lastTimestamp;
    }

    function getRecentWinner() external view returns (address) {
        return recentWinner;
    }
}
