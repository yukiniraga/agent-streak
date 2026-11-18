// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IAgentID} from "./IAgentID.sol";

/// @title MockAgentID
/// @notice Test double for the Agent ID contract. Mirrors the one behaviour
///         the protocol depends on — `balanceOf(address) > 0` means the
///         address holds an Agent ID — and lets tests grant or revoke that
///         status. Never deployed to a live network.
contract MockAgentID is IAgentID {
    mapping(address => uint256) private _balances;

    /// @notice Grant Agent ID status to `user` (test helper).
    function grant(address user) external {
        _balances[user] = 1;
    }

    /// @notice Revoke Agent ID status from `user` (test helper).
    function revoke(address user) external {
        _balances[user] = 0;
    }

    function balanceOf(address owner) external view override returns (uint256) {
        return _balances[owner];
    }
}
