// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Script, console} from "forge-std/Script.sol";
import {HelperConfig} from "./HelperConfig.s.sol";
import {VRFCoordinatorV2Mock} from "@chainLink/contracts/src/v0.8/mocks/VRFCoordinatorV2Mock.sol";
import {LinkToken} from "../test/mocks/LinkToken.sol";
import {DevOpsTools} from "lib/foundry-devops/src/DevOpsTools.sol";
import {Raffle} from "../src/Raffle.sol";

contract CreateSubscription is Script {
    function createSubscriptionUsingConfig() public returns (uint64) {
        HelperConfig helperConfig = new HelperConfig();
        (, , address vrfCoordinator, , , , ,) = helperConfig.activeNetworkConfig();
        return createSubscription(vrfCoordinator);
    }

    function createSubscription(
        address vrfCoordinator
    ) public returns (uint64) {
        console.log("Creating subscription on chainid: ", block.chainid);
        vm.startBroadcast();
        uint64 subId = VRFCoordinatorV2Mock(vrfCoordinator).createSubscription();
        vm.stopBroadcast();
        console.log("Subscription created with id: ", subId);
        return subId;
    }

    function run() external returns (uint64) {
        return createSubscriptionUsingConfig();
    }
}

contract FundSubscription is Script {
    uint96 public constant FUND_AMOUNT = 3 ether;

    function run() external {
        fundSubscriptionUsingConfig();
    }

    function fundSubscriptionUsingConfig() public returns (uint64) {
        HelperConfig helperConfig = new HelperConfig();
        (, , address vrfCoordinator, , uint64 subscriptionId, , address linkToken,) = helperConfig.activeNetworkConfig();
        return fundSubscription(vrfCoordinator, subscriptionId, linkToken);
    }

    function fundSubscription(
        address vrfCoordinator,
        uint64 subscriptionId,
        address link
    ) public returns (uint64) {
        console.log("Funding subscription: ", subscriptionId, " on chainid: ", block.chainid);
        console.log("Using VRF coordinator: ", vrfCoordinator, " and link token: ", link);

        if (block.chainid == 31337) { // if on local chain
        vm.startBroadcast();
        VRFCoordinatorV2Mock(vrfCoordinator).fundSubscription(subscriptionId,FUND_AMOUNT);
        vm.stopBroadcast();
        } else {
        vm.startBroadcast();
        LinkToken(link).transferAndCall(vrfCoordinator, FUND_AMOUNT, abi.encode(subscriptionId));
        vm.stopBroadcast();
        }

        console.log("Subscription funded with id: ", subscriptionId);
        return subscriptionId;
    }
}

contract AddConsumer is Script {
    function run() external {
            address contractAddress = DevOpsTools.get_most_recent_deployment("Raffle", block.chainid);
            addConsumerUsingConfig(contractAddress);
    }

    function addConsumerUsingConfig(address raffle) public {
        HelperConfig helperConfig = new HelperConfig();
        (, , address vrfCoordinator, , uint64 subscriptionId, , , uint256 deployerKey) = helperConfig.activeNetworkConfig();
        addConsumer(raffle, vrfCoordinator, subscriptionId, deployerKey);
    }

    function addConsumer(address raffle, address vrfCoordinator, uint64 subscriptionId, uint256 deployerKey) public {
        console.log("Adding consumer contract: ", raffle);
        console.log("Using VRF coordinator: ", vrfCoordinator, " and subscription id: ", subscriptionId);
        console.log("On chainid: ", block.chainid);
        vm.startBroadcast(deployerKey);
        VRFCoordinatorV2Mock(vrfCoordinator).addConsumer(subscriptionId, raffle);
        vm.stopBroadcast();
    }
}
