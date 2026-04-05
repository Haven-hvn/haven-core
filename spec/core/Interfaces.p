/**
 * Shared interface definitions for the Sovereign Agent kernel.
 *
 * Pure functions used across core machines. No side effects, no I/O.
 * Extension-specific logic does NOT belong here.
 */

// Generate a deterministic session key from channel + chat identifiers.
fun GenerateSessionKey(channel: ChannelName, chatId: string): SessionKey {
    return format("{0}:{1}", channel, chatId);
}

// Check if a message is a slash command.
fun IsSlashCommand(content: string): bool {
    return sizeof(content) > 0 && content[0] == '/';
}

// Extract the command name from a slash command string.
fun ParseCommand(content: string): string {
    var parts: seq[string];
    parts = split(content, " ");
    return parts[0];
}

// Sum token amounts for the same token symbol.
fun SumTokenAmounts(amounts: seq[TokenAmount], token: TokenSymbol): int {
    var total: int;
    total = 0;
    var i: int;
    i = 0;
    while (i < sizeof(amounts)) {
        if (amounts[i].token == token) {
            total = total + amounts[i].amount;
        }
        i = i + 1;
    }
    return total;
}

// Compute runway in days given total USD value and daily burn.
// Returns 0 if burn is zero or negative.
fun ComputeRunway(totalValueUsd: int, dailyBurnUsd: int): int {
    if (dailyBurnUsd <= 0) {
        return 9999;  // Effectively infinite if no burn
    }
    return totalValueUsd / dailyBurnUsd;
}

// Determine treasury state from runway days.
fun ComputeTreasuryState(runwayDays: int): TreasuryState {
    if (runwayDays > 30) {
        return FUNDED;
    } else if (runwayDays > 7) {
        return LOW;
    } else if (runwayDays > 0) {
        return CRITICAL;
    } else {
        return DEPLETED;
    }
}

// Check if a budget category has remaining allocation.
// spentPercentage is how much of total funds has been spent in this category.
fun IsBudgetAvailable(budget: BudgetAllocation, category: BudgetCategory, spentPercentage: int): bool {
    var limit: int;

    if (category == INFERENCE) {
        limit = budget.inference;
    } else if (category == TOOLS) {
        limit = budget.tools;
    } else if (category == INFRASTRUCTURE) {
        limit = budget.infrastructure;
    } else if (category == MESSAGING) {
        limit = budget.messaging;
    } else {
        limit = budget.reserve;
    }

    return spentPercentage < limit;
}

// Default budget allocation — balanced, with a 5% emergency reserve.
fun DefaultBudgetAllocation(): BudgetAllocation {
    return (
        inference = 40,
        tools = 15,
        infrastructure = 30,
        messaging = 10,
        reserve = 5
    );
}
