// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.26;

import { TimelockedConfigureBatch } from "./TimelockedConfigureBatch.sol";

contract ProposeTimelockedConfigure is TimelockedConfigureBatch {
    function run(uint256[] memory peerChainIds_) external {
        address sender_ = vm.rememberKey(vm.envUint("PRIVATE_KEY"));
        bytes32 salt_ = _buildConfigureBatch(peerChainIds_);
        _proposeTimelockBatch(sender_, salt_);
    }
}
