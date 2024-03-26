// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;
import {Script, console} from "forge-std/Script.sol";
import {HelperConfig} from "./HelperConfig.s.sol";
import {VRFCoordinatorV2Mock} from "@chainlink/contracts/src/v0.8/mocks/VRFCoordinatorV2Mock.sol";
import {LinkToken} from "../test/mocks/LinkToken.sol";
//获取最近部署合约信息。
import {DevOpsTools} from "lib/foundry-devops/src/DevOpsTools.sol";

//这个合约应该包含3个主要功能，为的是和Chainlink的Automation交互，为此，我们先要创建Subscription,然后Fund it
//最后通过Addconsumer来讲我们的彩票合约添加。
contract CreateSubscription is Script {
    function createSubscriptionUsingConfig() public returns (uint64, address) {
        HelperConfig helperConfig = new HelperConfig();
        (
            ,
            ,
            address vrfCoordinator, //注意，activeNetworkConfig实际上是一个struct，不是函数
            ,
            ,
            ,
            ,
            uint256 deployerkey
        ) = helperConfig.activeNetworkConfig();
        //实例化createSubscription 并将vrfCoordinator传递过去。
        return createSubscription(vrfCoordinator, deployerkey);
    }

    function createSubscription(
        address vrfCoordinator,
        uint256 deployerkey
    ) public returns (uint64, address) {
        console.log("Creating subscription on ChainId", block.chainid);
        vm.startBroadcast(deployerkey);
        //这里传入了vrfCoordinator,由于是在本地环境模拟，需要import chetcode
        uint64 subId = VRFCoordinatorV2Mock(vrfCoordinator)
            .createSubscription();
        vm.stopBroadcast();
        console.log("Your sub Id is:", subId);
        console.log("Please update subscriptionId in HelperConfig.s.sol");
        return (subId, vrfCoordinator);
    }

    //deploy 主要函数必须先来，然后根据主要函数的需求扩写其他函数。
    function run() external returns (uint64, address) {
        //初始化参数函数
        return createSubscriptionUsingConfig();
    }
}

contract FundSubscription is Script {
    uint96 public constant FUND_AMOUNT = 3 ether;

    function fundSubscriptionUsingConfig() public {
        HelperConfig helperConfig = new HelperConfig();
        (
            ,
            ,
            address vrfCoordinator, //注意，activeNetworkConfig实际上是一个struct，不是函数
            ,
            uint64 subId,
            ,
            address link,
            uint256 deployerkey
        ) = helperConfig.activeNetworkConfig();

        if (subId == 0) {
            CreateSubscription createSub = new CreateSubscription();
            (uint64 updatedSubId, address updatedVRFv2) = createSub.run();
            subId = updatedSubId;
            vrfCoordinator = updatedVRFv2;
            console.log(
                "New SubId Created! ",
                subId,
                "VRF Address: ",
                vrfCoordinator
            );
        }

        fundSubscription(vrfCoordinator, subId, link, deployerkey);
    }

    function fundSubscription(
        address vrfCoordinator,
        uint64 subId,
        address link,
        uint256 deployerkey
    ) public {
        console.log("Funding subscription:", subId);
        console.log("Using vrfCoordinator:", vrfCoordinator);
        console.log("On ChainID:", block.chainid);
        //本地chainid
        if (block.chainid == 31337) {
            vm.startBroadcast(deployerkey);
            //构建虚拟环境
            VRFCoordinatorV2Mock(vrfCoordinator).fundSubscription(
                subId,
                FUND_AMOUNT
            );
            vm.stopBroadcast();
        } else {
            console.log(LinkToken(link).balanceOf(msg.sender));
            console.log(msg.sender);
            console.log(LinkToken(link).balanceOf(address(this)));
            console.log(address(this));
            vm.startBroadcast(deployerkey);
            //这里是Sepolia真是环境
            LinkToken(link).transferAndCall(
                vrfCoordinator,
                FUND_AMOUNT,
                abi.encode(subId)
            );
            vm.stopBroadcast();
        }
    }

    function run() external {
        fundSubscriptionUsingConfig();
    }
}

contract AddConsumer is Script {
    function addConsumer(
        address raffle,
        address vrfCoordinator,
        uint64 subId,
        uint256 deployerkey
    ) public {
        console.log("Adding consumer contract:", raffle);
        console.log("vrfCoordinator:", vrfCoordinator);
        console.log("On ChainId:", block.chainid);
        vm.startBroadcast(deployerkey);
        VRFCoordinatorV2Mock(vrfCoordinator).addConsumer(subId, raffle);
        vm.stopBroadcast();
    }

    function addConsumerConfig(address mostRecentlyDeployed) public {
        HelperConfig helperConfig = new HelperConfig();
        (
            ,
            ,
            address vrfCoordinator, //注意，activeNetworkConfig实际上是一个struct，不是函数
            ,
            uint64 subId,
            ,
            ,
            uint256 deployerkey
        ) = helperConfig.activeNetworkConfig();
        addConsumer(mostRecentlyDeployed, vrfCoordinator, subId, deployerkey);
    }

    function run() external {
        //https://github.com/Cyfrin/foundry-devops
        address mostRecentlyDeployed = DevOpsTools.get_most_recent_deployment(
            "Raffle",
            block.chainid
        );
        addConsumerConfig(mostRecentlyDeployed);
    }
}
