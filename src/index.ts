/**
 * Sovereign Agent — Phase 0 CLI Entry Point
 * 
 * Boots the 5-machine kernel and provides an interactive CLI
 * for sending messages and inspecting agent state.
 * 
 * Usage:
 *   npm start          — Start interactive CLI
 *   npm test           — Run test harness
 */

import { SovereignAgentKernel } from "./kernel.js";
import { BudgetCategory } from "./types.js";
import * as readline from "readline";

async function main(): Promise<void> {
  console.log("");
  console.log("╔══════════════════════════════════════════════════════════════╗");
  console.log("║           SOVEREIGN AGENT — Phase 0 Implementation          ║");
  console.log("║                                                              ║");
  console.log("║  5 core machines from the P language specification:          ║");
  console.log("║    WalletIdentity • Treasury • MessageBus                    ║");
  console.log("║    ToolExecutor • AgentLoop                                  ║");
  console.log("║                                                              ║");
  console.log("║  Stub LLM provider (Phase 1+ adds real inference)           ║");
  console.log("╚══════════════════════════════════════════════════════════════╝");
  console.log("");

  const kernel = new SovereignAgentKernel();

  // Register a CLI channel to receive agent responses.
  const rl = readline.createInterface({
    input: process.stdin,
    output: process.stdout,
    prompt: "you> ",
  });

  kernel.onMessage("cli", (msg) => {
    console.log("");
    console.log("┌─ Agent Response ─────────────────────────────────────────────");
    console.log("│");
    const lines = msg.content.split("\n");
    for (const line of lines) {
      console.log(`│  ${line}`);
    }
    console.log("│");
    console.log("└──────────────────────────────────────────────────────────────");
    console.log("");
    rl.prompt();
  });

  // Register some Phase 0 demo tools.
  kernel.registerTool(
    {
      name: "get_time",
      description: "Get the current time",
      estimatedCost: { amounts: [], category: BudgetCategory.TOOLS },
    },
    () => new Date().toISOString()
  );

  kernel.registerTool(
    {
      name: "echo",
      description: "Echo back the input",
      estimatedCost: { amounts: [], category: BudgetCategory.TOOLS },
    },
    (call) => `Echo: ${call.arguments["text"] || "(empty)"}`
  );

  // Start the kernel.
  await kernel.start({ keySource: "dev:phase0-stub-key" });

  console.log("Commands:");
  console.log("  Type a message    — Send to the agent");
  console.log("  /status           — Show kernel status");
  console.log("  /treasury         — Show treasury report");
  console.log("  /wallet           — Show wallet info");
  console.log("  /tools            — List registered tools");
  console.log("  /quit             — Shutdown and exit");
  console.log("");

  rl.prompt();

  rl.on("line", async (line) => {
    const input = line.trim();
    if (!input) {
      rl.prompt();
      return;
    }

    if (input === "/quit" || input === "/exit") {
      await kernel.stop();
      rl.close();
      process.exit(0);
    }

    if (input === "/status") {
      console.log("");
      console.log("┌─ Kernel Status ───────────────────────────────────────────────");
      console.log(`│  Running:         ${kernel.isRunning()}`);
      console.log(`│  Wallet State:    ${kernel.wallet.getWalletState()}`);
      console.log(`│  Wallet Address:  ${kernel.wallet.getAddress()}`);
      console.log(`│  Treasury State:  ${kernel.treasury.getTreasuryState()}`);
      console.log(`│  Tools:           ${kernel.toolExecutor.getToolNames().join(", ") || "(none)"}`);
      console.log(`│  Active Sessions: ${kernel.agent.getActiveSessionCount()}`);
      console.log("└──────────────────────────────────────────────────────────────");
      console.log("");
      rl.prompt();
      return;
    }

    if (input === "/treasury") {
      const report = kernel.treasury.getReport();
      console.log("");
      console.log("┌─ Treasury Report ─────────────────────────────────────────────");
      console.log(`│  State:           ${report.state}`);
      console.log(`│  Total Value:     $${(report.totalValueUsd / 1_000_000).toFixed(2)} USD`);
      console.log(`│  Daily Burn:      $${(report.dailyBurnUsd / 1_000_000).toFixed(4)} USD`);
      console.log(`│  Runway:          ${report.runwayDays} days`);
      console.log(`│  Budget:          INF=${report.budget.inference}% TOOL=${report.budget.tools}% INFRA=${report.budget.infrastructure}% MSG=${report.budget.messaging}% RSV=${report.budget.reserve}%`);
      console.log(`│  Balances:`);
      for (const b of report.balances) {
        console.log(`│    ${b.chain}/${b.token}: ${b.amount} ($${(b.usdEstimate / 1_000_000).toFixed(2)})`);
      }
      console.log(`│  Recent Expenses: ${report.recentExpenses.length}`);
      for (const e of report.recentExpenses.slice(-5)) {
        console.log(`│    [${e.category}] ${e.amount} ${e.token} — ${e.description}`);
      }
      console.log("└──────────────────────────────────────────────────────────────");
      console.log("");
      rl.prompt();
      return;
    }

    if (input === "/wallet") {
      console.log("");
      console.log("┌─ Wallet Identity ─────────────────────────────────────────────");
      console.log(`│  State:    ${kernel.wallet.getWalletState()}`);
      console.log(`│  Address:  ${kernel.wallet.getAddress()}`);
      console.log(`│  Machine:  ${kernel.wallet.currentState}`);
      console.log("└──────────────────────────────────────────────────────────────");
      console.log("");
      rl.prompt();
      return;
    }

    if (input === "/tools") {
      const tools = kernel.toolExecutor.getToolNames();
      console.log("");
      console.log("┌─ Registered Tools ────────────────────────────────────────────");
      if (tools.length === 0) {
        console.log("│  (no tools registered)");
      } else {
        for (const t of tools) {
          console.log(`│  • ${t}`);
        }
      }
      console.log("└──────────────────────────────────────────────────────────────");
      console.log("");
      rl.prompt();
      return;
    }

    // Send as a message to the agent.
    kernel.sendMessage(input);

    // Wait for the agent to finish processing.
    await kernel.waitForIdle();
  });

  rl.on("close", async () => {
    await kernel.stop();
    process.exit(0);
  });
}

main().catch((err) => {
  console.error("Fatal error:", err);
  process.exit(1);
});
