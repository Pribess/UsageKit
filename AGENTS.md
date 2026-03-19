# AGENTS.md

## Project Overview

UsageKit is a macOS 14+ menu bar app (SwiftUI) that tracks Claude (Anthropic) and Codex (OpenAI) usage. Two `MenuBarExtra` icons with dual progress bars showing remaining rate-limit capacity. Single Swift Package (`swift-tools-version: 5.9`), one dependency (Sparkle 2.8.1 for auto-updates).

## Build / Test / Run

```sh
make build            # swift build -c release
make app              # full .app bundle with codesign
make run              # kill existing → build → launch
make install          # build → copy to /Applications
make release          # build → verify → gh release create (auto-increment version)
make release-artifacts # build ZIP + DMG + verify
make clean            # remove all build artifacts

cd macos && swift test                          # all tests
cd macos && swift test --filter UsageServiceTests  # single test class
cd macos && swift test --filter testBackoff     # single test method (substring match)
```

All source lives under `macos/Sources/UsageKit/`, tests under `macos/Tests/UsageKitTests/`.

## Code Style

### Formatting
- 4-space indentation, K&R braces, ~120 char line target
- 1 blank line between logical sections, no trailing whitespace
- No SwiftLint — conventions enforced by review

### Imports
Order: Foundation → standard frameworks → third-party → local modules.
```swift
import Foundation
import Combine
import CryptoKit
import AppKit
```

### Naming
| Kind | Convention | Example |
|------|-----------|---------|
| Types | PascalCase | `UsageService`, `CodexUsageResponse` |
| Methods / vars | camelCase | `fetchUsage()`, `pollingMinutes` |
| Constants | camelCase | `defaultPollingMinutes`, `maxBackoffInterval` |
| File-level privates | camelCase | `private let barWidth: CGFloat = 24` |
| CodingKeys | snake_case strings | `case fiveHour = "five_hour"` |

### Access Control
- Default internal (implicit, never written)
- `private` for implementation details
- `private(set)` for read-only published properties
- `nonisolated` on static members of `@MainActor` classes
- No `public` — this is an executable, not a library

## Architecture Patterns

### Services (@MainActor + ObservableObject)
Every service class follows this shape:
```swift
@MainActor
class SomeService: ObservableObject {
    @Published var data: Model?
    @Published var lastError: String?
    @Published private(set) var pollingMinutes: Int

    private var timer: Timer?

    // nonisolated for static pure functions
    nonisolated static func backoffInterval(...) -> TimeInterval { ... }
}
```

### Views (@ObservedObject, @ViewBuilder)
```swift
struct SomeView: View {
    @ObservedObject var service: SomeService

    var body: some View { ... }

    @ViewBuilder
    private var conditionalSection: some View { ... }
}
```
- `@StateObject` only at the app entry point (`UsageKitApp`)
- `@ObservedObject` everywhere else
- `@AppStorage` for simple persisted UI state

### File Organization
1. Imports
2. Class/struct declaration with `@Published` properties
3. Non-published / private properties
4. Computed properties
5. `init()`
6. `// MARK:` sections — public methods first, then private

### Data Models (Codable structs)
```swift
struct SomeResponse: Codable {
    let fieldName: String?

    enum CodingKeys: String, CodingKey {
        case fieldName = "field_name"
    }

    var derived: Double { ... }
}
```
- All API fields optional where server may omit them
- Computed properties for derived/display values
- `snake_case` CodingKeys mapping to `camelCase` Swift properties

## Error Handling

- `async throws` + `do-catch` for network calls
- Custom enum for state machines (not `Result<T,E>`):
```swift
private enum RefreshResult {
    case success
    case permanentFailure   // 4xx → sign out
    case transientFailure   // network/5xx → retry later
}
```
- Set `lastError: String?` for UI display, never crash on API failures
- Distinguish transient vs permanent failures for token refresh

## Concurrency

- `@MainActor` on all `ObservableObject` classes
- `async/await` for all network calls
- `Task { @MainActor in ... }` to hop back from non-isolated closures
- `MainActor.assumeIsolated { }` in Timer/NotificationCenter callbacks
- `[weak self]` in closures to avoid retain cycles

## Testing

### Conventions
- Test class: `@MainActor final class SomeTests: XCTestCase`
- Test names: `testDescriptiveBehavior()` — no underscores
- Assertions: `XCTAssertEqual`, `XCTAssertTrue`, `XCTAssertNil`
- Async tests: `func testSomething() async throws { ... }`

### Mocking
Network mocking via `URLProtocol` subclass:
```swift
private final class MockURLProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override func startLoading() { /* call handler */ }
    override func stopLoading() {}
}
```
Services accept injected `URLSession` and `StoredCredentialsStore` for testability.

### Running Tests
```sh
cd macos && swift test                              # all 44 tests
cd macos && swift test --filter UsageModelTests      # one class
cd macos && swift test --filter testBackoff          # one method
```

## Things to Avoid

- `as any`, `@ts-ignore`, type suppressions
- `Result<T, E>` — use custom enums or throws
- Empty catch blocks
- `public` access control (unnecessary for executable target)
- Force unwraps except for compile-time-known URLs: `URL(string: "https://...")!`
- Modifying existing Claude flow when adding Codex features
- Adding dependencies without strong justification (currently only Sparkle)

## Dual-Service Architecture

Claude and Codex run as parallel, independent stacks:

| Layer | Claude | Codex |
|-------|--------|-------|
| Model | `UsageModel.swift` | `CodexUsageModel.swift` |
| Service | `UsageService.swift` | `CodexUsageService.swift` |
| Icon | `MenuBarIconRenderer.swift` | `CodexMenuBarIcon.swift` |
| Popover | `PopoverView.swift` | `CodexPopoverView.swift` |
| Credentials | `~/.config/usagekit/` | `~/.config/usagekit/codex/` |
| History | `~/.config/usagekit/history.json` | `~/.config/usagekit/codex/history.json` |

Shared: `UsageHistoryService`, `NotificationService`, `UsageChartView`, `SettingsView`, `WindowUtils`, `AppUpdater`.
