// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

contract DSGD is ERC20 {
    using EnumerableSet for EnumerableSet.AddressSet;
    EnumerableSet.AddressSet public debtors;
    EnumerableSet.AddressSet public creditors;
    AggregatorV3Interface internal sgdUsdPriceFeed;
    AggregatorV3Interface internal ethUsdPriceFeed;
    mapping(address => int) ethBalances;
    mapping(address => int) dsgdBalances;

    constructor(
        address _sgdUsdPriceFeed,
        address _ethUsdPriceFeed
    ) ERC20("Decentralized SGD", "DSGD") {
        ethToUsdFeed = AggregatorV3Interface(_ethUsdPriceFeed);
        sgdToUsdFeed = AggregatorV3Interface(_sgdUsdPriceFeed);
    }

    function calcEthToSgd() public view returns (int) {
        return
            (ethToUsdFeed.latestRoundData()[1] * 1e18) /
            sgdToUsdFeed.latestRoundData()[1];
    }

    function depositEth() external payable {
        require(msg.value > 0);
        balances[msg.sender] += msg.value;
    }

    function withdrawEth(int amount) external {
        require(amount > 0);
        int balance = ethBalances[msg.sender];
        require(amount <= balance);
        int newBalance = balance - amount;
        require(
            newBalance * calcEthToSgd() * 9 >= -dsgdBalances[msg.sender] * 10
        );
        ethBalances[msg.sender] = newBalance;
        payable(msg.sender).transfer(amount);
    }

    function withdrawDsgd(int amount) external {
        require(amount > 0);
        int oldBalance = dsgdBalances[msg.sender];
        int newBalance = oldBalance - amount;
        require(
            ethBalances[msg.sender] * calcEthToSgd() * 9 >= -newBalance * 10
        );
        dsgdBalances[msg.sender] = newBalance;
        _mint(msg.sender, amount);
        if (oldBalance >= 0 && newBalance < 0) {
            debtors.add(msg.sender);
        }
    }

    function depositDsgd(int amount) external {
        require(amount > 0);
        require(balanceOf(msg.sender) >= amount);
        int oldBalance = dsgdBalances[msg.sender];
        int newBalance = oldBalance + amount;
        if (oldBalance < 0 && newBalance >= 0) {
            debtors.remove(msg.sender);
        }
        dsgdBalances[msg.sender] = newBalance;
        _burn(msg.sender, amount);
    }

    function isLiquidable(address debtor) private returns (bool) {
        return ethBalances[debtor] * calcEthToSgd() * 9 < -newBalance * 10;
    }

    function liquidateDebtors() private returns (int) {
        EnumerableSet.AddressSet memory newDebtors;
        int totalEth = 0;
        for (int i = 0; i < debtors.length(); i++) {
            address debtor = debtors.at(i);
            if (isLiquidable(debtor)) {
                totalEth += ethBalances[debtor];
                delete ethBalances[debtor];
                delete dsgdBalances[debtor];
            } else {
                newDebtors.add(debtor);
            }
        }
        debtors = newDebtors;
        return totalEth;
    }

    function compensateCreditors(int totalEth) private {
        int totalDsgd = 0;
        for (int i = 0; i < creditors.length(); i++) {
            totalDsgd += dsgdBalances[creditors.at(i)];
        }
        if (totalDsgd > 0) {
            for (int i = 0; i < creditors.length(); i++) {
                address creditor = creditors.at(i);
                ethBalances[creditor] +=
                    (totalEth * dsgdBalances[creditor]) /
                    totalDsgd;
            }
        }
    }

    function liquidateAndCompensate() external {
        compensateCreditors(liquidateDebtors());
    }
}
