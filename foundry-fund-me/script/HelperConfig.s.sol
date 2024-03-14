//SPDX-License-Identifier:MIT
//1.Deploy mocks when  we are on a local anvil chain
//2.keep track of contract address across different chains(eg:ETH Arbitrum one)

pragma solidity ^0.8.18;

import {Script} from "forge-std/Script.sol";
import {MockV3Aggregator} from "../test/Mock/MockV3Aggregator.sol";

contract HelperConfig is Script {
    uint8 public constant DECIMALS = 8;
    int256 public constant INITIAL_PRICE = 2000e8;
    struct NetworkConfig {
        address PriceFeed;
    }
    //设置一个变量配合constructor()完成变量传递
    NetworkConfig public ActiveNetworkConfig;

    constructor() {
        if (block.chainid == 11155111) {
            ActiveNetworkConfig = getSepoliaEthConfig();
        } else if (block.chainid == 1) {
            ActiveNetworkConfig = getMainnetEthConfig();
        } else {
            ActiveNetworkConfig = getAnvilEthConfig();
        }
    }

    function getSepoliaEthConfig() public pure returns (NetworkConfig memory) {
        /*在 Solidity 中，数据位置（data location）是一个重要概念，它告诉编译器如何存储变量。
        对于复杂数据类型（如数组、结构体和映射），Solidity 要求你明确指定数据存储的位置。这里有三个选项：
        storage、memory 和 calldata，它们各自有不同的用途和特性：
        storage：表示变量永久存储在区块链上。storage 变量是状态变量，修改它们会永久改变合约的状态，因此消耗gas。
        memory：表示变量临时存储在内存中，只在外部函数调用期间存在。memory 数据在函数调用结束时被丢弃，适用于临时存储和处理数据，不会改变区块链状态，因此相对节省gas。
        calldata：是一种特殊的数据位置，仅适用于外部函数的输入参数。calldata 类似于 memory，但是它是只读的且生命周期更长，因为它存储的是函数调用的参数。 */
        NetworkConfig memory sepoliaconfig = NetworkConfig({
            PriceFeed: 0x694AA1769357215DE4FAC081bf1f309aDC325306
        });
        return sepoliaconfig;
    }

    //在本地的话，需要去将合约下载到本地指定文件夹
    function getAnvilEthConfig() public returns (NetworkConfig memory) {
        if (ActiveNetworkConfig.PriceFeed != address(0)) {
            return ActiveNetworkConfig;
        }
        vm.startBroadcast();
        //这一步其实就是把合约本地化。
        MockV3Aggregator mockPriceFeed = new MockV3Aggregator(
            DECIMALS,
            INITIAL_PRICE
        );
        vm.stopBroadcast();

        NetworkConfig memory anvilConfig = NetworkConfig({
            PriceFeed: address(mockPriceFeed)
        });
        return anvilConfig;
    }

    function getMainnetEthConfig() public pure returns (NetworkConfig memory) {
        NetworkConfig memory mainnetEthConfig = NetworkConfig({
            PriceFeed: 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419
        });
        return mainnetEthConfig;
    }
}
