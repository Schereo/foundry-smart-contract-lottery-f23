// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import {DeployRaffle} from "../../script/DeployRaffle.s.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {Raffle} from "../../src/Raffle.sol";
import {Test, console} from "forge-std/Test.sol";
import {Vm, VmSafe} from "forge-std/VM.sol";
import {VRFCoordinatorV2Mock} from "@chainlink/contracts/src/v0.8/mocks/VRFCoordinatorV2Mock.sol";

contract RaffleTest is Test {
    // Events
    event EnteredRaffle(address indexed player);

    Raffle raffle;
    HelperConfig helperConfig;
    uint256 entranceFee;
    uint256 interval;
    address vrfCoordinator;
    bytes32 gasLane;
    uint64 subscriptionId;
    uint32 callbackGasLimit;

    address public PLAYER = makeAddr("player");
    uint256 public constant STARTING_USER_BALANCE = 10 ether;

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
            ,
        ) = helperConfig.activeNetworkConfig();
        vm.deal(PLAYER, STARTING_USER_BALANCE);
    }

    function testRaffleInitializedInOpenState() public view {
        assertEq(uint(raffle.getRaffleState()), uint(Raffle.RaffleState.OPEN));
    }

    // enterRaffle

    function testRaffleRevertsWhenYouDontPayEnough() public {
        vm.prank(PLAYER);
        vm.expectRevert(Raffle.Raffle__NotEnoughEthSent.selector);
        raffle.enterRaffle();
    }

    function testRaffleRecordsPlayerWhenTheyEnter() public {
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
        assertEq(raffle.getPlayer(0), PLAYER);
    }

    function testEmitsEventOnEntrance() public {
        vm.prank(PLAYER);
        vm.expectEmit(true, false, false, false, address(raffle));
        emit EnteredRaffle(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
    }

    function testCantEnterWhenRaffleIsCalculating() public {
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);
        raffle.performUpkeep("");
        vm.expectRevert(Raffle.Raffle__RaffleNotOpen.selector);
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
    }

    // checkUpKeep

    function testCheckUpReturnsFalsIfItHasNoBalance() public {
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);

        (bool upkeepNeeded, ) = raffle.checkUpKeep("");
        assert(!upkeepNeeded);
    }

    function testCheckUpKeepReturnsFalsIfNotOpen() public {
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);
        raffle.performUpkeep("");
        (bool upkeepNeeded, ) = raffle.checkUpKeep("");
        assert(!upkeepNeeded);
    }

    // performUpkeep

    function testPerformUpkeepCanOnlyRunIfCheckUpkeepIsTrue() public {
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);
        raffle.performUpkeep("");
    }

    function testPerformUpkeepRevertsIfCheckUpkeepIsFalse() public {
        uint256 currentBalance = 0;
        uint256 currentPlayers = 0;
        uint256 currentRaffleState = 0;
        vm.expectRevert(
            abi.encodeWithSelector(
                Raffle.Raffle__UpkeepNotNeeded.selector,
                currentBalance,
                currentPlayers,
                currentRaffleState
            )
        );
        raffle.performUpkeep("");
    }

    modifier raffleEnteredAndTimePassed() {
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);
        _;
    }

    // function testPerformUpkeepUpdatesRaffleStateAndEmitsRequestId()
    //     public
    //     raffleEnteredAndTimePassed
    // {
    //     vm.recordLogs();
    //     raffle.performUpkeep("");
    //     VmSafe.Log[] memory entries = vm.getRecordedLogs();
    //     bytes32 requestId = entries[1].topics[1];

    //     assert(requestId > 0);
    // }

    // FulfilfRandomWords

    modifier skipFork() {
        if (block.chainid == 31337) {
           return;
        }
        _;
    }

    function testFulfillRadomWordsCanOnlyBeCalledAfterPerformUpekeep(uint256 randomRequestId)
        public
        raffleEnteredAndTimePassed
    {
        vm.expectRevert("nonexistent request");
        VRFCoordinatorV2Mock(vrfCoordinator).fulfillRandomWords(
            randomRequestId,
            address(raffle)
        );
    }

    function testFulfillRandomWordsPicksAWinnerResetsAndSendsMoney() public raffleEnteredAndTimePassed {
        uint256 additionalEntrants = 5;
        uint256 startingIndex = 1;

        for (uint256 i = startingIndex; i < additionalEntrants; i++) {
            address player = address(uint160(i));
            hoax(player, 1 ether);
            raffle.enterRaffle{value: entranceFee}();

            VRFCoordinatorV2Mock(vrfCoordinator).fulfillRandomWords(
                1,
                address(raffle)
            );

            assert(uint256(raffle.getRaffleState()) == uint256(Raffle.RaffleState.OPEN));
        }

    }

    // ful
}
