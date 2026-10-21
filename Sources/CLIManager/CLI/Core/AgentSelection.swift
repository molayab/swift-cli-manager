import CLIManagerKit

func availableAgentIDs(for kind: ManagedItemKind) -> String {
    allAgentDescriptors.filter { $0.path(for: kind) != nil }.map(\.id).joined(separator: ", ")
}

/// Resolves agents to operate on for `kind` — detected agents when no filter is given, or the
/// filter's ids otherwise. Never prompts. Returns `nil` — and prints an appropriate message —
/// when there is nothing to do.
func resolveAgentTargets(_ filter: [String], for kind: ManagedItemKind) -> [AgentDescriptor]? {
    guard !filter.isEmpty else {
        let detected = AgentDescriptor.detected(for: kind)
        if detected.isEmpty {
            warn("No agents detected on this machine.")
            info("Use --agent <id>. Available: \(availableAgentIDs(for: kind))")
            return nil
        }
        return detected
    }
    let (resolved, unknown) = AgentDescriptor.resolve(ids: filter, for: kind)
    for id in unknown { warn("Unknown agent: \(id)") }
    return resolved
}

/// Resolves agents to operate on for `kind`, prompting interactively among detected agents
/// when no filter is given. Returns `nil` — and prints an appropriate message — when there is
/// nothing to do.
func selectAgentTargets(filter: [String], for kind: ManagedItemKind) -> [AgentDescriptor]? {
    if filter.isEmpty {
        let detected = AgentDescriptor.detected(for: kind)
        guard !detected.isEmpty else {
            warn("No agents detected on this machine.")
            info("Use --agent <id>. Available: \(availableAgentIDs(for: kind))")
            return nil
        }
        return selectInteractive(prompt: "Select agents", items: detected, display: \.name)
    }
    let (resolved, unknown) = AgentDescriptor.resolve(ids: filter, for: kind)
    for id in unknown { warn("Unknown agent: \(id)") }
    guard !resolved.isEmpty else {
        fail("No agents selected.")
        return nil
    }
    return resolved
}
