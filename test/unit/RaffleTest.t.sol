// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {DeployRaffle} from "../../script/DeployRaffle.s.sol";
import {Raffle} from "../../src/Raffle.sol";
import {Test, console} from "forge-std/Test.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {Vm} from "forge-std/Vm.sol";
import {VRFCoordinatorV2Mock} from "@chainLink/contracts/src/v0.8/mocks/VRFCoordinatorV2Mock.sol";

contract RaffleTest is Test {
    /** Events */
    event EnteredRaffle(address indexed player);

    Raffle raffle;
    address public player = makeAddr("player");
    uint256 public constant STARTING_BALANCE = 10 ether;
    HelperConfig helperConfig;
    uint256 private entranceFee;
    uint256 private interval;
    address private vrfCoordinator;
    bytes32 private gasLane;
    uint64 private subscriptionId;
    uint32 private callbackGasLimit;
    address link;

    function setUp() external {
        DeployRaffle deployer = new DeployRaffle();
        (raffle, helperConfig) = deployer.run();
        (
            entranceFee,
            interval,
            vrfCoordinator,
            gasLane,
            subscriptionId,
            callbackGasLimit,
            link
        ) = helperConfig.activeNetworkConfig();
        vm.deal(player, STARTING_BALANCE);
    }

    function testRaffleInitializesInOpenRaffleState() public view {
        assert(raffle.getRaffleState() == Raffle.RaffleState.OPEN);
    }

    function testRaffleRevertsWhenYouDontPayEnough() public {
        // Arrange
        vm.prank(player);
        // Act
        vm.expectRevert(Raffle.Raffle__NotEnoughEthSent.selector);
        raffle.enterRaffle();
        // Assert
    }

    function testRaffleRecordsPlayerWhenEntered() public {
        vm.prank(player);
        raffle.enterRaffle{value: entranceFee}();
        address playerRecorded = raffle.getPlayer(0);
        assert(playerRecorded == player);
    }

    function testEmitsEventWhenEnteredRaffle() public {
        vm.prank(player);
        vm.expectEmit(true, false, false, false, address(raffle));
        emit EnteredRaffle(player);
        raffle.enterRaffle{value: entranceFee}();
    }

    function testCantEnterWhenRaffleIsCalculating() public {
        vm.prank(player);
        raffle.enterRaffle{value: entranceFee}();
        vm.warp(block.timestamp + interval + 1); // simulate time passing
        vm.roll(block.number + 1); // simulate block passing
        raffle.performUpkeep(""); // should enter calculating state
        vm.expectRevert(Raffle.Raffle_NotOpen.selector);
        vm.prank(player);
        raffle.enterRaffle{value: entranceFee}();
    }

    function testCheckUpkeepReturnsFalseIfItHasNoBalance() public {
        // Arrange
        vm.warp(block.timestamp + interval + 1); // simulate time passing
        vm.roll(block.number + 1); // simulate block passing
        // Act
        (bool upkeepNeeded, ) = raffle.checkUpkeep("");
        // Assert
        assertFalse(upkeepNeeded);
    }

    function testCheckUpkeepReturnsFalseIfRaffleNotOpen() public {
        // Arrange
        vm.prank(player);
        raffle.enterRaffle{value: entranceFee}();
        vm.warp(block.timestamp + interval + 1); // simulate time passing
        vm.roll(block.number + 1); // simulate block passing
        raffle.performUpkeep(""); // should enter calculating state
        // Act
        (bool upkeepNeeded, ) = raffle.checkUpkeep("");
        // Assert
        assertFalse(upkeepNeeded);
    }

    function testCheckUpkeepReturnsFalseIfEnoughTimeHasntPassed() public {
        // Arrange
        vm.prank(player);
        raffle.enterRaffle{value: entranceFee}();
        vm.warp(block.timestamp + interval - 1); // simulate time passing
        vm.roll(block.number + 1); // simulate block passing
        // Act
        (bool upkeepNeeded, ) = raffle.checkUpkeep("");
        // Assert
        assertFalse(upkeepNeeded);
    }

    function testCheckUpkeepReturnsTrueWhenParametersAreGood() public {
        // Arrange
        vm.prank(player);
        raffle.enterRaffle{value: entranceFee}();
        vm.warp(block.timestamp + interval + 1); // simulate time passing
        vm.roll(block.number + 1); // simulate block passing
        // Act
        (bool upkeepNeeded, ) = raffle.checkUpkeep("");
        // Assert
        assertTrue(upkeepNeeded);
    }

    function testPerformUpkeepCanOnlyRunIfCheckUpkeepIsTrue() public {
        // Arrange
        vm.prank(player);
        raffle.enterRaffle{value: entranceFee}();
        vm.warp(block.timestamp + interval + 1); // simulate time passing
        vm.roll(block.number + 1); // simulate block passing
        // Act
        raffle.performUpkeep("");
        // Assert
    }

    function testPerformUpkeepRevertsIfCheckUpkeepIsFalse() public {
        uint256 currentBallance = 0;
        uint256 numPlayers = 0;
        Raffle.RaffleState raffleState = Raffle.RaffleState.OPEN;
        vm.expectRevert(
            abi.encodeWithSelector(
                Raffle.Raffle_UpkeepNotNeeded.selector,
                currentBallance,
                numPlayers,
                raffleState
            )
        );
        raffle.performUpkeep("");
    }

    modifier raffleEnteredAndTimePassed() {
        vm.prank(player);
        raffle.enterRaffle{value: entranceFee}();
        vm.warp(block.timestamp + interval + 1); // simulate time passing
        vm.roll(block.number + 1); // simulate block passing
        _;
    }

    function testPerformUpkeepUpdatesRaffleStateAndEmitsRequestId()
        public
        raffleEnteredAndTimePassed
    {
        // Act
        vm.recordLogs();
        raffle.performUpkeep("");
        Vm.Log[] memory entries = vm.getRecordedLogs();
        bytes32 requestId = entries[1].topics[1];
        Raffle.RaffleState state = raffle.getRaffleState();
        // Assert
        assert(uint256(requestId) > 0);
        assert(state == Raffle.RaffleState.CALCULATING);
    }

    function testFulfillRandomWordsCanOnlyBeCalledAfterPerformUpkeep(uint256 randomRequestId) public raffleEnteredAndTimePassed {
        // Arrange
        vm.expectRevert("nonexistent request");
        VRFCoordinatorV2Mock(vrfCoordinator).fulfillRandomWords(randomRequestId, address(raffle));
    }

    function testFulfillRandomWordsPicksAWinnerResetsAndSendsMoney() public raffleEnteredAndTimePassed {
        // add additional entrants
        for (uint256 i = 1; i <= 5; i++) {
            address playerx = address(uint160(i));
            hoax(player, STARTING_BALANCE);
            raffle.enterRaffle{value: entranceFee}();
        }
        uint256 prize = 5 * entranceFee;

        // kick off a request for a random number
        vm.recordLogs();
        raffle.performUpkeep("");
        Vm.Log[] memory entries = vm.getRecordedLogs();
        bytes32 requestId = entries[1].topics[1];
        uint256 previousTimestamp = raffle.getLastTimestamp();

        // pretend to be chainlink to get a random number and pick a winner
        VRFCoordinatorV2Mock(vrfCoordinator).fulfillRandomWords(uint256(requestId), address(raffle));

        // Assert
        assert(raffle.getLastTimestamp() > previousTimestamp);
        assert(raffle.getRaffleState() == Raffle.RaffleState.OPEN);
        assert(raffle.getRecentWinner() != address(0));
        assert(raffle.getRecentWinner().balance == STARTING_BALANCE + prize);
    }
}
