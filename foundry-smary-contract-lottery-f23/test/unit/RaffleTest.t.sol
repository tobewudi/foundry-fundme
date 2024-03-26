// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Test, console} from "forge-std/Test.sol";
import {DeployRaffle} from "../../script/DeployRaffle.s.sol";
import {Raffle} from "../../src/Raffle.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {Vm} from "forge-std/Vm.sol";
import {VRFCoordinatorV2Mock} from "@chainlink/contracts/src/v0.8/mocks/VRFCoordinatorV2Mock.sol";

contract RaffleTest is Test {
    Raffle raffle;
    HelperConfig helperConfig;

    uint256 entranceFee;
    uint256 interval;
    address vrfCoordinator;
    bytes32 gasLane;
    uint64 subscriptionId;
    uint32 callbackGasLimit;
    address link;
    uint256 deployerkey;

    //初始化一个测试对象。
    address public PLAYER = makeAddr("player");
    uint256 public constant STARTING_USER_BALANCE = 10 ether;
    /*Event */
    event EnteredRaffle(address indexed player);

    //先通过setUp()初始化测试所需函数
    function setUp() external {
        DeployRaffle deployer = new DeployRaffle();
        (raffle, helperConfig) = deployer.run();
        vm.deal(PLAYER, STARTING_USER_BALANCE);
        //将helperConfig引入后，就可以获取所有变量，并后续用于测试。

        (
            entranceFee,
            interval,
            vrfCoordinator,
            gasLane,
            subscriptionId,
            callbackGasLimit,
            link,
            // deployerkey
            //注意，activeNetworkConfig实际上是一个struct，不是函数

        ) = helperConfig.activeNetworkConfig();
    }

    //skip的原因在于我们还是用的v2mock，在政治的VRF里，fulfillrandom拥有不一样的输入要求。所以这里我们选择跳过
    modifier skipFork() {
        if (block.chainid != 31337) {
            return;
        }
        _;
    }

    //测试初始状态是否为open。
    function testRaffleInitializesInOpenState() public {
        vm.startBroadcast();
        // assertEq(raffle.getRaffleState(),Raffle.RaffleState.OPEN);
        /**assertEq function assertEq(<type> a, <type> b) internal;
         * 其中 <type> 可以是 address, bytes32, int, uint 断言 a 等于 b.
         * 这里不能用assertEq原因是 raffle.getRaffleState()返回的是一个枚举*/
        assert(raffle.getRaffleState() == Raffle.RaffleState.OPEN);
        vm.stopBroadcast();
    }

    function testRaffleRevertsWhenYouDontPayEnough() public {
        //Arrange
        vm.prank(PLAYER);
        //Act /Assert
        vm.expectRevert(Raffle.Raffle__NotEnoughEthSent.selector);
        raffle.enterRaffle();
    }

    function testRaffleRecordsPlayerWhenTheyEnter() public {
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
        address playerRecord = raffle.getPlayer(0);
        assert(playerRecord == PLAYER);
        // assert(raffle.getPlayer(0) == PLAYER);
        /**这种方法多了一步赋值操作，但它可以在断言失败时提供更多的上下文信息，特别是在调试复杂的测试案例时。例如，如果assert失败了，你可能想要检查playerRecord的值来帮助确定问题所在，尤其是在不支持详细断言错误信息的测试环境中。此外，将值赋给一个变量还允许你在断言失败之前对该变量进行其他操作或检查，提供更灵活的测试逻辑。 */
    }

    function testEmitsEventOnEntrance() public {
        vm.prank(PLAYER);
        //expectEmit()希望在这一条下面的emit可以在emit后的执行语句中被触发。
        //     function expectEmit(
        //     bool checkTopic1,
        //     bool checkTopic2,
        //     bool checkTopic3,
        //     bool checkData,
        //     address emitter
        //     ) external;
        //参数 true 和 false 用于指定在断言期间应该检查哪些部分的事件数据。
        vm.expectEmit(true, false, false, false, address(raffle));
        emit EnteredRaffle(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
    }

    function testCantEnterWhenRaffleIsCalculating() public {
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
        //vm.warp()区块
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);
        raffle.performUpkeep("");
        vm.expectRevert(Raffle.Raffle__RaffleNotOpen.selector);
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
        //test is failed,we need createsubscription.
    }

    //checkUpkeep
    function testcheckUpkeepReturnsFlaseIfIthasNoBalance() public {
        //Arrange
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);
        //Act
        //要测试没有余额，就是不传入余额，直接调用。
        (bool upkeepNeeded, ) = raffle.checkUpkeep("");
        //Assert
        assert(!upkeepNeeded);
    }

    function testCheckUpkeepReturnsFalseIfRaffleNotOpen() public {
        //Arrange
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);
        //运行结果是s_raffleState = RaffleState.CALCULATING;
        raffle.performUpkeep("");
        //Act
        //运行raffle.checkUpkeep("");因为RaffleState.CALCULATING，所以返回的upkeepNeeded is false
        (bool upkeepNeeded, ) = raffle.checkUpkeep("");
        assert(upkeepNeeded == false);
        //assert(!upkeepNeeded);
        //Assert
    }

    function testCheckUpkeepReturnsFalseIfEnoughTimeHasNotPassed() public {
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
        vm.warp(block.timestamp + 1);
        vm.roll(block.number + 1);
        (bool upkeepNeeded, ) = raffle.checkUpkeep("");
        assert(upkeepNeeded == false);
    }

    modifier passIntervalTime() {
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
        vm.warp(block.timestamp + interval + 1);
        _;
    }

    function testCheckUpkeepReturnsTrueWhenParametersAreGood() public {
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);
        (bool upkeepNeeded, ) = raffle.checkUpkeep("");
        assert(upkeepNeeded == true);
    }

    function testPerformUpkeepCanOnlyRunIfCheckUpkeepIsTrue()
        public
        passIntervalTime
    {
        raffle.performUpkeep("");
    }

    function testPerformUpkeepRevertsIfCheckUpkeepIsFalse() public {
        //Arrage
        uint256 currentBalance = 0;
        uint256 numberPlayer = 0;
        uint256 rState = 0;
        //Act /Assert
        vm.expectRevert(
            abi.encodeWithSelector(
                //返回有参数的error需要用到abi.encodeWithSelector
                Raffle.Raffle__UpkeepNotNeeded.selector,
                currentBalance,
                numberPlayer,
                rState
            )
        );
        raffle.performUpkeep("");
    }

    function testPerformUpkeepUpdatesRaffleStateAndEmitsRequestId()
        public
        passIntervalTime
    {
        //Act
        //告诉虚拟机开始记录所有已发出的事件。要访问它们，请使用 getRecordedLogs。
        vm.recordLogs();
        raffle.performUpkeep("");
        Vm.Log[] memory entries = vm.getRecordedLogs();
        //所有时间日志都是bytes32.注意entries[1]是为了跳过requestRandomWords（）里面的emit,而topics[1]是为了锁定subId
        bytes32 requestId = entries[1].topics[1];
        Raffle.RaffleState rState = raffle.getRaffleState();
        //Assert
        //requestId默认为0
        assert(uint256(requestId) > 0);
        //
        assert(uint256(rState) == 1);
        // assert(rState == Raffle.RaffleState.CALCULATING);
    }

    function testFulfillRandomWordsCanOnlyBeCalledAfterPerformUpkeep(
        uint256 randomRequestId
    ) public passIntervalTime skipFork {
        //Array
        vm.expectRevert("nonexistent request");
        //Acc
        VRFCoordinatorV2Mock(vrfCoordinator).fulfillRandomWords(
            randomRequestId,
            address(raffle)
        );
        //Assert
    }

    function testFulfillRandomWordsPicksAWinnerResetsAndSendsMoney()
        public
        passIntervalTime
        skipFork
    {
        //准备再加5人，一共6人参与抽奖
        uint256 additionalEntrants = 5;
        uint256 startingIndex = 1;
        for (
            uint256 i = startingIndex;
            i < startingIndex + additionalEntrants;
            i++
        ) {
            address player = address(uint160(i));
            //利用hoax赋予代币以及发挥prank的作用。
            hoax(player, STARTING_USER_BALANCE);
            raffle.enterRaffle{value: entranceFee}();
        }
        //pretend to be chainlink vrf to get random number & pick winner
        //first，we should get requestId
        //We should subtract the entry fee for this game
        uint256 prize = entranceFee * (additionalEntrants);

        vm.recordLogs();
        raffle.performUpkeep("");
        Vm.Log[] memory entries = vm.getRecordedLogs();
        bytes32 requestId = entries[1].topics[1];
        //利用get函数获取当前timestap
        uint256 previousTimeStamp = raffle.getLastTimeStamp();

        VRFCoordinatorV2Mock(vrfCoordinator).fulfillRandomWords(
            uint256(requestId),
            address(raffle)
        );
        //Assert
        assert(uint256(raffle.getRaffleState()) == 0);
        assert(raffle.getLengthOfPlayers() == 0);
        assert(raffle.getRecentWinner() != address(0));
        assert(raffle.getLastTimeStamp() > previousTimeStamp);
        assert(
            raffle.getRecentWinner().balance == prize + STARTING_USER_BALANCE
        );
    }
}
