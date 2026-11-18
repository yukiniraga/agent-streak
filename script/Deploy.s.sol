// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AgentStreak} from "../src/AgentStreak.sol";

/// @notice Minimal broadcast cheatcodes, declared locally (no forge-std).
interface VmBroadcast {
    function startBroadcast() external;
    function stopBroadcast() external;
}

/// @title Deploy
/// @notice Deploys AgentStreak wired to the Agent ID contract on BNB Chain
///         mainnet. Run with:
///         forge script script/Deploy.s.sol:Deploy --rpc-url $BSC_RPC_URL \
///             --broadcast --private-key $DEPLOYER_PRIVATE_KEY
///         The deployer key must be supplied through the environment at
///         deploy time; it is never stored in this repository.
contract Deploy {
    VmBroadcast internal constant VM = VmBroadcast(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);

    /// @dev Agent ID identity contract on BNB Chain mainnet
    ///      (SPACE ID Agent ID, ERC-721).
    address internal constant AGENT_ID_BNB_MAINNET = 0x60B9262456dE011F7d15a54CdD8c48bAaa8B022F;

    function run() external returns (AgentStreak deployed) {
        VM.startBroadcast();
        deployed = new AgentStreak(AGENT_ID_BNB_MAINNET);
        VM.stopBroadcast();
    }
}
