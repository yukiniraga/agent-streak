// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {AgentStreak} from "../src/AgentStreak.sol";
import {MockAgentID} from "../src/MockAgentID.sol";

/// @notice Minimal cheatcode interface (the subset of forge's Vm this suite
///         uses), declared locally so the project needs no external test
///         dependency at all.
interface Vm {
    function warp(uint256 newTimestamp) external;
    function prank(address msgSender) external;
    function expectRevert() external;
    function expectRevert(bytes4 revertData) external;
    function expectRevert(bytes calldata revertData) external;
}

/// @notice Test suite for AgentStreak. Run with `forge test`.
contract AgentStreakTest {
    Vm internal constant vm = Vm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);

    uint256 internal constant T0 = 1_700_000_000; // fixed start time
    uint256 internal constant DAY = 86400;

    MockAgentID internal mock;
    AgentStreak internal streak;

    address internal alice = address(0xA11CE);
    address internal bob = address(0xB0B);
    address internal carol = address(0xCA401);

    function setUp() public {
        mock = new MockAgentID();
        streak = new AgentStreak(address(mock));
        vm.warp(T0);
    }

    // ---------------------------------------------------------------
    // Assertion helpers (revert with a message on failure)
    // ---------------------------------------------------------------
    function assertEq(uint256 a, uint256 b, string memory what) internal pure {
        if (a != b) revert(string(abi.encodePacked("assertEq failed: ", what)));
    }

    function assertEq(address a, address b, string memory what) internal pure {
        if (a != b) revert(string(abi.encodePacked("assertEq failed: ", what)));
    }

    function assertTrue(bool cond, string memory what) internal pure {
        if (!cond) revert(string(abi.encodePacked("assertTrue failed: ", what)));
    }

    // ---------------------------------------------------------------
    // Scenario helpers
    // ---------------------------------------------------------------
    function _checkIn(address user) internal {
        vm.prank(user);
        streak.checkIn();
    }

    /// @dev Check `user` in on `numDays` consecutive days starting now.
    function _buildStreak(address user, uint256 numDays) internal {
        for (uint256 i = 0; i < numDays; i++) {
            if (i > 0) vm.warp(block.timestamp + DAY);
            _checkIn(user);
        }
    }

    function _startsWith(string memory s, string memory prefix) internal pure returns (bool) {
        bytes memory b = bytes(s);
        bytes memory p = bytes(prefix);
        if (b.length < p.length) return false;
        for (uint256 i = 0; i < p.length; i++) {
            if (b[i] != p[i]) return false;
        }
        return true;
    }

    // ---------------------------------------------------------------
    // Gating
    // ---------------------------------------------------------------
    function testNonHolderCannotCheckIn() public {
        assertTrue(!streak.hasAgentID(alice), "alice starts without Agent ID");
        vm.expectRevert(abi.encodeWithSelector(AgentStreak.NoAgentID.selector, alice));
        vm.prank(alice);
        streak.checkIn();
    }

    function testHolderCanCheckIn() public {
        mock.grant(alice);
        assertTrue(streak.hasAgentID(alice), "alice holds Agent ID after grant");
        _checkIn(alice);
    }

    // ---------------------------------------------------------------
    // Check-in, streaks and points
    // ---------------------------------------------------------------
    function testFirstCheckIn() public {
        mock.grant(alice);
        _checkIn(alice);
        (uint256 total, uint256 current, uint256 best, uint256 points, uint256 lastDay, uint256 badges) =
            streak.getStats(alice);
        assertEq(total, 1, "totalCheckIns");
        assertEq(current, 1, "currentStreak");
        assertEq(best, 1, "bestStreak");
        assertEq(points, 11, "points = 10 base + 1 streak bonus");
        assertEq(lastDay, T0 / DAY, "lastCheckInDay");
        assertEq(badges, 0, "no badges yet");
        assertEq(streak.participantCount(), 1, "one participant");
        assertEq(streak.participantAt(0), alice, "participant 0 is alice");
        assertTrue(streak.isParticipant(alice), "alice is a participant");
    }

    function testSameDayDoubleCheckInReverts() public {
        mock.grant(alice);
        _checkIn(alice);
        vm.expectRevert(
            abi.encodeWithSelector(AgentStreak.AlreadyCheckedInToday.selector, alice, T0 / DAY)
        );
        vm.prank(alice);
        streak.checkIn();
    }

    function testStreakIncrementsAcrossDays() public {
        mock.grant(alice);
        _buildStreak(alice, 3);
        (uint256 total, uint256 current, uint256 best, uint256 points,,) = streak.getStats(alice);
        assertEq(total, 3, "totalCheckIns");
        assertEq(current, 3, "currentStreak");
        assertEq(best, 3, "bestStreak");
        // points: (10+1) + (10+2) + (10+3) = 36
        assertEq(points, 36, "points accumulate with streak bonus");
    }

    function testStreakResetsAfterGap() public {
        mock.grant(alice);
        _buildStreak(alice, 2); // streak 2
        vm.warp(block.timestamp + 3 * DAY); // miss two full days
        _checkIn(alice);
        (uint256 total, uint256 current, uint256 best, uint256 points,,) = streak.getStats(alice);
        assertEq(total, 3, "totalCheckIns");
        assertEq(current, 1, "streak restarts at 1 after a gap");
        assertEq(best, 2, "bestStreak is preserved");
        // points: 11 + 12 + 11 = 34
        assertEq(points, 34, "points after reset");
    }

    function testPointsBonusCapsAtTwenty() public {
        mock.grant(alice);
        _buildStreak(alice, 25);
        (, uint256 current, uint256 best, uint256 points,,) = streak.getStats(alice);
        assertEq(current, 25, "currentStreak");
        assertEq(best, 25, "bestStreak");
        // days 1..20: 10 + streak  -> 200 + (1+...+20) = 410
        // days 21..25: 10 + 20 = 30 each -> 150 ; total 560
        assertEq(points, 560, "streak bonus caps at +20");
    }

    // ---------------------------------------------------------------
    // Badges
    // ---------------------------------------------------------------
    function testClaimSparkAtThreeDayStreak() public {
        mock.grant(alice);
        _buildStreak(alice, 3);
        vm.prank(alice);
        uint256 tokenId = streak.claimBadge(0);
        assertEq(tokenId, 1, "first badge token id");
        assertEq(streak.ownerOf(tokenId), alice, "badge owner");
        assertEq(streak.balanceOf(alice), 1, "badge balance");
        assertEq(uint256(streak.badgeTierOf(tokenId)), 0, "badge tier");
        (,,,,, uint256 badges) = streak.getStats(alice);
        assertEq(badges, 1, "bitmask has tier 0 set");
        string memory uri = streak.tokenURI(tokenId);
        assertTrue(_startsWith(uri, "data:application/json;base64,"), "tokenURI is a base64 data URI");
        assertTrue(bytes(uri).length > 200, "tokenURI carries JSON + SVG payload");
    }

    function testClaimAllFourTiers() public {
        mock.grant(alice);
        _buildStreak(alice, 30);
        for (uint8 tier = 0; tier < 4; tier++) {
            vm.prank(alice);
            uint256 tokenId = streak.claimBadge(tier);
            assertEq(streak.ownerOf(tokenId), alice, "badge owner");
            assertEq(uint256(streak.badgeTierOf(tokenId)), uint256(tier), "badge tier");
        }
        assertEq(streak.balanceOf(alice), 4, "four badges held");
        (,,,,, uint256 badges) = streak.getStats(alice);
        assertEq(badges, 15, "bitmask 0b1111");
        assertEq(streak.badgeThreshold(0), 3, "Spark threshold");
        assertEq(streak.badgeThreshold(1), 7, "Flame threshold");
        assertEq(streak.badgeThreshold(2), 14, "Blaze threshold");
        assertEq(streak.badgeThreshold(3), 30, "Eternal Flame threshold");
    }

    function testClaimBeforeThresholdReverts() public {
        mock.grant(alice);
        _buildStreak(alice, 2); // best streak 2 < 3 required for Spark
        vm.expectRevert(abi.encodeWithSelector(AgentStreak.StreakTooShort.selector, uint8(0), 2, 3));
        vm.prank(alice);
        streak.claimBadge(0);
    }

    function testBadgeClaimableFromBestStreakAfterReset() public {
        mock.grant(alice);
        _buildStreak(alice, 7); // best streak 7
        vm.warp(block.timestamp + 5 * DAY); // streak lapses
        _checkIn(alice); // current streak back to 1, best stays 7
        vm.prank(alice);
        streak.claimBadge(1); // Flame is earned from bestStreak
        assertEq(streak.balanceOf(alice), 1, "Flame claimed from best streak");
    }

    function testDoubleClaimReverts() public {
        mock.grant(alice);
        _buildStreak(alice, 3);
        vm.prank(alice);
        streak.claimBadge(0);
        vm.expectRevert(abi.encodeWithSelector(AgentStreak.BadgeAlreadyClaimed.selector, alice, uint8(0)));
        vm.prank(alice);
        streak.claimBadge(0);
    }

    function testBadgeClaimRequiresAgentID() public {
        mock.grant(alice);
        _buildStreak(alice, 3);
        mock.revoke(alice); // Agent ID no longer held
        vm.expectRevert(abi.encodeWithSelector(AgentStreak.NoAgentID.selector, alice));
        vm.prank(alice);
        streak.claimBadge(0);
    }

    function testInvalidTierReverts() public {
        mock.grant(alice);
        _buildStreak(alice, 30);
        vm.expectRevert(abi.encodeWithSelector(AgentStreak.InvalidTier.selector, uint8(4)));
        vm.prank(alice);
        streak.claimBadge(4);
    }

    function testSoulboundTransfersAndApprovalsRevert() public {
        mock.grant(alice);
        _buildStreak(alice, 3);
        vm.prank(alice);
        uint256 tokenId = streak.claimBadge(0);

        vm.expectRevert(AgentStreak.Soulbound.selector);
        vm.prank(alice);
        streak.transferFrom(alice, bob, tokenId);

        vm.expectRevert(AgentStreak.Soulbound.selector);
        vm.prank(alice);
        streak.safeTransferFrom(alice, bob, tokenId);

        vm.expectRevert(AgentStreak.Soulbound.selector);
        vm.prank(alice);
        streak.safeTransferFrom(alice, bob, tokenId, bytes(""));

        vm.expectRevert(AgentStreak.Soulbound.selector);
        vm.prank(alice);
        streak.approve(bob, tokenId);

        vm.expectRevert(AgentStreak.Soulbound.selector);
        vm.prank(alice);
        streak.setApprovalForAll(bob, true);

        assertEq(streak.ownerOf(tokenId), alice, "badge never moved");
        assertEq(streak.getApproved(tokenId), address(0), "no approved spender");
        assertTrue(!streak.isApprovedForAll(alice, bob), "no operator approval");
    }

    function testTokenURIOfNonexistentBadgeReverts() public {
        vm.expectRevert(abi.encodeWithSelector(AgentStreak.BadgeDoesNotExist.selector, 999));
        streak.tokenURI(999);
    }

    // ---------------------------------------------------------------
    // Registry / leaderboard support
    // ---------------------------------------------------------------
    function testMultipleParticipantsRegistry() public {
        mock.grant(alice);
        mock.grant(bob);
        mock.grant(carol);
        _buildStreak(alice, 2);
        _checkIn(bob);
        // carol holds an Agent ID but never checks in: not a participant.
        assertEq(streak.participantCount(), 2, "two participants");
        assertEq(streak.participantAt(0), alice, "first participant");
        assertEq(streak.participantAt(1), bob, "second participant");
        assertTrue(!streak.isParticipant(carol), "carol never checked in");

        (uint256 aTotal,,,,,) = streak.getStats(alice);
        (uint256 bTotal,,,,,) = streak.getStats(bob);
        assertEq(aTotal, 2, "alice stats independent");
        assertEq(bTotal, 1, "bob stats independent");
    }

    function testReturningParticipantNotDuplicated() public {
        mock.grant(alice);
        _buildStreak(alice, 5);
        assertEq(streak.participantCount(), 1, "still one participant after 5 days");
    }
}
