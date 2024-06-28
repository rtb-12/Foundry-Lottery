// SPDX-License-Identifier: MIT License
pragma solidity ^0.8.18;

import {Test, console} from "forge-std/Test.sol";
import {Raffle} from "../../src/Raffle.sol";
import {DeployRaffle} from "../../script/DeployRaffle.s.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {StdCheats} from "forge-std/StdCheats.sol";
import {Vm} from "forge-std/Vm.sol";
import {VRFCoordinatorV2Mock} from "@chainlink/contracts/src/v0.8/vrf/mocks/VRFCoordinatorV2Mock.sol";


contract RaffleTest is StdCheats, Test {
    /* Errors */
    event enteredRaffle(address indexed player);
    event WinnerPicked(address indexed player);
    event requestIdPicked(uint256 indexed request);

    Raffle public raffle;
    HelperConfig public helperConfig;

    uint64 subscriptionId;
    bytes32 gasLane;
    uint256 automationUpdateInterval;
    uint256 raffleEntranceFee;
    uint32 callbackGasLimit;
    address vrfCoordinatorV2;

    address public PLAYER = makeAddr("player");
    uint256 public constant STARTING_USER_BALANCE = 10 ether;

    modifier raffleEnterAndTimePassed() {
        vm.prank(PLAYER);
        raffle.enterRaffle{value: raffleEntranceFee}();
        vm.warp(block.timestamp + automationUpdateInterval + 1);
        vm.roll(block.number + 1);
        _;
    }

    function setUp() external {
        DeployRaffle deployer = new DeployRaffle();
        (raffle, helperConfig) = deployer.run();
        vm.deal(PLAYER, STARTING_USER_BALANCE);

        (
            ,
            gasLane,
            automationUpdateInterval,
            raffleEntranceFee,
            callbackGasLimit,
            vrfCoordinatorV2, // link
            // deployerKey
            ,

        ) = helperConfig.activeNetworkConfig();
    }

    function testRaffleInitializesInOpenState() public view {
        assert(raffle.getState() == Raffle.RaffleState.OPEN);
    }

    function testRaffleRevertsWHenYouDontPayEnough() public {
        // Arrange
        vm.prank(PLAYER);
        // Act / Assert
        vm.expectRevert(Raffle.Raffle__NotEnoughEntranceFee.selector);
        raffle.enterRaffle();
    }

    function testPlayerEnteredRaffle() public {
        // Arrange
        vm.prank(PLAYER);
        // Act
        raffle.enterRaffle{value: raffleEntranceFee}();
        // Assert
        address thisPlayer = PLAYER;
        assert(thisPlayer == raffle.getPlayers(0));
    }

    function testEmitWhenPlayerEntersRaffle() public {
        vm.prank(PLAYER);
        vm.expectEmit(true,false,false ,false, address(raffle));
        emit enteredRaffle(PLAYER);
        raffle.enterRaffle{value: raffleEntranceFee}();
    }

    function testDontAllowPlayersToEnterWhileRaffleIsCalculating() public raffleEnterAndTimePassed {
        // Arrange
       
        raffle.performUpkeep("");

        // Act / Assert
        vm.expectRevert(Raffle.Raffle__RaffleClosed.selector);
        vm.prank(PLAYER);
        raffle.enterRaffle{value: raffleEntranceFee}();
    }
    function testCheckUpkeepReturnsFalseIfItHasNoBalance() public{
        vm.warp(block.timestamp + automationUpdateInterval + 1);
        vm.roll(block.number + 1);

        (bool upkeepNeeded, ) = raffle.checkUpkeep("");

        assert(upkeepNeeded == false);
    }

    function testCheckUpkeepReturnsFalseIfRaffleIsntOpen() public raffleEnterAndTimePassed{
        
        raffle.performUpkeep("");

        Raffle.RaffleState raffleState = raffle.getState();
        // Act
        (bool upkeepNeeded, ) = raffle.checkUpkeep("");
        // Assert
        assert(raffleState == Raffle.RaffleState.CALCULATING_WINNER);
        assert(upkeepNeeded == false);
    }
    function testCheckUpkeepReturnsFalseIfEnoughTimeHasntPassed() public {
        vm.prank(PLAYER);
        raffle.enterRaffle{value: raffleEntranceFee}();

        // Act
        (bool upkeepNeeded, ) = raffle.checkUpkeep("");
        // Assert
    
        assert(upkeepNeeded == false);
    }

    function testCheckUpkeepReturnsTrueWhenParametersGood() public raffleEnterAndTimePassed {
     
        // Act
        (bool upkeepNeeded, ) = raffle.checkUpkeep("");
        // Assert
     
        assert(upkeepNeeded == true);
    }

    function testPerformUpkeepCanOnlyRunIfCheckUpkeepIsTrue() public raffleEnterAndTimePassed {
       
        // Act
        // Assert
        raffle.performUpkeep("");
    }

    function testPerformUpkeepReturnsFalseWhenCheckUpKeepIsFalse() public {
        uint256 raffleBalance=0 ;
        uint256 raffleState= 0;
        uint256 numberOfPlayers=0 ;
        vm.expectRevert(
            abi.encodeWithSelector(
                Raffle.NotUpKeepNeeded.selector,
                raffleState,
                numberOfPlayers,
                raffleBalance
            )
        );
        raffle.performUpkeep("");
    }

    function testPerformUpKeepUpdatesRaffleStateAndEmitsRequesId() public raffleEnterAndTimePassed {
    
        // Act
        vm.recordLogs();
        raffle.performUpkeep("");
        Vm.Log[] memory recordEntries = vm.getRecordedLogs();
        bytes32 requestID = recordEntries[1].topics[1];

        // Assert
        assert(raffle.getState() == Raffle.RaffleState.CALCULATING_WINNER);
        assert(requestID >0);
    }

    modifier skipFork() {
        if (block.chainid != 31337) {
            return;
        }
        _;
    }


    function testFullfiilRandomWordCanBeCalledAfterPerformUpKeep(uint256 randomRequestID) public raffleEnterAndTimePassed skipFork {
 
        //Act 
        vm.expectRevert("nonexistent request");
        VRFCoordinatorV2Mock(vrfCoordinatorV2).fulfillRandomWords(
            randomRequestID,
            address(raffle));
    }

    function testFulfillRandomWordsPicksAWinnerResetsAndSendsMoney() public raffleEnterAndTimePassed skipFork {
        // Arrange
        uint256 additionalEntrants = 5;
        for (uint256 i = 1; i <= additionalEntrants; i++) {
            address player = address(uint160(i));
            hoax(player, 1 ether); // Assuming 1 ether is the starting balance for simplicity
            raffle.enterRaffle{value: raffleEntranceFee}();
        }

        uint256 prize = raffleEntranceFee * (additionalEntrants + 1); // Total prize pool
        uint256 startingBalance = PLAYER.balance; // Assuming PLAYER is a global variable representing the test account
        uint256 startingTimeStamp = raffle.getLastTimeStamp();

        // Act
        vm.recordLogs();
        raffle.performUpkeep("");
        Vm.Log[] memory entries = vm.getRecordedLogs();
        bytes32 requestId = entries[1].topics[1];

        VRFCoordinatorV2Mock(vrfCoordinatorV2).fulfillRandomWords(
            uint256(requestId),
            address(raffle)
        );

        // Assert
        address recentWinner = raffle.getRecentWinner();
        uint256 winnerBalance = recentWinner.balance;
        uint256 endingTimeStamp = raffle.getLastTimeStamp();

        assert(uint256(raffle.getState()) == 0); // Assuming RaffleState.OPEN is 0
        assert(recentWinner != address(0));
        assert(raffle.getLengthOfPlayers() == 0); // Assuming getLengthOfPlayers() is equivalent to getNumberOfPlayers()
        assert(winnerBalance == startingBalance - raffleEntranceFee + prize);
        assert(endingTimeStamp > startingTimeStamp);
    }
}
 