# Agent Streak

**A daily check-in & streak protocol exclusively for Agent ID holders, with soulbound milestone badges.**

Agent Streak turns an Agent ID into a living identity: holders check in once a day on BNB Chain, build streaks, earn points, and claim soulbound ERC-721 badges at streak milestones. A public leaderboard ranks every participant by points. It is a free reputation game — no fees, no deposits, no assets at risk, and no promised returns of any kind.

## How Agent ID is integrated

Agent ID is the identity layer for the whole protocol — not a cosmetic login:

- **The gate.** Every state-changing function (`checkIn`, `claimBadge`) first calls the official integration check on the Agent ID contract (BNB Chain mainnet: `0x60b9262456de011f7d15a54cdd8c48baaa8b022f`): the caller must satisfy `balanceOf(caller) > 0`, otherwise the call reverts with `NoAgentID`. The check is performed live on every call, so losing the Agent ID immediately locks the account out.
- **The identity.** There are no usernames, passwords, or server-side accounts. The wallet address that holds the Agent ID *is* the participant identity; the participant registry, streaks, points and badges are all keyed to it.
- **The proof.** Milestone badges are soulbound ERC-721 tokens minted only by the streak logic to Agent ID holders. Because badges can never be transferred, a badge is durable on-chain proof that a specific Agent ID holder showed up, day after day.

Agent ID exposes no enumerable or name-resolution getters, so the protocol deliberately relies only on `balanceOf` — exactly the integration method described in the hackathon announcement.

## Gameplay

| Mechanic | Rule |
| --- | --- |
| Check-in | One per account per UTC day (`block.timestamp / 86400`) |
| Streak | Consecutive days increment it; a missed day restarts it at 1; best streak is kept forever |
| Points | 10 base + streak bonus of `min(currentStreak, 20)` per check-in |
| Badges | Soulbound ERC-721 at best streak **3 (Spark)**, **7 (Flame)**, **14 (Blaze)**, **30 (Eternal Flame)**; each tier claimable once, from best streak (a lapsed streak never revokes a badge) |
| Leaderboard | On-chain participant registry (`participantCount` / `participantAt` / `getStats`); the frontend enumerates and sorts by points |

Badge artwork and metadata are generated entirely on-chain: `tokenURI` returns a `data:` URI containing JSON with an inline SVG image (original geometric flame art, recoloured per tier).

## Architecture

```
src/
  IAgentID.sol     Minimal interface: balanceOf(address) — the only Agent ID call used
  AgentStreak.sol  The whole protocol: check-ins, streaks, points, registry,
                   and the soulbound badge ERC-721 (implemented in-contract,
                   so there is exactly one contract to audit and verify)
  Base64.sol       Small RFC 4648 encoder used to build data: URIs on-chain
  MockAgentID.sol  Test double for Agent ID (tests only, never deployed)
test/
  AgentStreak.t.sol  18 Foundry tests (see below)
script/
  Deploy.s.sol     Broadcast deployment wired to the mainnet Agent ID contract
web/
  index.html, app.js, style.css   Static frontend (vanilla JS + ethers v6 via CDN)
  preview/         Screenshots of the frontend in demo mode
```

Design choices worth noting:

- **Zero dependencies.** The contracts import nothing external — no OpenZeppelin, no forge-std — so the deployed bytecode is small, self-contained and trivially verifiable.
- **No admin surface.** The contract has no owner, no pause, no upgrade path, no fee switch and no function that can move user assets (it never holds any). The Agent ID contract address is `immutable`.
- **Soulbound by construction.** All ERC-721 transfer and approval entry points revert with `Soulbound()`; badges can only ever be minted by `claimBadge` and can never leave the earning wallet.
- **Wallet safety (hackathon red lines).** The frontend uses only the standard injected-wallet flow (`window.ethereum`). There is no QR-code or pairing-code login, no server-side session storage, and no collection of credentials of any kind; every transaction is signed by the user's own wallet.

## Run the tests

Requires [Foundry](https://getfoundry.sh).

```bash
forge build
forge test
```

The suite covers: Agent ID gating (non-holders revert on check-in and on badge claim, including after a mock revocation), first check-in stats, same-day double check-in revert, streak increments across days (`vm.warp`), streak reset after a gap, exact points math including the +20 bonus cap, badge claims at every tier, claiming from best streak after a lapse, double-claim reverts, invalid-tier reverts, soulbound transfer/approval reverts, `tokenURI` shape, and participant-registry enumeration without duplicates.

## Deploy & verify (BNB Chain mainnet)

> The deployer key is supplied through the environment at deploy time and is never stored in this repository.

```bash
export BSC_RPC_URL="https://bsc-dataseed1.bnbchain.org"
export DEPLOYER_PRIVATE_KEY="<set at deploy time>"

# Option A: deploy script (wired to the mainnet Agent ID contract)
forge script script/Deploy.s.sol:Deploy \
  --rpc-url $BSC_RPC_URL --broadcast --private-key $DEPLOYER_PRIVATE_KEY

# Option B: forge create
forge create src/AgentStreak.sol:AgentStreak \
  --rpc-url $BSC_RPC_URL --broadcast --private-key $DEPLOYER_PRIVATE_KEY \
  --constructor-args 0x60B9262456dE011F7d15a54CdD8c48bAaa8B022F

# Verify on BscScan (requires a BscScan API key in the environment)
forge verify-contract <DEPLOYED_ADDRESS> src/AgentStreak.sol:AgentStreak \
  --chain bsc --constructor-args $(cast abi-encode "constructor(address)" 0x60B9262456dE011F7d15a54CdD8c48bAaa8B022F) \
  --etherscan-api-key $BSCSCAN_API_KEY
```

After deployment:

1. Put the deployed address into `CONFIG.CONTRACT_ADDRESS` at the top of `web/app.js`.
2. Host the `web/` folder on any static host.

## Run the frontend locally

```bash
cd web && python3 -m http.server 8000
# open http://localhost:8000
```

While `CONFIG.CONTRACT_ADDRESS` is the zero address, the page runs in **demo mode**: a banner says so, and the protocol is simulated locally (with a sample leaderboard) so every screen — stats, check-in, countdown, badge states, leaderboard — can be previewed without a deployment. Demo state persists in `localStorage`.

## Hackathon submission materials (draft)

- **Project name:** Agent Streak
- **One-liner:** A daily check-in and streak protocol exclusively for Agent ID holders, with soulbound milestone badges and an on-chain leaderboard.
- **Agent ID usage description:** Agent ID is the protocol's identity layer. The AgentStreak contract gates every action with the official check — `balanceOf(msg.sender) > 0` on the Agent ID contract (`0x60b9262456de011f7d15a54cdd8c48baaa8b022f`) — evaluated live on each call. Only Agent ID holders can check in, build streaks, earn points, appear on the leaderboard, or claim the soulbound milestone badges (Spark 3d, Flame 7d, Blaze 14d, Eternal Flame 30d). This gives Agent ID a recurring, everyday use case — a reason to return daily — and gives holders a portable, non-transferable on-chain reputation record bound to their Agent ID identity.
- **Contract address:** `<deployed AgentStreak address — filled in at submission>`
- **Website:** `<hosted web/ URL — filled in at submission>`

## License

MIT — see [LICENSE](LICENSE).
