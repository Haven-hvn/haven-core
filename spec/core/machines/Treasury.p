/**
 * Machine: Treasury
 * Role: CORE — The economic survival engine.
 *
 * The agent exists only as long as it can pay for resources. Treasury tracks
 * balances across chains, enforces budget limits, records expenses, and
 * transitions through survival states (Funded → Low → Critical → Depleted).
 *
 * Design principle: Treasury is the gatekeeper. Every costly action in the
 * system must ask Treasury for authorization via eCostAuthorize before
 * proceeding. Treasury does NOT know how to query balances — that's an
 * extension concern. It receives balance updates via eBalanceUpdate events
 * from whatever chain-query extensions are registered.
 */

machine Treasury {
    // Current economic state.
    var currentState: TreasuryState;

    // Latest known balances.
    var balances: seq[ChainBalance];

    // Budget allocation percentages.
    var budget: BudgetAllocation;

    // Expense ledger (recent entries).
    var expenses: seq[Expense];

    // Running totals per category (in USD × 1e6).
    var spentByCategory: map[BudgetCategory, int];

    // Aggregate USD values.
    var totalValueUsd: int;
    var dailyBurnUsd: int;
    var runwayDays: int;

    start state Init {
        entry {
            currentState = FUNDED;
            balances = default(seq[ChainBalance]);
            budget = DefaultBudgetAllocation();
            expenses = default(seq[Expense]);
            spentByCategory = default(map[BudgetCategory, int]);
            totalValueUsd = 0;
            dailyBurnUsd = 0;
            runwayDays = 9999;

            print "Treasury: Initialized — awaiting balance data";
            goto Funded;
        }
    }

    // ========================================================================
    // FUNDED — Normal operation (runway > 30 days)
    // ========================================================================
    state Funded {
        entry {
            currentState = FUNDED;
            print format("Treasury: FUNDED — runway {0} days", runwayDays);
        }

        on eBalanceUpdate do (newBalances: seq[ChainBalance]) {
            UpdateBalances(newBalances);
        }

        on eCostAuthorize do (req: (requestId: string, estimate: CostEstimate, requestor: machine)) {
            // In funded mode, authorize if within budget category limits.
            var categorySpent: int;
            categorySpent = GetCategorySpentPercentage(req.estimate.category);

            if (IsBudgetAvailable(budget, req.estimate.category, categorySpent)) {
                send req.requestor, eCostAuthorized, (
                    requestId = req.requestId,
                    approved = true,
                    reason = "Authorized"
                );
            } else {
                send req.requestor, eCostAuthorized, (
                    requestId = req.requestId,
                    approved = false,
                    reason = format("Budget limit reached for category")
                );
            }
        }

        on eExpenseRecord do (expense: Expense) {
            RecordExpense(expense);
        }

        on eBalanceCheck do {
            // Extensions should respond with eBalanceUpdate.
            print "Treasury: Balance check requested";
        }

        on eTreasuryReportRequest do {
            send this, eTreasuryReport, BuildReport();
        }
    }

    // ========================================================================
    // LOW — Cost-conscious mode (runway 7-30 days)
    // ========================================================================
    state Low {
        entry {
            currentState = LOW;
            print format("Treasury: LOW — runway {0} days — entering cost-conscious mode", runwayDays);
        }

        on eBalanceUpdate do (newBalances: seq[ChainBalance]) {
            UpdateBalances(newBalances);
        }

        on eCostAuthorize do (req: (requestId: string, estimate: CostEstimate, requestor: machine)) {
            // In low mode, still authorize but with stricter budget enforcement.
            // Reserve budget is locked.
            if (req.estimate.category == RESERVE) {
                send req.requestor, eCostAuthorized, (
                    requestId = req.requestId,
                    approved = false,
                    reason = "Reserve locked in LOW state"
                );
                return;
            }

            var categorySpent: int;
            categorySpent = GetCategorySpentPercentage(req.estimate.category);

            if (IsBudgetAvailable(budget, req.estimate.category, categorySpent)) {
                send req.requestor, eCostAuthorized, (
                    requestId = req.requestId,
                    approved = true,
                    reason = "Authorized (cost-conscious)"
                );
            } else {
                send req.requestor, eCostAuthorized, (
                    requestId = req.requestId,
                    approved = false,
                    reason = "Budget exhausted in LOW state"
                );
            }
        }

        on eExpenseRecord do (expense: Expense) {
            RecordExpense(expense);
        }

        on eBalanceCheck do {
            print "Treasury: Balance check requested (LOW)";
        }

        on eTreasuryReportRequest do {
            send this, eTreasuryReport, BuildReport();
        }
    }

    // ========================================================================
    // CRITICAL — Survival mode (runway < 7 days)
    // ========================================================================
    state Critical {
        entry {
            currentState = CRITICAL;
            print format("Treasury: CRITICAL — runway {0} days — survival mode", runwayDays);
        }

        on eBalanceUpdate do (newBalances: seq[ChainBalance]) {
            UpdateBalances(newBalances);
        }

        on eCostAuthorize do (req: (requestId: string, estimate: CostEstimate, requestor: machine)) {
            // In critical mode, only infrastructure, storage, and minimal inference allowed.
            if (req.estimate.category == INFRASTRUCTURE) {
                // Infrastructure is life-or-death — always approve.
                send req.requestor, eCostAuthorized, (
                    requestId = req.requestId,
                    approved = true,
                    reason = "Infrastructure authorized (survival)"
                );
            } else if (req.estimate.category == STORAGE) {
                // Storage is survival-critical — without memory persistence,
                // the agent loses continuity on restart. Approve like infrastructure.
                send req.requestor, eCostAuthorized, (
                    requestId = req.requestId,
                    approved = true,
                    reason = "Storage authorized (survival — memory persistence)"
                );
            } else if (req.estimate.category == INFERENCE) {
                // Allow inference only if very cheap.
                var totalCostUsd: int;
                totalCostUsd = EstimateCostUsd(req.estimate);
                if (totalCostUsd < 100000) {  // Less than $0.10 (USD × 1e6)
                    send req.requestor, eCostAuthorized, (
                        requestId = req.requestId,
                        approved = true,
                        reason = "Minimal inference authorized (survival)"
                    );
                } else {
                    send req.requestor, eCostAuthorized, (
                        requestId = req.requestId,
                        approved = false,
                        reason = "Inference too expensive in CRITICAL state"
                    );
                }
            } else {
                // Everything else denied.
                send req.requestor, eCostAuthorized, (
                    requestId = req.requestId,
                    approved = false,
                    reason = "Denied in CRITICAL state"
                );
            }
        }

        on eExpenseRecord do (expense: Expense) {
            RecordExpense(expense);
        }

        on eBalanceCheck do {
            print "Treasury: Balance check requested (CRITICAL)";
        }

        on eTreasuryReportRequest do {
            send this, eTreasuryReport, BuildReport();
        }
    }

    // ========================================================================
    // DEPLETED — Agent cannot pay for next cycle
    // ========================================================================
    state Depleted {
        entry {
            currentState = DEPLETED;
            print "Treasury: DEPLETED — agent cannot sustain operation";
        }

        on eBalanceUpdate do (newBalances: seq[ChainBalance]) {
            // Even in depleted, listen for incoming funds (resurrection).
            UpdateBalances(newBalances);
        }

        on eCostAuthorize do (req: (requestId: string, estimate: CostEstimate, requestor: machine)) {
            // Deny everything.
            send req.requestor, eCostAuthorized, (
                requestId = req.requestId,
                approved = false,
                reason = "DEPLETED — no funds available"
            );
        }

        on eTreasuryReportRequest do {
            send this, eTreasuryReport, BuildReport();
        }
    }

    // ========================================================================
    // Shared helper functions
    // ========================================================================

    fun UpdateBalances(newBalances: seq[ChainBalance]) {
        balances = newBalances;

        // Recompute totals.
        totalValueUsd = 0;
        var i: int;
        i = 0;
        while (i < sizeof(balances)) {
            totalValueUsd = totalValueUsd + balances[i].usdEstimate;
            i = i + 1;
        }

        // Recompute runway.
        runwayDays = ComputeRunway(totalValueUsd, dailyBurnUsd);

        // Check for state transition.
        var newState: TreasuryState;
        newState = ComputeTreasuryState(runwayDays);

        if (newState != currentState) {
            var previous: TreasuryState;
            previous = currentState;

            send this, eTreasuryStateChanged, (previous = previous, current = newState);

            if (newState == FUNDED) {
                goto Funded;
            } else if (newState == LOW) {
                goto Low;
            } else if (newState == CRITICAL) {
                goto Critical;
            } else {
                goto Depleted;
            }
        }
    }

    fun RecordExpense(expense: Expense) {
        expenses += (expense);

        // Update category tracking.
        if (expense.category in spentByCategory) {
            spentByCategory[expense.category] =
                spentByCategory[expense.category] + expense.amount;
        } else {
            spentByCategory[expense.category] = expense.amount;
        }

        // Update daily burn estimate (simplified: rolling average).
        dailyBurnUsd = ComputeDailyBurn();

        // Recompute runway.
        runwayDays = ComputeRunway(totalValueUsd, dailyBurnUsd);

        var newState: TreasuryState;
        newState = ComputeTreasuryState(runwayDays);

        if (newState != currentState) {
            var previous: TreasuryState;
            previous = currentState;
            send this, eTreasuryStateChanged, (previous = previous, current = newState);

            if (newState == FUNDED) {
                goto Funded;
            } else if (newState == LOW) {
                goto Low;
            } else if (newState == CRITICAL) {
                goto Critical;
            } else {
                goto Depleted;
            }
        }
    }

    fun GetCategorySpentPercentage(category: BudgetCategory): int {
        if (totalValueUsd == 0) {
            return 100;  // No funds = fully spent
        }
        var spent: int;
        spent = 0;
        if (category in spentByCategory) {
            spent = spentByCategory[category];
        }
        return (spent * 100) / totalValueUsd;
    }

    fun EstimateCostUsd(estimate: CostEstimate): int {
        // Simplified: sum all amounts' USD equivalents.
        // In reality, would use price oracle data.
        var total: int;
        total = 0;
        var i: int;
        i = 0;
        while (i < sizeof(estimate.amounts)) {
            total = total + estimate.amounts[i].amount;
            i = i + 1;
        }
        return total;
    }

    fun ComputeDailyBurn(): int {
        // Simplified: sum recent expenses and divide by time window.
        var total: int;
        total = 0;
        var i: int;
        i = 0;
        while (i < sizeof(expenses)) {
            total = total + expenses[i].amount;
            i = i + 1;
        }
        // Assume expenses cover ~1 day for model checking purposes.
        return total;
    }

    fun BuildReport(): TreasuryReport {
        return (
            state = currentState,
            balances = balances,
            totalValueUsd = totalValueUsd,
            dailyBurnUsd = dailyBurnUsd,
            runwayDays = runwayDays,
            budget = budget,
            recentExpenses = expenses
        );
    }
}
