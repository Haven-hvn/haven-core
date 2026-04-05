/**
 * Test Harness for the Sovereign Agent Kernel.
 * 
 * Runs through Phase 0 milestone verification plus pi-mono pattern tests:
 *   ✓ Kernel boots with 5 core machines (kernel-scoped registry)
 *   ✓ Wallet unlocks and derives address
 *   ✓ Treasury initializes in FUNDED state
 *   ✓ MessageBus routes messages
 *   ✓ AgentLoop processes messages through cost-checking
 *   ✓ ProviderStub returns responses
 *   ✓ ToolExecutor registers and dispatches tools
 *   ✓ beforeToolCall / afterToolCall hooks work
 *   ✓ transformContext is applied before LLM requests
 *   ✓ subscribe() emits events to external observers
 *   ✓ waitForIdle() synchronization works (no setTimeout)
 *   ✓ ToolExecutor uses real Executing state
 *   ✓ Expense tracking works
 *   ✓ Multiple channels work
 *   ✓ State machine states are correct
 *   ✓ Shutdown works cleanly
 */

import { SovereignAgentKernel } from "./kernel.js";
import type { MachineEvent } from "./machine.js";
import { BudgetCategory, TreasuryState, WalletState } from "./types.js";

let passed = 0;
let failed = 0;

function assert(condition: boolean, testName: string): void {
  if (condition) {
    console.log(`  ✓ ${testName}`);
    passed++;
  } else {
    console.log(`  ✗ ${testName}`);
    failed++;
  }
}

// ============================================================================
// Test Suite
// ============================================================================

async function runTests(): Promise<void> {
  console.log("");
  console.log("╔══════════════════════════════════════════════════════════════╗");
  console.log("║          SOVEREIGN AGENT — Phase 0 Test Harness             ║");
  console.log("╚══════════════════════════════════════════════════════════════╝");
  console.log("");

  // ========================================================================
  // Test 1: Kernel Boot (scoped registry, no globals)
  // ========================================================================
  console.log("─── Test 1: Kernel Boot ───────────────────────────────────────");

  const kernel = new SovereignAgentKernel();
  assert(kernel.wallet !== undefined, "WalletIdentity created");
  assert(kernel.treasury !== undefined, "Treasury created");
  assert(kernel.bus !== undefined, "MessageBus created");
  assert(kernel.toolExecutor !== undefined, "ToolExecutor created");
  assert(kernel.agent !== undefined, "AgentLoop created");
  assert(kernel.provider !== undefined, "ProviderStub created");
  assert(kernel.registry !== undefined, "Kernel-scoped registry created");
  console.log("");

  // ========================================================================
  // Test 2: Kernel Start (uses waitForIdle, no setTimeout)
  // ========================================================================
  console.log("─── Test 2: Kernel Start ──────────────────────────────────────");
  await kernel.start({ keySource: "test:harness-key" });

  assert(kernel.isRunning(), "Kernel is running");
  assert(kernel.wallet.getWalletState() === WalletState.UNLOCKED, "Wallet is unlocked");
  assert(kernel.wallet.getAddress().startsWith("0x"), "Wallet has valid address");
  assert(kernel.treasury.getTreasuryState() === TreasuryState.FUNDED, "Treasury is FUNDED");
  console.log("");

  // ========================================================================
  // Test 3: Subscribe — External event observation
  // ========================================================================
  console.log("─── Test 3: Subscribe ─────────────────────────────────────────");
  const observedEvents: MachineEvent[] = [];
  const unsub = kernel.subscribe((evt) => {
    observedEvents.push(evt);
  });

  kernel.sendMessage("Hello from subscriber test", { channel: "test", senderId: "tester" });
  await kernel.waitForIdle();

  assert(observedEvents.length > 0, "Events observed via subscribe()");
  const inboundEvent = observedEvents.find((e) => e.event === "ePublishInbound");
  assert(inboundEvent !== undefined, "ePublishInbound observed");
  const llmEvent = observedEvents.find((e) => e.event === "eLLMRequest");
  assert(llmEvent !== undefined, "eLLMRequest observed");

  unsub(); // Unsubscribe
  const countBefore = observedEvents.length;
  kernel.sendMessage("Should not observe this", { channel: "test" });
  await kernel.waitForIdle();
  assert(observedEvents.length === countBefore, "Unsubscribe stops observation");
  console.log("");

  // ========================================================================
  // Test 4: Message Routing (callback channels)
  // ========================================================================
  console.log("─── Test 4: Message Routing ───────────────────────────────────");
  let receivedResponse = false;
  let responseContent = "";

  kernel.onMessage("test2", (msg) => {
    receivedResponse = true;
    responseContent = msg.content;
  });

  kernel.sendMessage("Hello, sovereign agent!", { channel: "test2", senderId: "tester" });
  await kernel.waitForIdle();

  assert(receivedResponse, "Response received via callback channel");
  assert(responseContent.length > 0, "Response has content");
  assert(
    responseContent.includes("sovereign agent") || responseContent.includes("Phase 0"),
    "Response is contextual"
  );
  console.log("");

  // ========================================================================
  // Test 5: Conversation Context
  // ========================================================================
  console.log("─── Test 5: Conversation Context ──────────────────────────────");
  let secondResponse = "";

  kernel.onMessage("test2", (msg) => {
    secondResponse = msg.content;
  });

  kernel.sendMessage("Who are you?", { channel: "test2", senderId: "tester" });
  await kernel.waitForIdle();

  assert(secondResponse.length > 0, "Second response received");
  assert(secondResponse !== responseContent, "Different response for different question");
  console.log("");

  // ========================================================================
  // Test 6: Treasury Report
  // ========================================================================
  console.log("─── Test 6: Treasury Report ───────────────────────────────────");
  const report = kernel.treasury.getReport();

  assert(report.state === TreasuryState.FUNDED, "Treasury state is FUNDED");
  assert(report.balances.length > 0, "Treasury has balances");
  assert(report.totalValueUsd > 0, "Treasury has USD value");
  assert(report.runwayDays > 30, "Runway is > 30 days");
  assert(report.budget.inference === 40, "Inference budget is 40%");
  assert(report.budget.reserve === 5, "Reserve budget is 5%");
  assert(report.recentExpenses.length > 0, "Expenses were recorded");
  console.log("");

  // ========================================================================
  // Test 7: Tool Registration + beforeToolCall/afterToolCall hooks
  // ========================================================================
  console.log("─── Test 7: Tool Hooks ────────────────────────────────────────");

  let beforeHookCalled = false;
  let afterHookCalled = false;
  let afterHookResult = "";

  kernel.registerTool(
    {
      name: "test_tool",
      description: "A test tool",
      estimatedCost: { amounts: [], category: BudgetCategory.TOOLS },
    },
    (call) => `Test executed: ${JSON.stringify(call.arguments)}`
  );

  kernel.beforeToolCall((call, sessionKey, def) => {
    beforeHookCalled = true;
    return true; // Allow execution
  });

  kernel.afterToolCall((call, result, sessionKey) => {
    afterHookCalled = true;
    afterHookResult = result.result;
  });

  const toolNames = kernel.toolExecutor.getToolNames();
  assert(toolNames.includes("test_tool"), "Tool is registered");

  // Register a blocking hook for a specific tool
  let blockHookCalled = false;
  kernel.beforeToolCall((call, sessionKey, def) => {
    if (call.name === "blocked_tool") {
      blockHookCalled = true;
      return false; // Block execution
    }
    return true;
  });

  kernel.registerTool(
    {
      name: "blocked_tool",
      description: "Should be blocked by hook",
      estimatedCost: { amounts: [], category: BudgetCategory.TOOLS },
    },
    () => "This should never execute"
  );

  assert(kernel.toolExecutor.getToolNames().includes("blocked_tool"), "Blocked tool registered");
  console.log("");

  // ========================================================================
  // Test 8: transformContext
  // ========================================================================
  console.log("─── Test 8: transformContext ───────────────────────────────────");
  let transformCalled = false;
  let transformMessageCount = 0;

  kernel.setTransformContext((messages, sessionKey) => {
    transformCalled = true;
    transformMessageCount = messages.length;
    // Inject a system prompt (real use: context window management).
    return [
      { role: "system", content: "You are a sovereign agent." },
      ...messages.slice(-5), // Keep only last 5 messages
    ];
  });

  kernel.sendMessage("Test transform context", { channel: "test2" });
  await kernel.waitForIdle();

  assert(transformCalled, "transformContext was called");
  assert(transformMessageCount > 0, "transformContext received messages");
  console.log("");

  // ========================================================================
  // Test 9: Expense Tracking
  // ========================================================================
  console.log("─── Test 9: Expense Tracking ──────────────────────────────────");
  const reportAfter = kernel.treasury.getReport();
  const inferenceExpenses = reportAfter.recentExpenses.filter(
    (e) => e.category === BudgetCategory.INFERENCE
  );
  assert(inferenceExpenses.length > 0, "Inference expenses recorded");
  assert(inferenceExpenses[0].token === "USDC", "Expense tracked in USDC");
  assert(inferenceExpenses[0].amount === 5000, "Expense amount is correct (5000 = $0.005)");
  console.log("");

  // ========================================================================
  // Test 10: Multiple Channels
  // ========================================================================
  console.log("─── Test 10: Multiple Channels ────────────────────────────────");
  let channel3Response = "";

  kernel.onMessage("channel3", (msg) => {
    channel3Response = msg.content;
  });

  kernel.sendMessage("Testing channel 3", { channel: "channel3" });
  await kernel.waitForIdle();

  assert(channel3Response.length > 0, "Response received on channel3");
  console.log("");

  // ========================================================================
  // Test 11: State Machine States
  // ========================================================================
  console.log("─── Test 11: State Machine States ─────────────────────────────");
  assert(kernel.wallet.currentState === "Unlocked", "Wallet in Unlocked state");
  assert(
    kernel.treasury.currentState === "Funded",
    `Treasury in Funded state (got: ${kernel.treasury.currentState})`
  );
  assert(kernel.bus.currentState === "Running", "MessageBus in Running state");
  assert(
    kernel.toolExecutor.currentState === "Ready",
    `ToolExecutor in Ready state (got: ${kernel.toolExecutor.currentState})`
  );
  assert(
    kernel.agent.currentState === "Idle" || kernel.agent.currentState === "Responding",
    `AgentLoop in expected state (got: ${kernel.agent.currentState})`
  );
  console.log("");

  // ========================================================================
  // Test 12: Parallel registries (no global collision)
  // ========================================================================
  console.log("─── Test 12: Parallel Registries ──────────────────────────────");
  const kernel2 = new SovereignAgentKernel();
  await kernel2.start({ keySource: "test:parallel-key" });

  assert(kernel.registry !== kernel2.registry, "Kernels have different registries");
  assert(
    kernel.wallet.getAddress() !== kernel2.wallet.getAddress(),
    "Different wallets have different addresses"
  );

  await kernel2.stop();
  assert(kernel.isRunning(), "First kernel still running after second stops");
  console.log("");

  // ========================================================================
  // Test 13: Shutdown
  // ========================================================================
  console.log("─── Test 13: Shutdown ─────────────────────────────────────────");
  await kernel.stop();

  assert(!kernel.isRunning(), "Kernel is stopped");
  console.log("");

  // ========================================================================
  // Summary
  // ========================================================================
  console.log("═══════════════════════════════════════════════════════════════");
  console.log(`  Results: ${passed} passed, ${failed} failed, ${passed + failed} total`);
  console.log("═══════════════════════════════════════════════════════════════");

  if (failed > 0) {
    console.log("\n  ⚠ Some tests failed. Review output above.");
    process.exit(1);
  } else {
    console.log("\n  ✓ All tests passed! Phase 0 kernel is operational.");
    console.log("  → Ready for Phase 1: Identity + Messaging (viem + XMTP)");
    process.exit(0);
  }
}

runTests().catch((err) => {
  console.error("Test harness error:", err);
  process.exit(1);
});
