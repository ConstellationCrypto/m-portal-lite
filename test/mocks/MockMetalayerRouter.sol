// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { ReadOperation } from "../../src/bridges/metalayer/interfaces/IMetalayerRecipient.sol";
import { FinalityState } from "../../src/bridges/metalayer/interfaces/IMetalayerRouter.sol";

contract MockMetalayerRouter {
    uint256 public refundAmount;
    uint32 public nonce;

    function quoteDispatch(
        uint32,
        bytes32,
        ReadOperation[] calldata,
        bytes calldata,
        FinalityState,
        uint256
    ) external pure returns (uint256) {
        return 0;
    }

    function dispatch(
        uint32,
        bytes32,
        ReadOperation[] calldata,
        bytes calldata,
        FinalityState,
        uint256
    ) external payable {
        nonce++;  // Increment nonce on each dispatch

        // Mock dispatch function - simulates refund if refundAmount is set
        if (refundAmount > 0) {
            payable(msg.sender).call{ value: refundAmount }("");
        }
    }

    function setRefundAmount(uint256 amount_) external {
        refundAmount = amount_;
    }
} 