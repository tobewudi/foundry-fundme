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
// internal & private view & pure functions
// external & public view & pure functions

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

/**
 * @title A sample Raffle Contract
 * @author Patrick Collins
 * @notice this contract is for creating a sample raffle
 * @dev Implements Chainlink VRFv2
 */
import {VRFCoordinatorV2Interface} from "@chainlink/contracts/src/v0.8/interfaces/VRFCoordinatorV2Interface.sol";
import {VRFConsumerBaseV2} from "@chainlink/contracts/src/v0.8/vrf/VRFConsumerBaseV2.sol";

contract Raffle is VRFConsumerBaseV2 {
    /*如果某人试图通过调用 enterRaffle 函数并发送少于 i_entranceFee 的以太币，交易将会失败，并且会在交易的错误日志中记录 Raffle_NotEnoughEthSent 错误。在大多数以太坊钱包或交易查看器中，这会以某种形式展示，比如错误类型的名称或是附带的错误代码。
    值得注意的是，虽然 error 关键字提供了一种更为高效和组织化的错误处理方式，但它不允许像 require 那样动态生成错误消息。因此，当你需要返回包含动态值的详细信息时，require 可能仍然是必要的。*/
    error Raffle__NotEnoughEthSent();
    error Raffle__TransferFailed();
    error Raffle__RaffleNotOpen();
    error Raffle__UpkeepNotNeeded(
        uint256 currentBalance,
        uint256 numberPlayer,
        uint256 raffleState
    );
    /**Type declarations */
    enum RaffleState {
        OPEN,
        CALCULATING
    }
    //前期需要两个函数，1.用于购买彩票，并设置一定的购买费用。2.开奖用函数，决定谁是获奖者
    /**State Variables */
    uint16 private constant REQUEST_CONFIRMATIONS = 3;
    uint16 private constant NUM_WORDS = 1;

    //定义一个动态数组来装玩家地址。
    address payable[] s_player;
    uint256 private immutable i_interval;
    uint256 private s_lastTimeStamp;
    VRFCoordinatorV2Interface private immutable i_vrfCoordinator;
    bytes32 private immutable i_gasLane;
    uint64 private immutable i_subscriptionId;
    uint32 private immutable i_callbackGasLimit;
    uint256 private immutable i_entranceFee;
    address private s_recentWinner;
    RaffleState private s_raffleState;

    /*Events */
    //需要改变storge的时候都考虑用event
    event EnteredRaffle(address indexed player);
    event PickedWinner(address indexed winner);
    event RequestedRaffleWinner(uint256 indexed requestId);

    constructor(
        uint256 entranceFee,
        uint256 interval,
        address vrfCoordinator,
        bytes32 gasLane,
        uint64 subscriptionId,
        uint32 callbackGasLimit
    ) VRFConsumerBaseV2(vrfCoordinator) {
        i_entranceFee = entranceFee;
        i_interval = interval;
        s_lastTimeStamp = block.timestamp;
        i_vrfCoordinator = VRFCoordinatorV2Interface(vrfCoordinator);
        i_gasLane = gasLane;
        i_subscriptionId = subscriptionId;
        i_callbackGasLimit = callbackGasLimit;
        s_raffleState = RaffleState.OPEN;
    }

    function enterRaffle() external payable {
        if (msg.value < i_entranceFee) {
            revert Raffle__NotEnoughEthSent();
        }
        if (s_raffleState != RaffleState.OPEN) {
            revert Raffle__RaffleNotOpen();
        }
        s_player.push(payable(msg.sender));
        emit EnteredRaffle(msg.sender);
    }

    //When is the winner supposed to (应该) be picked?
    /**
     * @dev this is the function that the Chainlink Automation nodes(节点) call to see if it's time to perform an upkeep.
     *The following should be true for this to return true:
     *1.The time interval has passed between raffle runs
     *2.The raffle is in the OPEN state
     *3.The contract has ETH (aka, players)
     *4.(Implicit)The subscription is funded with LINK
     *5.This game has players.
     */
    //bytes memory /*performData */预留是为了更多的灵活性和扩展性，比如你可以传入一个数据来作为触发器。虽然我们这里没有用到
    function checkUpkeep(
        bytes memory /* checkData */
    ) public view returns (bool upkeepNeeded, bytes memory /*performData */) {
        //The time interval has passed between raffle runs
        bool timeHasPassed = (block.timestamp - s_lastTimeStamp) >= i_interval;
        //The raffle is in the OPEN state
        bool isOpen = RaffleState.OPEN == s_raffleState;
        //The contract has ETH (aka, players)
        bool hasBalance = address(this).balance > 0;
        bool hasPlayers = s_player.length > 0;
        upkeepNeeded = (timeHasPassed && isOpen && hasBalance && hasPlayers);
        return (upkeepNeeded, "0x0");
    }

    //1.Get a random number
    //2.Use the random number to pick a player
    //3.Be aoutomatically called
    function performUpkeep(bytes calldata /* performData */) external {
        //use checkUpkeep() to verify whether the execution conditions are met
        //check to see if enough time has passed
        (bool upkeepNeeded, ) = checkUpkeep("");
        //如果处于未开放阶段，返回指定参数信息。
        if (!upkeepNeeded) {
            revert Raffle__UpkeepNotNeeded(
                address(this).balance,
                s_player.length,
                uint256(s_raffleState)
            );
        }
        s_raffleState = RaffleState.CALCULATING;
        //chose a random player
        //random VRF actually has two steps
        //1.Request the RNG(Random number generator)
        //2.Get the random number
        //i_vrfCoordinator将调用requestRandomWords,这里需要从github import。
        uint256 requestId = i_vrfCoordinator.requestRandomWords(
            i_gasLane, //gas lane
            i_subscriptionId,
            REQUEST_CONFIRMATIONS,
            i_callbackGasLimit,
            NUM_WORDS
        );
        //此处应注意，其实requestRandomWords（）里已经包含了一个event,这里是为了测试，才多加了一个emit。
        emit RequestedRaffleWinner(requestId);
    }

    //CEI:Checks,Effects,Interactions

    function fulfillRandomWords(
        uint256 /*requestId*/,
        uint256[] memory randomWords
    ) internal override {
        uint256 indexOfWinner = randomWords[0] % s_player.length;
        address payable recentWinner = s_player[indexOfWinner];
        //为了方便查看最近的winner。设置s_recentwinner。
        s_recentWinner = recentWinner;
        //重置玩家名单
        s_player = new address payable[](0);
        //reset rafflestate == open
        s_raffleState = RaffleState.OPEN;
        //重置计时器
        s_lastTimeStamp = block.timestamp;
        (bool success, ) = recentWinner.call{value: address(this).balance}("");
        if (!success) {
            revert Raffle__TransferFailed();
        }
        emit PickedWinner(recentWinner);
    }

    /**Getter Function */
    //一个Getter函数，的基本格式应该是function <name> external view returns
    function getEntranceFee() external view returns (uint256) {
        return i_entranceFee;
    }

    function getRaffleState() external view returns (RaffleState) {
        return s_raffleState;
    }

    function getPlayer(uint256 indexOfPlayer) external view returns (address) {
        return s_player[indexOfPlayer];
    }

    function getRecentWinner() external view returns (address) {
        return s_recentWinner;
    }

    function getLengthOfPlayers() external view returns (uint256) {
        return s_player.length;
    }

    function getLastTimeStamp() external view returns (uint256) {
        return s_lastTimeStamp;
    }

    function getBalance() external view returns (uint256) {
        return address(this).balance;
    }
}
