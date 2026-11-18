"use strict";

/* =====================================================================
   Agent Streak — frontend
   ---------------------------------------------------------------------
   CONFIG: set CONTRACT_ADDRESS to the deployed AgentStreak address
   after deployment (see README). While it is the zero address the page
   runs in DEMO MODE: it simulates the protocol locally so the whole UI
   can be previewed and screenshotted without a deployment.

   Wallet model (hackathon safety rules): standard injected-wallet
   connect via window.ethereum only. No QR-code or pairing-code login,
   no server-side sessions, no credential collection. Every transaction
   is signed by the user's own wallet.
   ===================================================================== */
const CONFIG = {
  CONTRACT_ADDRESS: "0x23E134C959A322a61aE4Bd48bfCd08956B942938", // AgentStreak on BNB Chain (deployed 2026-11-18)
  AGENT_ID_ADDRESS: "0x60b9262456de011f7d15a54cdd8c48baaa8b022f", // Agent ID contract, BNB Chain mainnet
  CHAIN_ID: 56,
  CHAIN_NAME: "BNB Chain",
  READ_RPC: "https://bsc-dataseed1.bnbchain.org",
  LEADERBOARD_CAP: 250,
};

const STREAK_ABI = [
  "function checkIn()",
  "function claimBadge(uint8 tier) returns (uint256)",
  "function getStats(address user) view returns (uint256 totalCheckIns, uint256 currentStreak, uint256 bestStreak, uint256 points, uint256 lastCheckInDay, uint256 badgesClaimed)",
  "function participantCount() view returns (uint256)",
  "function participantAt(uint256 i) view returns (address)",
  "function hasAgentID(address user) view returns (bool)",
  "event CheckIn(address indexed user, uint256 day, uint256 streak, uint256 pointsAwarded, uint256 totalPoints)",
  "event BadgeClaimed(address indexed user, uint8 indexed tier, uint256 tokenId)",
];

const AGENT_ID_ABI = ["function balanceOf(address owner) view returns (uint256)"];

const TIERS = [
  { name: "Spark", threshold: 3, color: "#f5b942" },
  { name: "Flame", threshold: 7, color: "#f97b1e" },
  { name: "Blaze", threshold: 14, color: "#ef4444" },
  { name: "Eternal Flame", threshold: 30, color: "#a78bfa" },
];

const DEMO = CONFIG.CONTRACT_ADDRESS === "0x0000000000000000000000000000000000000000";
const DAY_MS = 86400000;
const todayUTC = () => Math.floor(Date.now() / DAY_MS);

/* ---------------- state ---------------- */
let account = null; // connected address (live or demo)
let myStats = null; // {totalCheckIns, currentStreak, bestStreak, points, lastCheckInDay, badges}
let busy = false;

/* ---------------- DOM helpers ---------------- */
const $ = (id) => document.getElementById(id);
const shortAddr = (a) => (a ? a.slice(0, 6) + "\u2026" + a.slice(-4) : "");
function setStatus(text) { $("statusLine").textContent = text; }
function flameSVG(color, cls) {
  return (
    '<svg class="' + (cls || "flame") + '" viewBox="0 0 24 24" aria-hidden="true">' +
    '<path d="M12 22c-4.1-3.2-5.6-6.6-4.1-10C8.7 9.9 10 8.4 12 4c2 4.4 3.3 5.9 4.1 8 1.5 3.4 0 6.8-4.1 10z" fill="' +
    color + '"/></svg>'
  );
}

/* =====================================================================
   DEMO MODE — local simulation of the contract rules
   ===================================================================== */
const DEMO_KEY = "agentstreak-demo-v1";
const DEMO_OTHERS = [
  { address: "0x2222222222222222222222222222222222222222", totalCheckIns: 34, currentStreak: 30, bestStreak: 30, points: 890 },
  { address: "0x3333333333333333333333333333333333333333", totalCheckIns: 27, currentStreak: 12, bestStreak: 21, points: 655 },
  { address: "0x4444444444444444444444444444444444444444", totalCheckIns: 19, currentStreak: 3, bestStreak: 14, points: 388 },
  { address: "0x5555555555555555555555555555555555555555", totalCheckIns: 12, currentStreak: 9, bestStreak: 9, points: 264 },
  { address: "0x6666666666666666666666666666666666666666", totalCheckIns: 10, currentStreak: 1, bestStreak: 7, points: 141 },
  { address: "0x7777777777777777777777777777777777777777", totalCheckIns: 4, currentStreak: 2, bestStreak: 3, points: 58 },
];

function demoLoad() {
  try {
    const raw = localStorage.getItem(DEMO_KEY);
    if (raw) return JSON.parse(raw);
  } catch (e) { /* storage unavailable: fall through to defaults */ }
  return {
    address: "0x1111111111111111111111111111111111111111",
    totalCheckIns: 16,
    currentStreak: 5,
    bestStreak: 14,
    points: 342,
    lastCheckInDay: todayUTC() - 1,
    badges: 3, // Spark + Flame claimed, Blaze claimable at best streak 14
  };
}
function demoSave(s) {
  try { localStorage.setItem(DEMO_KEY, JSON.stringify(s)); } catch (e) { /* ignore */ }
}
let demoState = DEMO ? demoLoad() : null;

async function demoConnect() {
  account = demoState.address;
  myStats = demoState;
  onConnected("Demo account connected — this is a local simulation.");
  renderAll();
  renderLeaderboard(demoBoardRows());
}
function demoBoardRows() {
  const mine = {
    address: demoState.address,
    totalCheckIns: demoState.totalCheckIns,
    currentStreak: demoState.currentStreak,
    bestStreak: demoState.bestStreak,
    points: demoState.points,
  };
  return DEMO_OTHERS.concat([mine]);
}
async function demoCheckIn() {
  const s = demoState;
  const t = todayUTC();
  if (s.totalCheckIns > 0 && s.lastCheckInDay === t) throw new Error("Already checked in today.");
  s.currentStreak = s.lastCheckInDay === t - 1 ? s.currentStreak + 1 : 1;
  if (s.currentStreak > s.bestStreak) s.bestStreak = s.currentStreak;
  s.points += 10 + Math.min(s.currentStreak, 20);
  s.totalCheckIns += 1;
  s.lastCheckInDay = t;
  demoSave(s);
  myStats = s;
}
async function demoClaim(tier) {
  demoState.badges |= 1 << tier;
  demoSave(demoState);
  myStats = demoState;
}

/* =====================================================================
   LIVE MODE — ethers v6 against BNB Chain
   ===================================================================== */
let readProvider = null;
let readContract = null;
let agentIdContract = null;

function initReaders() {
  readProvider = new ethers.JsonRpcProvider(CONFIG.READ_RPC);
  readContract = new ethers.Contract(CONFIG.CONTRACT_ADDRESS, STREAK_ABI, readProvider);
  agentIdContract = new ethers.Contract(CONFIG.AGENT_ID_ADDRESS, AGENT_ID_ABI, readProvider);
}

async function liveConnect() {
  if (typeof window.ethereum === "undefined") {
    setStatus("No wallet found. Install a BNB Chain compatible wallet extension, then reload.");
    return;
  }
  if (typeof ethers === "undefined") {
    setStatus("Could not load the ethers library. Check your connection and reload.");
    return;
  }
  const browserProvider = new ethers.BrowserProvider(window.ethereum);
  const accounts = await browserProvider.send("eth_requestAccounts", []);
  if (!accounts || accounts.length === 0) return;
  account = accounts[0];
  initReaders();

  const network = await browserProvider.getNetwork();
  $("networkChip").hidden = false;
  if (Number(network.chainId) !== CONFIG.CHAIN_ID) {
    $("networkChip").textContent = "Wrong network";
    setStatus("You are connected. Switch to BNB Chain (chainId 56) to check in or claim badges.");
  } else {
    $("networkChip").textContent = CONFIG.CHAIN_NAME;
  }

  // The identity check: does this address hold an Agent ID?
  const held = await agentIdContract.balanceOf(account);
  if (held === 0n) {
    onConnected("Wallet connected.");
    $("appPanel").hidden = true;
    $("gatePanel").hidden = false;
    $("leaderboardEmpty").textContent = "The leaderboard is open to everyone, but check-ins need an Agent ID.";
    await loadLeaderboard();
    return;
  }
  onConnected("Agent ID verified — welcome back, holder.");
  await refreshStats();
  await loadLeaderboard();
}

async function signerContract() {
  const browserProvider = new ethers.BrowserProvider(window.ethereum);
  const network = await browserProvider.getNetwork();
  if (Number(network.chainId) !== CONFIG.CHAIN_ID) {
    await window.ethereum.request({
      method: "wallet_switchEthereumChain",
      params: [{ chainId: "0x" + CONFIG.CHAIN_ID.toString(16) }],
    });
  }
  const signer = await browserProvider.getSigner();
  return new ethers.Contract(CONFIG.CONTRACT_ADDRESS, STREAK_ABI, signer);
}

function statsFromTuple(t) {
  return {
    totalCheckIns: Number(t[0]),
    currentStreak: Number(t[1]),
    bestStreak: Number(t[2]),
    points: Number(t[3]),
    lastCheckInDay: Number(t[4]),
    badges: Number(t[5]),
  };
}

async function refreshStats() {
  myStats = statsFromTuple(await readContract.getStats(account));
  renderAll();
}

async function loadLeaderboard() {
  const count = Number(await readContract.participantCount());
  const n = Math.min(count, CONFIG.LEADERBOARD_CAP);
  const rows = [];
  for (let i = 0; i < n; i++) {
    const addr = await readContract.participantAt(i);
    const s = statsFromTuple(await readContract.getStats(addr));
    rows.push({ address: addr, ...s });
  }
  renderLeaderboard(rows);
}

async function liveCheckIn() {
  const c = await signerContract();
  const tx = await c.checkIn();
  setStatus("Check-in sent — waiting for confirmation\u2026");
  await tx.wait();
}
async function liveClaim(tier) {
  const c = await signerContract();
  const tx = await c.claimBadge(tier);
  setStatus("Badge claim sent — waiting for confirmation\u2026");
  await tx.wait();
}

/* =====================================================================
   Rendering
   ===================================================================== */
function onConnected(msg) {
  $("connectBtn").hidden = true;
  const chip = $("accountChip");
  chip.hidden = false;
  chip.textContent = shortAddr(account) + (DEMO ? " (demo)" : "");
  $("gatePanel").hidden = true;
  $("appPanel").hidden = false;
  setStatus(msg);
}

function renderAll() {
  if (!myStats) return;
  $("statStreak").textContent = myStats.currentStreak;
  $("statPoints").textContent = myStats.points;
  $("statTotal").textContent = myStats.totalCheckIns;
  $("statBest").textContent = myStats.bestStreak;
  renderCheckIn();
  renderBadges();
}

function checkedInToday() {
  return myStats && myStats.totalCheckIns > 0 && myStats.lastCheckInDay === todayUTC();
}

function renderCheckIn() {
  const btn = $("checkInBtn");
  const note = $("checkInNote");
  if (checkedInToday()) {
    btn.disabled = true;
    btn.textContent = "Checked in today";
    note.textContent = "Nice — day " + myStats.currentStreak + " of your streak is in the books. Come back tomorrow to keep it alive.";
    $("countdown").hidden = false;
  } else {
    btn.disabled = busy;
    btn.textContent = myStats.currentStreak > 0 && myStats.lastCheckInDay === todayUTC() - 1
      ? "Check in — extend your streak to " + (myStats.currentStreak + 1) + " days"
      : "Check in for today";
    note.textContent = myStats.totalCheckIns === 0
      ? "Your first check-in starts your streak."
      : myStats.lastCheckInDay === todayUTC() - 1
        ? "You checked in yesterday — today keeps the streak going."
        : "Your previous streak ended. Today starts a new one at day 1.";
    $("countdown").hidden = true;
  }
}

function renderBadges() {
  const grid = $("badgeGrid");
  grid.innerHTML = "";
  TIERS.forEach((tier, i) => {
    const claimed = (myStats.badges & (1 << i)) !== 0;
    const claimable = !claimed && myStats.bestStreak >= tier.threshold;
    const card = document.createElement("div");
    card.className = "badge-card" + (claimed ? " claimed" : claimable ? " claimable" : " locked");
    card.style.setProperty("--tier-color", tier.color);
    let bottom;
    if (claimed) {
      bottom = '<div class="badge-state claimed">Claimed</div>';
    } else if (claimable) {
      bottom = '<button class="btn-claim" data-tier="' + i + '">Claim badge</button>';
    } else {
      const pct = Math.min(100, Math.round((myStats.bestStreak / tier.threshold) * 100));
      bottom =
        '<div class="progress"><div style="width:' + pct + '%"></div></div>' +
        '<div class="badge-state">' + myStats.bestStreak + " / " + tier.threshold + " days</div>";
    }
    card.innerHTML =
      '<div class="flame-wrap">' + flameSVG(tier.color) + "</div>" +
      '<div class="badge-name">' + tier.name + "</div>" +
      '<div class="badge-req">Best streak of ' + tier.threshold + " days</div>" +
      bottom;
    grid.appendChild(card);
  });
  grid.querySelectorAll(".btn-claim").forEach((b) => {
    b.addEventListener("click", () => onClaim(Number(b.dataset.tier)));
  });
}

function renderLeaderboard(rows) {
  const sorted = rows.slice().sort((a, b) => b.points - a.points || b.bestStreak - a.bestStreak);
  const body = $("leaderboardBody");
  body.innerHTML = "";
  sorted.forEach((r, idx) => {
    const me = account && r.address.toLowerCase() === account.toLowerCase();
    const tr = document.createElement("tr");
    if (me) tr.className = "me";
    tr.innerHTML =
      "<td>" + (idx + 1) + "</td>" +
      '<td><span class="addr">' + shortAddr(r.address) + "</span>" + (me ? '<span class="you-tag">YOU</span>' : "") + "</td>" +
      "<td>" + r.bestStreak + "</td>" +
      "<td>" + r.currentStreak + "</td>" +
      "<td><strong>" + r.points + "</strong></td>";
    body.appendChild(tr);
  });
  $("leaderboardEmpty").hidden = sorted.length > 0;
  if (sorted.length === 0) $("leaderboardEmpty").textContent = "No check-ins yet — be the first name on this board.";
  $("leaderboardTable").hidden = sorted.length === 0;
}

/* ---------------- countdown to the next UTC day ---------------- */
function tickCountdown() {
  if (!checkedInToday()) return;
  const msLeft = (todayUTC() + 1) * DAY_MS - Date.now();
  const s = Math.max(0, Math.floor(msLeft / 1000));
  const hh = String(Math.floor(s / 3600)).padStart(2, "0");
  const mm = String(Math.floor((s % 3600) / 60)).padStart(2, "0");
  const ss = String(s % 60).padStart(2, "0");
  $("countdownTime").textContent = hh + ":" + mm + ":" + ss;
  if (msLeft <= 0 && myStats) renderAll();
}
setInterval(tickCountdown, 1000);

/* ---------------- actions ---------------- */
async function onCheckIn() {
  if (busy || !account) return;
  busy = true;
  renderCheckIn();
  try {
    if (DEMO) await demoCheckIn(); else await liveCheckIn();
    if (DEMO) { renderAll(); renderLeaderboard(demoBoardRows()); }
    else { await refreshStats(); await loadLeaderboard(); }
    setStatus("Checked in! Streak day " + myStats.currentStreak + " — see you tomorrow.");
  } catch (e) {
    setStatus("Check-in failed: " + friendlyError(e));
  } finally {
    busy = false;
    if (myStats) renderAll();
  }
}

async function onClaim(tier) {
  if (busy || !account) return;
  busy = true;
  try {
    if (DEMO) await demoClaim(tier); else await liveClaim(tier);
    if (DEMO) renderAll(); else await refreshStats();
    setStatus(TIERS[tier].name + " badge claimed — it is soulbound to your wallet forever.");
  } catch (e) {
    setStatus("Claim failed: " + friendlyError(e));
  } finally {
    busy = false;
    if (myStats) renderAll();
  }
}

function friendlyError(e) {
  const msg = (e && (e.shortMessage || e.message)) || "unknown error";
  if (/user rejected|denied/i.test(msg)) return "you rejected the transaction in your wallet.";
  if (/AlreadyCheckedInToday/.test(msg)) return "you already checked in today.";
  if (/NoAgentID/.test(msg)) return "this wallet does not hold an Agent ID.";
  return msg.length > 140 ? msg.slice(0, 140) + "\u2026" : msg;
}

/* ---------------- boot ---------------- */
$("connectBtn").addEventListener("click", async () => {
  try {
    if (DEMO) await demoConnect(); else await liveConnect();
  } catch (e) {
    setStatus("Connection failed: " + friendlyError(e));
  }
});
$("checkInBtn").addEventListener("click", onCheckIn);

if (typeof window.ethereum !== "undefined" && !DEMO) {
  window.ethereum.on("accountsChanged", () => window.location.reload());
  window.ethereum.on("chainChanged", () => window.location.reload());
}

if (DEMO) {
  $("demoBanner").hidden = false;
  $("connectBtn").textContent = "Connect wallet (demo)";
  // Preview hook: ?view=leaderboard collapses the sections above the
  // board so a headless screenshot frames the leaderboard directly.
  if (new URLSearchParams(window.location.search).get("view") === "leaderboard") {
    document.body.classList.add("preview-board");
  }
  // Auto-connect in demo mode so previews show the full UI immediately.
  demoConnect();
}
