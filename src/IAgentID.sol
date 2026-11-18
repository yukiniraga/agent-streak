// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title IAgentID
/// @notice Minimal read interface for the Agent ID identity contract on
///         BNB Chain (SPACE ID Agent ID, ERC-721, non-transferable).
/// @dev The official integration method is a single balance check:
///      an address "holds an Agent ID" if and only if
///      `balanceOf(address) > 0`. Agent ID exposes no enumerable or
///      name-resolution getters, so `balanceOf` is the only call this
///      project relies on.
interface IAgentID {
    /// @notice Number of Agent ID tokens held by `owner` (0 or 1 in practice,
    ///         since each user can claim only one Agent ID).
    function balanceOf(address owner) external view returns (uint256);
}
