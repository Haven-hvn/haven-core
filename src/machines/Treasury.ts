/**
 * Machine: Treasury
 * Role: CORE — The economic survival engine.
 * 
 * Direct TypeScript translation of src/machines/Treasury.p
 * 
 * The agent exists only as long as it can pay for resources. Treasury tracks
 * balances across chains, enforces budget limits, records expenses, and
 * transitions through survival states (Funded → Low → Critical → Depleted).
 * 
 * States: Init → Funded ↔ Low ↔ Critical ↔ Depleted
 */

import { Machine, MachineRegistry } from "../machine.js";
import {
  type ChainBalance,
  type BudgetAllocation,
  type Expense,
  type CostEstimate,
  type TreasuryReport,
  TreasuryState,
  BudgetCategory,
} from "../types.js";
import {
  defaultBudgetAllocation,
  computeRunway,
  computeTreasuryState,
  isBudgetAvailable,
} from "../interfaces.js";

export class Treasury extends Machine {
  private treasuryState: TreasuryState = TreasuryState.FUNDED;
  private balances: ChainBalance[] = [];
  private budget: BudgetAllocation = defaultBudgetAllocation();
  private expenses: Expense[] = [];
  private spentByCategory = new Map<BudgetCategory, number>();
  private totalValueUsd = 0;
  private dailyBurnUsd = 0;
  private runwayDays = 9999;

  constructor(registry: MachineRegistry, id?: string) {
    super("Treasury", registry, id);
    this.defineStates();
  }

  async initialize(): Promise<void> {
    await this.init("Init");
  }

  private defineStates(): void {
    this.defineState("Init")
      .onEntry(() => {
        this.treasuryState = TreasuryState.FUNDED;
        this.log("Initialized — awaiting balance data");
        this.goto("Funded");
      });

    // FUNDED — Normal operation (runway > 30 days)
    this.defineState("Funded")
      .onEntry(() => {
        this.treasuryState = TreasuryState.FUNDED;
        this.log(`FUNDED — runway ${this.runwayDays} days`);
      })
      .on("eBalanceUpdate", (newBalances) => {
        this.updateBalances(newBalances);
      })
      .on("eCostAuthorize", (req) => {
        const categorySpent = this.getCategorySpentPercentage(req.estimate.category);
        if (isBudgetAvailable(this.budget, req.estimate.category, categorySpent)) {
          this.sendById(req.requestor, "eCostAuthorized", {
            requestId: req.requestId, approved: true, reason: "Authorized",
          });
        } else {
          this.sendById(req.requestor, "eCostAuthorized", {
            requestId: req.requestId, approved: false, reason: "Budget limit reached for category",
          });
        }
      })
      .on("eExpenseRecord", (expense) => { this.recordExpense(expense); })
      .on("eBalanceCheck", () => { this.log("Balance check requested"); })
      .on("eTreasuryReportRequest", () => {
        this.sendSelf("eTreasuryReport", this.buildReport());
      });

    // LOW — Cost-conscious mode (runway 7-30 days)
    this.defineState("Low")
      .onEntry(() => {
        this.treasuryState = TreasuryState.LOW;
        this.log(`LOW — runway ${this.runwayDays} days — entering cost-conscious mode`);
      })
      .on("eBalanceUpdate", (newBalances) => { this.updateBalances(newBalances); })
      .on("eCostAuthorize", (req) => {
        if (req.estimate.category === BudgetCategory.RESERVE) {
          this.sendById(req.requestor, "eCostAuthorized", {
            requestId: req.requestId, approved: false, reason: "Reserve locked in LOW state",
          });
          return;
        }
        const categorySpent = this.getCategorySpentPercentage(req.estimate.category);
        if (isBudgetAvailable(this.budget, req.estimate.category, categorySpent)) {
          this.sendById(req.requestor, "eCostAuthorized", {
            requestId: req.requestId, approved: true, reason: "Authorized (cost-conscious)",
          });
        } else {
          this.sendById(req.requestor, "eCostAuthorized", {
            requestId: req.requestId, approved: false, reason: "Budget exhausted in LOW state",
          });
        }
      })
      .on("eExpenseRecord", (expense) => { this.recordExpense(expense); })
      .on("eBalanceCheck", () => { this.log("Balance check requested (LOW)"); })
      .on("eTreasuryReportRequest", () => {
        this.sendSelf("eTreasuryReport", this.buildReport());
      });

    // CRITICAL — Survival mode (runway < 7 days)
    this.defineState("Critical")
      .onEntry(() => {
        this.treasuryState = TreasuryState.CRITICAL;
        this.log(`CRITICAL — runway ${this.runwayDays} days — survival mode`);
      })
      .on("eBalanceUpdate", (newBalances) => { this.updateBalances(newBalances); })
      .on("eCostAuthorize", (req) => {
        if (req.estimate.category === BudgetCategory.INFRASTRUCTURE) {
          this.sendById(req.requestor, "eCostAuthorized", {
            requestId: req.requestId, approved: true, reason: "Infrastructure authorized (survival)",
          });
        } else if (req.estimate.category === BudgetCategory.INFERENCE) {
          const totalCostUsd = this.estimateCostUsd(req.estimate);
          if (totalCostUsd < 100000) {
            this.sendById(req.requestor, "eCostAuthorized", {
              requestId: req.requestId, approved: true, reason: "Minimal inference authorized (survival)",
            });
          } else {
            this.sendById(req.requestor, "eCostAuthorized", {
              requestId: req.requestId, approved: false, reason: "Inference too expensive in CRITICAL state",
            });
          }
        } else {
          this.sendById(req.requestor, "eCostAuthorized", {
            requestId: req.requestId, approved: false, reason: "Denied in CRITICAL state",
          });
        }
      })
      .on("eExpenseRecord", (expense) => { this.recordExpense(expense); })
      .on("eBalanceCheck", () => { this.log("Balance check requested (CRITICAL)"); })
      .on("eTreasuryReportRequest", () => {
        this.sendSelf("eTreasuryReport", this.buildReport());
      });

    // DEPLETED — Agent cannot pay for next cycle
    this.defineState("Depleted")
      .onEntry(() => {
        this.treasuryState = TreasuryState.DEPLETED;
        this.log("DEPLETED — agent cannot sustain operation");
      })
      .on("eBalanceUpdate", (newBalances) => { this.updateBalances(newBalances); })
      .on("eCostAuthorize", (req) => {
        this.sendById(req.requestor, "eCostAuthorized", {
          requestId: req.requestId, approved: false, reason: "DEPLETED — no funds available",
        });
      })
      .on("eTreasuryReportRequest", () => {
        this.sendSelf("eTreasuryReport", this.buildReport());
      });
  }

  // Public accessors
  getTreasuryState(): TreasuryState { return this.treasuryState; }
  getReport(): TreasuryReport { return this.buildReport(); }

  // Helpers
  private updateBalances(newBalances: ChainBalance[]): void {
    this.balances = newBalances;
    this.totalValueUsd = 0;
    for (const b of this.balances) this.totalValueUsd += b.usdEstimate;
    this.runwayDays = computeRunway(this.totalValueUsd, this.dailyBurnUsd);
    const newState = computeTreasuryState(this.runwayDays);
    if (newState !== this.treasuryState) {
      const previous = this.treasuryState;
      this.sendSelf("eTreasuryStateChanged", { previous, current: newState });
      this.transitionToState(newState);
    }
  }

  private recordExpense(expense: Expense): void {
    this.expenses.push(expense);
    const current = this.spentByCategory.get(expense.category) || 0;
    this.spentByCategory.set(expense.category, current + expense.amount);
    this.dailyBurnUsd = this.computeDailyBurn();
    this.runwayDays = computeRunway(this.totalValueUsd, this.dailyBurnUsd);
    const newState = computeTreasuryState(this.runwayDays);
    if (newState !== this.treasuryState) {
      const previous = this.treasuryState;
      this.sendSelf("eTreasuryStateChanged", { previous, current: newState });
      this.transitionToState(newState);
    }
  }

  private transitionToState(newState: TreasuryState): void {
    switch (newState) {
      case TreasuryState.FUNDED: this.goto("Funded"); break;
      case TreasuryState.LOW: this.goto("Low"); break;
      case TreasuryState.CRITICAL: this.goto("Critical"); break;
      case TreasuryState.DEPLETED: this.goto("Depleted"); break;
    }
  }

  private getCategorySpentPercentage(category: BudgetCategory): number {
    if (this.totalValueUsd === 0) return 100;
    const spent = this.spentByCategory.get(category) || 0;
    return Math.floor((spent * 100) / this.totalValueUsd);
  }

  private estimateCostUsd(estimate: CostEstimate): number {
    let total = 0;
    for (const a of estimate.amounts) total += a.amount;
    return total;
  }

  private computeDailyBurn(): number {
    let total = 0;
    for (const e of this.expenses) total += e.amount;
    return total;
  }

  private buildReport(): TreasuryReport {
    return {
      state: this.treasuryState,
      balances: [...this.balances],
      totalValueUsd: this.totalValueUsd,
      dailyBurnUsd: this.dailyBurnUsd,
      runwayDays: this.runwayDays,
      budget: { ...this.budget },
      recentExpenses: [...this.expenses],
    };
  }
}
