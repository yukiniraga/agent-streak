// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IAgentID} from "./IAgentID.sol";
import {Base64} from "./Base64.sol";

/// @title AgentStreak
/// @notice A daily check-in and streak protocol exclusively for Agent ID
///         holders, with soulbound milestone badges.
///
///         Agent ID is the identity layer for every state-changing action:
///         `checkIn` and `claimBadge` both require the caller to hold an
///         Agent ID, checked live against the Agent ID contract with the
///         official integration method — `balanceOf(address) > 0`.
///
///         The contract holds no user assets, charges no fees, has no
///         payable functions and no admin powers of any kind. Points and
///         badges are non-transferable reputation records only; they are
///         not financial instruments and carry no promised value.
contract AgentStreak {
    // ------------------------------------------------------------------
    // Errors
    // ------------------------------------------------------------------
    error NoAgentID(address user);
    error AlreadyCheckedInToday(address user, uint256 day);
    error InvalidTier(uint8 tier);
    error StreakTooShort(uint8 tier, uint256 bestStreak, uint256 required);
    error BadgeAlreadyClaimed(address user, uint8 tier);
    error BadgeDoesNotExist(uint256 tokenId);
    error Soulbound();
    error ZeroAddress();

    // ------------------------------------------------------------------
    // Events
    // ------------------------------------------------------------------
    event CheckIn(address indexed user, uint256 day, uint256 streak, uint256 pointsAwarded, uint256 totalPoints);
    event BadgeClaimed(address indexed user, uint8 indexed tier, uint256 tokenId);

    // ------------------------------------------------------------------
    // Constants and identity layer
    // ------------------------------------------------------------------
    uint256 public constant POINTS_BASE = 10;
    uint256 public constant STREAK_BONUS_CAP = 20;
    uint8 public constant TIER_COUNT = 4;

    /// @notice The Agent ID identity contract (BNB Chain mainnet deployment
    ///         is passed to the constructor; see README for the address).
    IAgentID public immutable agentID;

    // ------------------------------------------------------------------
    // Streak state
    // ------------------------------------------------------------------
    struct Stats {
        uint256 totalCheckIns;
        uint256 currentStreak;
        uint256 bestStreak;
        uint256 points;
        uint256 lastCheckInDay; // UTC day number: block.timestamp / 86400
        uint8 badgesClaimed; // bitmask over badge tiers
    }

    mapping(address => Stats) private _stats;
    address[] private _participants;
    mapping(address => bool) private _isParticipant;

    // ------------------------------------------------------------------
    // Badge state (minimal soulbound ERC-721, implemented in-contract so
    // the whole protocol stays in one auditable file set)
    // ------------------------------------------------------------------
    string public constant name = "Agent Streak Badge";
    string public constant symbol = "STREAK";

    uint256 private _nextBadgeId = 1;
    mapping(uint256 => address) private _badgeOwner;
    mapping(uint256 => uint8) private _badgeTier;
    mapping(address => uint256) private _badgeBalance;

    constructor(address agentID_) {
        if (agentID_ == address(0)) revert ZeroAddress();
        agentID = IAgentID(agentID_);
    }

    // ------------------------------------------------------------------
    // Identity
    // ------------------------------------------------------------------
    /// @notice True if `user` currently holds an Agent ID.
    function hasAgentID(address user) public view returns (bool) {
        return agentID.balanceOf(user) > 0;
    }

    function _requireAgentID(address user) internal view {
        if (!hasAgentID(user)) revert NoAgentID(user);
    }

    // ------------------------------------------------------------------
    // Check-in and streaks
    // ------------------------------------------------------------------
    /// @notice Check in for today (UTC). One check-in per account per day.
    ///         Consecutive days build the streak; a missed day restarts it
    ///         at 1. Awards 10 + min(streak, 20) points.
    function checkIn() external {
        _requireAgentID(msg.sender);
        uint256 today = block.timestamp / 1 days;
        Stats storage s = _stats[msg.sender];
        if (s.lastCheckInDay == today && s.totalCheckIns != 0) {
            revert AlreadyCheckedInToday(msg.sender, today);
        }

        if (s.totalCheckIns == 0) {
            _participants.push(msg.sender);
            _isParticipant[msg.sender] = true;
            s.currentStreak = 1;
        } else if (s.lastCheckInDay + 1 == today) {
            s.currentStreak += 1;
        } else {
            // At least one full day was missed: the streak restarts.
            s.currentStreak = 1;
        }

        if (s.currentStreak > s.bestStreak) s.bestStreak = s.currentStreak;
        s.lastCheckInDay = today;
        s.totalCheckIns += 1;

        uint256 bonus = s.currentStreak < STREAK_BONUS_CAP ? s.currentStreak : STREAK_BONUS_CAP;
        uint256 awarded = POINTS_BASE + bonus;
        s.points += awarded;

        emit CheckIn(msg.sender, today, s.currentStreak, awarded, s.points);
    }

    // ------------------------------------------------------------------
    // Badges
    // ------------------------------------------------------------------
    /// @notice Best streak required for a badge tier (0..3).
    function badgeThreshold(uint8 tier) public pure returns (uint256) {
        if (tier == 0) return 3;
        if (tier == 1) return 7;
        if (tier == 2) return 14;
        if (tier == 3) return 30;
        revert InvalidTier(tier);
    }

    /// @notice Display name of a badge tier (0..3).
    function badgeName(uint8 tier) public pure returns (string memory) {
        if (tier == 0) return "Spark";
        if (tier == 1) return "Flame";
        if (tier == 2) return "Blaze";
        if (tier == 3) return "Eternal Flame";
        revert InvalidTier(tier);
    }

    /// @notice Claim the soulbound badge for `tier`. Requires an Agent ID,
    ///         a best streak at or above the tier threshold, and that the
    ///         tier has not been claimed before by this account.
    function claimBadge(uint8 tier) external returns (uint256 tokenId) {
        _requireAgentID(msg.sender);
        if (tier >= TIER_COUNT) revert InvalidTier(tier);
        Stats storage s = _stats[msg.sender];
        uint256 required = badgeThreshold(tier);
        if (s.bestStreak < required) revert StreakTooShort(tier, s.bestStreak, required);
        uint8 bit = uint8(1) << tier;
        if (s.badgesClaimed & bit != 0) revert BadgeAlreadyClaimed(msg.sender, tier);

        s.badgesClaimed |= bit;
        tokenId = _nextBadgeId++;
        _badgeOwner[tokenId] = msg.sender;
        _badgeTier[tokenId] = tier;
        _badgeBalance[msg.sender] += 1;

        emit BadgeClaimed(msg.sender, tier, tokenId);
    }

    // ------------------------------------------------------------------
    // Views for the leaderboard and profile pages
    // ------------------------------------------------------------------
    /// @notice Full stats for one account. `badgesClaimed` is a bitmask:
    ///         bit i set means tier i has been claimed.
    function getStats(address user)
        external
        view
        returns (
            uint256 totalCheckIns,
            uint256 currentStreak,
            uint256 bestStreak,
            uint256 points,
            uint256 lastCheckInDay,
            uint256 badgesClaimed
        )
    {
        Stats storage s = _stats[user];
        return (s.totalCheckIns, s.currentStreak, s.bestStreak, s.points, s.lastCheckInDay, s.badgesClaimed);
    }

    /// @notice Number of accounts that have ever checked in.
    function participantCount() external view returns (uint256) {
        return _participants.length;
    }

    /// @notice Participant address at leaderboard index `i`.
    function participantAt(uint256 i) external view returns (address) {
        return _participants[i];
    }

    /// @notice True if `user` has checked in at least once.
    function isParticipant(address user) external view returns (bool) {
        return _isParticipant[user];
    }

    // ------------------------------------------------------------------
    // Soulbound ERC-721 surface
    // ------------------------------------------------------------------
    function balanceOf(address owner) external view returns (uint256) {
        if (owner == address(0)) revert ZeroAddress();
        return _badgeBalance[owner];
    }

    function ownerOf(uint256 tokenId) public view returns (address) {
        address owner = _badgeOwner[tokenId];
        if (owner == address(0)) revert BadgeDoesNotExist(tokenId);
        return owner;
    }

    /// @notice Tier of a minted badge token.
    function badgeTierOf(uint256 tokenId) external view returns (uint8) {
        if (_badgeOwner[tokenId] == address(0)) revert BadgeDoesNotExist(tokenId);
        return _badgeTier[tokenId];
    }

    /// @notice Badges are soulbound: every transfer path reverts.
    function transferFrom(address, address, uint256) external pure {
        revert Soulbound();
    }

    /// @notice Badges are soulbound: every transfer path reverts.
    function safeTransferFrom(address, address, uint256) external pure {
        revert Soulbound();
    }

    /// @notice Badges are soulbound: every transfer path reverts.
    function safeTransferFrom(address, address, uint256, bytes calldata) external pure {
        revert Soulbound();
    }

    /// @notice Badges are soulbound: approvals are disabled.
    function approve(address, uint256) external pure {
        revert Soulbound();
    }

    /// @notice Badges are soulbound: approvals are disabled.
    function setApprovalForAll(address, bool) external pure {
        revert Soulbound();
    }

    function getApproved(uint256 tokenId) external view returns (address) {
        if (_badgeOwner[tokenId] == address(0)) revert BadgeDoesNotExist(tokenId);
        return address(0);
    }

    function isApprovedForAll(address, address) external pure returns (bool) {
        return false;
    }

    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        return interfaceId == 0x80ac58cd // ERC-721
            || interfaceId == 0x5b5e139f // ERC-721 metadata
            || interfaceId == 0x01ffc9a7; // ERC-165
    }

    // ------------------------------------------------------------------
    // On-chain badge metadata: JSON + inline SVG, generated per tier
    // ------------------------------------------------------------------
    function tokenURI(uint256 tokenId) external view returns (string memory) {
        if (_badgeOwner[tokenId] == address(0)) revert BadgeDoesNotExist(tokenId);
        uint8 tier = _badgeTier[tokenId];
        string memory tierName = badgeName(tier);
        string memory threshold = _toString(badgeThreshold(tier));
        string memory svg = _badgeSVG(tier, tierName, threshold);
        string memory json = string(
            abi.encodePacked(
                '{"name":"Agent Streak Badge - ',
                tierName,
                '","description":"Soulbound milestone badge from Agent Streak, the daily check-in protocol for Agent ID holders. Awarded for a best streak of ',
                threshold,
                ' days. Non-transferable.","image":"data:image/svg+xml;base64,',
                Base64.encode(bytes(svg)),
                '","attributes":[{"trait_type":"Tier","value":"',
                tierName,
                '"},{"trait_type":"Best streak (days)","value":',
                threshold,
                "}]}"
            )
        );
        return string(abi.encodePacked("data:application/json;base64,", Base64.encode(bytes(json))));
    }

    /// @dev Original geometric badge art: concentric rings around a simple
    ///      teardrop flame, coloured per tier, with the tier name and the
    ///      streak requirement as text.
    function _badgeSVG(uint8 tier, string memory tierName, string memory threshold)
        internal
        pure
        returns (string memory)
    {
        string memory main;
        string memory inner;
        string memory bg;
        if (tier == 0) {
            bg = "#201404";
            main = "#f5b942";
            inner = "#ffe1a8";
        } else if (tier == 1) {
            bg = "#221003";
            main = "#f97b1e";
            inner = "#ffc46b";
        } else if (tier == 2) {
            bg = "#230606";
            main = "#ef4444";
            inner = "#fb923c";
        } else {
            bg = "#160a2e";
            main = "#a78bfa";
            inner = "#f5b942";
        }
        return string(
            abi.encodePacked(
                '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 240 240">',
                '<rect width="240" height="240" rx="28" fill="',
                bg,
                '"/>',
                '<circle cx="120" cy="104" r="74" fill="none" stroke="',
                main,
                '" stroke-width="3" opacity="0.45"/>',
                '<circle cx="120" cy="104" r="58" fill="none" stroke="',
                main,
                '" stroke-width="2" opacity="0.7"/>',
                '<path d="M120 158 C 96 134 90 110 100 88 C 106 74 114 64 120 40 C 126 64 134 74 140 88 C 150 110 144 134 120 158 Z" fill="',
                main,
                '"/>',
                '<path d="M120 146 C 106 130 104 114 112 100 C 116 92 119 86 120 74 C 121 86 124 92 128 100 C 136 114 134 130 120 146 Z" fill="',
                inner,
                '"/>',
                '<text x="120" y="196" text-anchor="middle" font-family="sans-serif" font-size="19" font-weight="bold" fill="',
                main,
                '">',
                tierName,
                "</text>",
                '<text x="120" y="218" text-anchor="middle" font-family="sans-serif" font-size="12" fill="#e8e3d8">',
                threshold,
                " DAY STREAK</text></svg>"
            )
        );
    }

    function _toString(uint256 value) internal pure returns (string memory) {
        if (value == 0) return "0";
        uint256 temp = value;
        uint256 digits;
        while (temp != 0) {
            digits++;
            temp /= 10;
        }
        bytes memory buffer = new bytes(digits);
        while (value != 0) {
            digits -= 1;
            buffer[digits] = bytes1(uint8(48 + uint256(value % 10)));
            value /= 10;
        }
        return string(buffer);
    }
}
