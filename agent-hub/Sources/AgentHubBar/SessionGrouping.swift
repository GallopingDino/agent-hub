import Foundation

enum GroupingMode: String, CaseIterable, Identifiable {
    case status
    case project
    case task

    var id: String { rawValue }

    var title: String {
        switch self {
        case .status: return "Status"
        case .project: return "Project"
        case .task: return "Task"
        }
    }

    var isReorderable: Bool { self != .status }
}

struct SessionGroup: Identifiable {
    static let forgottenId = "forgotten"

    let id: String
    let title: String
    let sessions: [PanelSession]
    let isReorderable: Bool

    var isForgotten: Bool { id == Self.forgottenId }
}

enum SessionGrouping {
    static func makeGroups(_ sessions: [PanelSession], mode: GroupingMode, savedOrder: [String]) -> [SessionGroup] {
        let active = sortByState(sessions.filter { $0.state != "stale" })
        let stale = sortByState(sessions.filter { $0.state == "stale" })

        var groups: [SessionGroup]
        switch mode {
        case .status:
            groups = [
                SessionGroup(id: "needs-you", title: "Needs you", sessions: active.filter(\.isNeedingUser), isReorderable: false),
                SessionGroup(id: "working", title: "Working", sessions: active.filter { $0.state == "working" }, isReorderable: false),
                SessionGroup(id: "idle", title: "Idle", sessions: active.filter { $0.state == "idle" }, isReorderable: false),
            ]
        case .project:
            groups = makeKeyedGroups(active, key: \.projectName, title: \.projectName, savedOrder: savedOrder)
        case .task:
            groups = makeKeyedGroups(active, key: taskKey, title: \.title, savedOrder: savedOrder)
        }

        groups.append(SessionGroup(id: SessionGroup.forgottenId, title: "Forgotten", sessions: stale, isReorderable: false))
        return groups.filter { $0.sessions.isEmpty == false }
    }

    static func taskKey(_ session: PanelSession) -> String {
        session.title.trimmingCharacters(in: .whitespaces).lowercased()
    }

    private static func makeKeyedGroups(_ sessions: [PanelSession], key: (PanelSession) -> String, title: (PanelSession) -> String, savedOrder: [String]) -> [SessionGroup] {
        var keys: [String] = []
        var sessionsByKey: [String: [PanelSession]] = [:]
        for session in sessions {
            let groupKey = key(session)
            if sessionsByKey[groupKey] == nil {
                keys.append(groupKey)
            }
            sessionsByKey[groupKey, default: []].append(session)
        }

        let savedIndex = Dictionary(savedOrder.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
        let ordered = keys.sorted { left, right in
            switch (savedIndex[left], savedIndex[right]) {
            case let (leftIndex?, rightIndex?): return leftIndex < rightIndex
            case (.some, nil): return true
            case (nil, .some): return false
            case (nil, nil): return (bestStateOrder(sessionsByKey[left]!), left) < (bestStateOrder(sessionsByKey[right]!), right)
            }
        }

        return ordered.map { groupKey in
            let members = sessionsByKey[groupKey]!
            return SessionGroup(id: groupKey, title: title(members[0]), sessions: members, isReorderable: true)
        }
    }

    private static func sortByState(_ sessions: [PanelSession]) -> [PanelSession] {
        sessions.sorted { ($0.stateOrder, $0.idleSeconds) < ($1.stateOrder, $1.idleSeconds) }
    }

    private static func bestStateOrder(_ sessions: [PanelSession]) -> Int {
        sessions.map(\.stateOrder).min() ?? Int.max
    }
}
