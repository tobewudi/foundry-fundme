// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;
//导入forge基本库
//console类似打开日志功能。
import {Test, console} from "forge-std/Test.sol";
//导入测试合约
import {FundMe} from "../../src/FundMe.sol";
//将部署功能内置
import {DeployFundMe} from "../../script/DeployFundMe.s.sol";

//继承
contract FundMeTest is Test {
    FundMe fundMe;
    //用chetcodes模拟一个地给合约发送资金
    address USER = makeAddr("user");
    uint256 constant SEND_VALUE = 0.1 ether;
    uint256 constant STARTING_BALANCE = 10 ether;
    modifier funded() {
        vm.prank(USER); //告诉合约，下一笔交易将由USER发出。
        fundMe.fund{value: SEND_VALUE}();
        _;
    }

    //setUP其实就是初始化参数、合约等的特殊函数。setUp() 函数是一种特殊的函数，
    //用于在每个测试之前设置测试环境。当你在编写合约测试时，
    //setUp() 函数允许你定义一组在执行每个测试函数之前都会运行的预备步骤。这可以包括部署合约、
    //初始化变量、设置合约状态等，确保每个测试都是在预期的环境下执行。
    function setUp() external {
        // fundMe = new FundMe(0x694AA1769357215DE4FAC081bf1f309aDC325306);
        DeployFundMe deployFundME = new DeployFundMe();
        fundMe = deployFundME.run();
        // checode，给虚拟账户余额
        vm.deal(USER, STARTING_BALANCE);
    }

    function testMinimumDollarIsFive() public {
        assertEq(fundMe.MINIMUM_USD(), 5e18);
    }

    function testOwnerIsMsgSender() public {
        //console.log 需要加上-vv（几个参数几个V）来返回结果。
        console.log(msg.sender);
        console.log(fundMe.getOwner());
        assertEq(fundMe.getOwner(), msg.sender);
    }

    function testPriceFeedVersionISAccurate() public {
        uint256 version = fundMe.getVersion();
        assertEq(version, 4);
    }

    function testFundFailsWithoutEnoughETH() public {
        //这里要注意，如果不够，则回滚
        vm.expectRevert();
        fundMe.fund();
    }

    /*合约调用与发送 ETH: 当你调用一个合约函数并希望同时发送以太币，
    Solidity 允许你在函数调用时使用 {value: amount} 语法指定发送的金额。
    这里的 amount 是要发送的以太币数量，以 wei 为单位。在你的例子中，
    10e18 表示发送 10 ETH
    testFundUpdatesFundedDateStructure 中使用 address(this) 作为参数来调用 getAddressToAmountFunded 是有道理的。
    这是因为在测试环境中，this 指的是当前测试合约的实例（即 FundMeTest），而当你在测试中调用 fundMe.fund{value: 10e18}();
     时，资金是从测试合约（FundMeTest）发送到 FundMe 合约的。*/
    function testFundUpdatesFundedDateStructure() public funded {
        uint256 amountFunded = fundMe.getAddressToAmountFunded(USER);
        assertEq(amountFunded, SEND_VALUE);
    }

    function testAddsFunderToArrayOfFunders() public funded {
        address funder = fundMe.getFunder(0);
        assertEq(funder, USER);
    }

    function testOnlyOwnerCanWithdraw() public {
        vm.expectRevert();
        vm.prank(USER);
        fundMe.withdraw();
    }

    function testWithDrawWithASingleFunder() public funded {
        //Arrange
        uint256 staringOwnerBalance = fundMe.getOwner().balance;
        uint256 staringFundMeBalance = address(fundMe).balance;
        //Act
        //只有owner才可以withdraw
        vm.prank(fundMe.getOwner());
        fundMe.withdraw();
        //Assert
        //这里要注意提取操作后将会小号GAS，导致合约所有者增加的ETH不等于原合约余额。
        //而这里如果申明两个ending变量后可以解决这个问题。
        // assertEq(address(fundMe).balance, 0);
        // assertEq(fundMe.getOwner().balance, staringFundMeBalance);
        uint256 endingOwnerBalance = fundMe.getOwner().balance;
        uint256 endingFundMeBalance = address(fundMe).balance;
        assertEq(endingFundMeBalance, 0);
        assertEq(
            staringFundMeBalance + staringOwnerBalance,
            endingOwnerBalance
        );
    }

    function testWithdrawFromMultipleFunders() public funded {
        //if you want to use address(n) to generate random address. you should convert uint256 to uint160.
        uint160 numberOfFunders = 10;
        //we set startingFundersIndex=1 can reduce some revert error
        uint160 startingFundersIndex = 1;
        //arrange
        for (uint160 i = startingFundersIndex; i < numberOfFunders; i++) {
            //we need some address and some balance
            //vm.prank new address
            //vm.deal new address
            //hoax(<some address>,value)  hoax can integrate the above function
            hoax(address(i), SEND_VALUE);
            //then we send some ether to fundMe contract
            fundMe.fund{value: SEND_VALUE}();
        }
        //Act
        uint256 startingOwnerBalance = fundMe.getOwner().balance;
        uint256 startingFundMeBalance = address(fundMe).balance;
        //Between vm.startprank and vm.stopprank, all code will run as USER
        vm.startPrank(fundMe.getOwner());
        fundMe.withdraw();
        vm.stopPrank();
        uint256 endingFundMeBalance = address(fundMe).balance;
        uint256 endingOwnerBalance = fundMe.getOwner().balance;
        //Assert
        assertEq(endingFundMeBalance, 0);
        assertEq(
            startingFundMeBalance + startingOwnerBalance,
            endingOwnerBalance

            //如果将FunMe部署到真实链上，那么在调用widraw()时会消耗一定的GAS，我们上面的测试将不会通过。提供一个计算GAS消耗的写法。
            //Act
            //First:obtain the initial gas through gasleft()
            //uint256 gasStart = gasleft();
            //调用内置函数vm.txGasPrice(GAS_PRICE);
            //vm.txGasPrice(GAS_PRICE)；
            //vm.prank(fundMe.getOwner());
            //fundMe.withdraw();
            //uint256 gasEnd=gasleft();
            //unit256 gasUsed = (gasStart - gasEnd) * tx.gasprice;
            //console.log(gasUsed);
        );
    }
}
