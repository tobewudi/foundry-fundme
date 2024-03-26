// SPDX-License-Identifier:MIT
pragma solidity ^0.8.18;
import {Script} from "forge-std/Script.sol";
import {Raffle} from "../src/Raffle.sol";
import {HelperConfig} from "./HelperConfig.s.sol";
import {CreateSubscription, AddConsumer, FundSubscription} from "./Interactions.s.sol";

contract DeployRaffle is Script {
    function run() external returns (Raffle, HelperConfig) {
        //从HelperConfig调入相关网络设置
        HelperConfig helperConfig = new HelperConfig();
        AddConsumer addConsumer = new AddConsumer();
        (
            uint256 entranceFee,
            uint256 interval,
            address vrfCoordinator,
            bytes32 gasLane,
            uint64 subscriptionId,
            uint32 callbackGasLimit,
            address link, //注意，activeNetworkConfig实际上是一个struct，不是函数
            uint256 deployerkey
        ) = helperConfig.activeNetworkConfig();
        //如果不是本地环境那么就不需要以下设定。
        if (subscriptionId == 0) {
            //we are going to need to create a subscription!
            CreateSubscription creatSubscription = new CreateSubscription();
            (subscriptionId, vrfCoordinator) = creatSubscription
                .createSubscription(vrfCoordinator, deployerkey);
            //Fund it!这里是模拟给订阅号冲币
            FundSubscription fundSubscription = new FundSubscription();
            fundSubscription.fundSubscription(
                vrfCoordinator,
                subscriptionId,
                link,
                deployerkey
            );
        }

        vm.startBroadcast(deployerkey);
        Raffle raffle = new Raffle(
            entranceFee,
            interval,
            vrfCoordinator,
            gasLane,
            subscriptionId,
            callbackGasLimit
        );
        vm.stopBroadcast();
        addConsumer.addConsumer(
            address(raffle),
            vrfCoordinator,
            subscriptionId,
            deployerkey
        );

        return (raffle, helperConfig);
    }
}
