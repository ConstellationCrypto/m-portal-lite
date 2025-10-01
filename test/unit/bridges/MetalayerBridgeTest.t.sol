// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { Test } from "../../../lib/forge-std/src/Test.sol";
import { Ownable } from "../../../lib/openzeppelin/contracts/access/Ownable.sol";

import { MetalayerBridge } from "../../../src/bridges/metalayer/MetalayerBridge.sol";
import { IMetalayerBridge } from "../../../src/bridges/metalayer/interfaces/IMetalayerBridge.sol";
import { IMetalayerRouter } from "../../../src/bridges/metalayer/interfaces/IMetalayerRouter.sol";
import { ReadOperation } from "../../../src/bridges/metalayer/interfaces/IMetalayerRecipient.sol";
import { FinalityState } from "../../../src/bridges/metalayer/interfaces/IMetalayerRouter.sol";
import { IPortal } from "../../../src/interfaces/IPortal.sol";
import { IBridge } from "../../../src/interfaces/IBridge.sol";
import { TypeConverter } from "../../../src/libs/TypeConverter.sol";

import { MockMetalayerRouter } from "../../mocks/MockMetalayerRouter.sol";
import { MockPortal } from "../../mocks/MockPortal.sol";

contract MetalayerBridgeTest is Test {
    using TypeConverter for *;

    uint256 public constant REMOTE_CHAIN_ID = 111;

    address public owner = makeAddr("owner");
    address public user = makeAddr("user");

    MetalayerBridge public bridge;
    address public router;
    address public portal;
    bytes32 public remotePeer;

    function setUp() external {
        router = address(new MockMetalayerRouter());
        portal = address(new MockPortal());
        bridge = new MetalayerBridge(router, portal, owner);
        remotePeer = makeAddr("remotePeer").toBytes32();

        vm.prank(owner);
        bridge.setPeer(REMOTE_CHAIN_ID, remotePeer);
    }

    function test_constructor_zeroAddress() external {
        vm.expectRevert(IMetalayerBridge.ZeroRouter.selector);
        new MetalayerBridge(address(0), portal, owner);

        vm.expectRevert(IBridge.ZeroPortal.selector);
        new MetalayerBridge(router, address(0), owner);
    }

    function test_setPeer() external {
        uint256 newChainId = 10;
        bytes32 newPeer = makeAddr("newPeer").toBytes32();

        vm.prank(owner);
        vm.expectEmit(address(bridge));
        emit IMetalayerBridge.PeerSet(newChainId, newPeer);

        bridge.setPeer(newChainId, newPeer);

        assertEq(bridge.peer(newChainId), newPeer);
    }

    function test_setPeer_nonOwner() external {
        vm.prank(address(0xBAD));
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(0xBAD)));
        bridge.setPeer(REMOTE_CHAIN_ID, remotePeer);
    }

    function test_setPeer_zeroInputs() external {
        vm.prank(owner);
        vm.expectRevert(IMetalayerBridge.ZeroDestinationChain.selector);
        bridge.setPeer(0, remotePeer);

        vm.prank(owner);
        vm.expectRevert(IMetalayerBridge.ZeroPeer.selector);
        bridge.setPeer(REMOTE_CHAIN_ID, bytes32(0));
    }

    function test_setDomainOverride() external {
        uint256 chainId = 123;
        uint32 customDomain = 456;

        vm.prank(owner);
        vm.expectEmit(address(bridge));
        emit IMetalayerBridge.DomainOverrideSet(chainId, customDomain);

        bridge.setDomainOverride(chainId, customDomain);

        assertEq(bridge.domainOverride(chainId), customDomain);
    }

    function test_setDomainOverride_nonOwner() external {
        vm.prank(address(0xBAD));
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(0xBAD)));
        bridge.setDomainOverride(123, 456);
    }

    function test_setDomainOverride_zeroInputs() external {
        vm.prank(owner);
        vm.expectRevert(IMetalayerBridge.ZeroDestinationChain.selector);
        bridge.setDomainOverride(0, 456);

        vm.prank(owner);
        vm.expectRevert(IMetalayerBridge.ZeroDomain.selector);
        bridge.setDomainOverride(123, 0);
    }

    function testFuzz_quote(uint256 gasLimit_, bytes memory payload_, uint256 routerFee_) external {
        ReadOperation[] memory emptyReads = new ReadOperation[](0);

        // Manual selector for: quoteDispatch(uint32,bytes32,ReadOperation[],bytes,FinalityState,uint256)
        bytes4 quoteSelector = bytes4(keccak256("quoteDispatch(uint32,bytes32,(uint32,address,bytes)[],bytes,uint8,uint256)"));
        
        vm.mockCall(
            router,
            abi.encodeWithSelector(
                quoteSelector,
                uint32(REMOTE_CHAIN_ID),
                remotePeer,
                emptyReads,
                payload_,
                FinalityState.INSTANT,
                gasLimit_
            ),
            abi.encode(routerFee_)
        );

        vm.prank(user);
        uint256 bridgeFee_ = bridge.quote(REMOTE_CHAIN_ID, gasLimit_, payload_);

        assertEq(bridgeFee_, routerFee_);
    }

    function test_quote_unsupportedChain() external {
        uint256 unsupportedChainId_ = 222;
        uint256 gasLimit_ = 200_000;
        bytes memory payload_ = bytes("payload");

        vm.expectRevert(abi.encodeWithSelector(IMetalayerBridge.UnsupportedDestinationChain.selector, unsupportedChainId_));
        bridge.quote(unsupportedChainId_, gasLimit_, payload_);
    }

    function test_quote_withDomainOverride() external {
        uint256 chainId = 111;
        uint32 customDomain = 999;
        uint256 gasLimit_ = 200_000;
        bytes memory payload_ = bytes("payload");
        ReadOperation[] memory emptyReads = new ReadOperation[](0);

        // Set domain override
        vm.prank(owner);
        bridge.setDomainOverride(chainId, customDomain);

        // Manual selector for: quoteDispatch(uint32,bytes32,ReadOperation[],bytes,FinalityState,uint256)
        bytes4 quoteSelector = bytes4(keccak256("quoteDispatch(uint32,bytes32,(uint32,address,bytes)[],bytes,uint8,uint256)"));

        vm.mockCall(
            router,
            abi.encodeWithSelector(
                quoteSelector,
                customDomain,
                remotePeer,
                emptyReads,
                payload_,
                FinalityState.INSTANT,
                gasLimit_
            ),
            abi.encode(1000)
        );

        uint256 fee_ = bridge.quote(chainId, gasLimit_, payload_);
        assertEq(fee_, 1000);
    }

    function test_sendMessage() external {
        uint256 gasLimit_ = 100_000;
        bytes memory payload_ = bytes("payload");
        uint256 value_ = 0.001 ether;
        ReadOperation[] memory emptyReads = new ReadOperation[](0);

        // Manual selector for: dispatch(uint32,bytes32,ReadOperation[],bytes,FinalityState,uint256)
        bytes4 dispatchSelector = bytes4(keccak256("dispatch(uint32,bytes32,(uint32,address,bytes)[],bytes,uint8,uint256)"));

        vm.expectCall(
            router,
            abi.encodeWithSelector(
                dispatchSelector,
                uint32(REMOTE_CHAIN_ID),
                remotePeer,
                emptyReads,
                payload_,
                FinalityState.INSTANT,
                gasLimit_
            )
        );

        vm.deal(portal, value_);
        vm.prank(portal);

        bytes32 messageId = bridge.sendMessage{ value: value_ }(REMOTE_CHAIN_ID, gasLimit_, user, payload_);
        
        // Verify that a messageId was generated
        assertTrue(messageId != bytes32(0));
    }

    function test_sendMessage_notPortal() external {
        uint256 value_ = 0.001 ether;

        vm.expectRevert(IBridge.NotPortal.selector);

        vm.deal(user, value_);
        vm.prank(user);

        bridge.sendMessage{ value: value_ }(REMOTE_CHAIN_ID, 100_000, user, bytes("payload"));
    }

    function test_sendMessage_withDomainOverride() external {
        uint256 gasLimit_ = 100_000;
        bytes memory payload_ = bytes("payload");
        uint256 value_ = 0.001 ether;
        uint32 customDomain = 999;
        ReadOperation[] memory emptyReads = new ReadOperation[](0);

        // Set domain override
        vm.prank(owner);
        bridge.setDomainOverride(REMOTE_CHAIN_ID, customDomain);

        // Manual selector for: dispatch(uint32,bytes32,ReadOperation[],bytes,FinalityState,uint256)
        bytes4 dispatchSelector = bytes4(keccak256("dispatch(uint32,bytes32,(uint32,address,bytes)[],bytes,uint8,uint256)"));

        vm.expectCall(
            router,
            abi.encodeWithSelector(
                dispatchSelector,
                customDomain,
                remotePeer,
                emptyReads,
                payload_,
                FinalityState.INSTANT,
                gasLimit_
            )
        );

        vm.deal(portal, value_);
        vm.prank(portal);

        bridge.sendMessage{ value: value_ }(REMOTE_CHAIN_ID, gasLimit_, user, payload_);
    }

    function test_handle() external {
        bytes memory payload_ = bytes("payload");
        ReadOperation[] memory reads = new ReadOperation[](0);
        bytes[] memory readResults = new bytes[](0);

        vm.expectCall(portal, abi.encodeCall(IPortal.receiveMessage, (REMOTE_CHAIN_ID, payload_)));

        vm.prank(router);
        bridge.handle(uint32(REMOTE_CHAIN_ID), remotePeer, payload_, reads, readResults);
    }

    function test_handle_notRouter() external {
        ReadOperation[] memory reads = new ReadOperation[](0);
        bytes[] memory readResults = new bytes[](0);

        vm.expectRevert(IMetalayerBridge.NotRouter.selector);

        vm.prank(user);
        bridge.handle(uint32(REMOTE_CHAIN_ID), remotePeer, bytes("payload"), reads, readResults);
    }

    function test_handle_unsupportedSender() external {
        bytes32 sender_ = bytes32("sender");
        ReadOperation[] memory reads = new ReadOperation[](0);
        bytes[] memory readResults = new bytes[](0);

        vm.expectRevert(abi.encodeWithSelector(IMetalayerBridge.UnsupportedSender.selector, sender_));

        vm.prank(router);
        bridge.handle(uint32(REMOTE_CHAIN_ID), sender_, bytes("payload"), reads, readResults);
    }

    function test_domainOverride_defaultBehavior() external {
        // Without override, should return 0
        assertEq(bridge.domainOverride(REMOTE_CHAIN_ID), 0);
    }

    function test_sendMessage_uniqueMessageIds() external {
        // This test verifies that the nonce ensures unique messageIds
        // even when sending identical messages in the same block
        uint256 gasLimit_ = 100_000;
        bytes memory payload_ = bytes("identical payload");
        uint256 value_ = 0.001 ether;
        address refundAddress_ = makeAddr("refund");

        vm.deal(portal, value_ * 2);

        // Send first message
        vm.prank(portal);
        bytes32 messageId1_ = bridge.sendMessage{ value: value_ }(
            REMOTE_CHAIN_ID,
            gasLimit_,
            refundAddress_,
            payload_
        );

        // Send second identical message in the same block
        vm.prank(portal);
        bytes32 messageId2_ = bridge.sendMessage{ value: value_ }(
            REMOTE_CHAIN_ID,
            gasLimit_,
            refundAddress_,
            payload_
        );

        assertTrue(messageId1_ != messageId2_, "MessageIds should be unique");
        assertEq(MockMetalayerRouter(router).nonce(), 2, "Nonce should have incremented twice");
    }

    function test_receive_notRouter() external {
        ETHSender sender = new ETHSender();
        vm.deal(address(sender), 1 ether);

        vm.expectRevert(IMetalayerBridge.NotRouter.selector);
        sender.sendETH(payable(address(bridge)), 0.1 ether);
    }

    function test_sendMessage_withRefund() external {
        uint256 gasLimit_ = 100_000;
        bytes memory payload_ = bytes("payload");
        uint256 value_ = 1 ether;
        uint256 refundAmount_ = 0.5 ether;
        address refundAddress_ = makeAddr("refundAddress");

        // Set the mock router to refund 0.5 ether
        MockMetalayerRouter(router).setRefundAmount(refundAmount_);

        uint256 refundAddressBalanceBefore = refundAddress_.balance;

        vm.deal(portal, value_);
        vm.prank(portal);

        bridge.sendMessage{ value: value_ }(REMOTE_CHAIN_ID, gasLimit_, refundAddress_, payload_);

        // Verify that the refund address received the refund
        assertEq(refundAddress_.balance, refundAddressBalanceBefore + refundAmount_);
    }

    function test_receive_withoutActiveRefund() external {
        // This test simulates a scenario where router tries to send ETH to bridge
        // when there's no active sendMessage call (currentRefundAddress is 0)

        // Deploy ETHSender at the router address using vm.etch
        ETHSender sender = new ETHSender();
        bytes memory senderCode = address(sender).code;
        vm.etch(router, senderCode);

        vm.deal(router, 1 ether);

        vm.expectRevert(IMetalayerBridge.RefundFailed.selector);
        ETHSender(router).sendETH(payable(address(bridge)), 0.1 ether);
    }
}

// Helper contract that rejects ETH transfers
contract RejectingReceiver {
    receive() external payable {
        revert("Rejecting ETH");
    }
}

// Helper contract that sends ETH to an address
contract ETHSender {
    function sendETH(address payable recipient, uint256 amount) external {
        recipient.transfer(amount);
    }
} 