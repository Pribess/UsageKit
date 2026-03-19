import Foundation
import Combine
import CryptoKit
import AppKit
import Network

@MainActor
class CodexUsageService: ObservableObject {
    @Published var usage: CodexUsageResponse?
    @Published var lastError: String?
    @Published var lastUpdated: Date?
    @Published var isAuthenticated = false
    @Published var isAwaitingCode = false
    @Published var accountEmail: String?
    @Published private(set) var pollingMinutes: Int

    var historyService: UsageHistoryService?
    var notificationService: NotificationService?

    private var timer: Timer?
    private let session: URLSession
    private let usageEndpoint: URL
    private let tokenEndpoint: URL
    private let credentialsStore: StoredCredentialsStore
    private var currentInterval: TimeInterval
    private var refreshTask: Task<RefreshResult, Never>?
    private var callbackListener: NWListener?
    private var callbackContinuation: CheckedContinuation<(code: String, state: String?), Error>?
    private let callbackQueue = DispatchQueue(label: "usagekit.codex.oauth")
    private var codeVerifier: String?
    private var oauthState: String?
    private var accountID: String?

    private enum RefreshResult {
        case success
        case permanentFailure
        case transientFailure
    }

    static let defaultPollingMinutes = 30
    static let pollingOptions = [5, 15, 30, 60]
    nonisolated static let maxBackoffInterval: TimeInterval = 60 * 60
    nonisolated private static let authorizeEndpoint = URL(string: "https://auth.openai.com/oauth/authorize")!
    nonisolated private static let defaultTokenEndpoint = URL(string: "https://auth.openai.com/oauth/token")!
    nonisolated private static let defaultUsageEndpoint = URL(string: "https://chatgpt.com/backend-api/wham/usage")!
    nonisolated private static let defaultRedirectURI = "http://localhost:1455/auth/callback"
    nonisolated private static let defaultScopes = "openid profile email offline_access"

    private let clientId = "app_EMoamEEZ73f0CkXaXp7hrann"
    private let redirectUri: String

    var pctPrimary: Double? { usage?.rateLimit?.primaryWindow?.pct }
    var pctSecondary: Double? { usage?.rateLimit?.secondaryWindow?.pct }
    var primaryLabel: String { usage?.primaryWindowLabel ?? "P" }
    var secondaryLabel: String { usage?.secondaryWindowLabel ?? "S" }

    private var baseInterval: TimeInterval { TimeInterval(pollingMinutes * 60) }

    init(
        session: URLSession = .shared,
        usageEndpoint: URL = CodexUsageService.defaultUsageEndpoint,
        tokenEndpoint: URL = CodexUsageService.defaultTokenEndpoint,
        redirectUri: String = CodexUsageService.defaultRedirectURI,
        credentialsStore: StoredCredentialsStore = StoredCredentialsStore(
            directoryURL: FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".config/usagekit/codex", isDirectory: true)
        )
    ) {
        self.session = session
        self.usageEndpoint = usageEndpoint
        self.tokenEndpoint = tokenEndpoint
        self.redirectUri = redirectUri
        self.credentialsStore = credentialsStore
        let stored = UserDefaults.standard.integer(forKey: "codexPollingMinutes")
        let minutes = Self.pollingOptions.contains(stored) ? stored : Self.defaultPollingMinutes
        self.pollingMinutes = minutes
        self.currentInterval = TimeInterval(minutes * 60)

        let credentials = loadCredentials()
        self.isAuthenticated = credentials != nil
        self.accountEmail = credentials.flatMap { Self.jwtClaim(named: "email", from: $0.accessToken) as? String }
        self.accountID = credentials.flatMap { Self.extractAccountID(from: $0.accessToken) }
    }

    func updatePollingInterval(_ minutes: Int) {
        pollingMinutes = minutes
        UserDefaults.standard.set(minutes, forKey: "codexPollingMinutes")
        currentInterval = TimeInterval(minutes * 60)
        if isAuthenticated {
            scheduleTimer()
            Task { await fetchUsage() }
        }
    }

    func startPolling() {
        guard isAuthenticated else { return }
        Task { await fetchUsage() }
        scheduleTimer()
    }

    func startOAuthFlow() {
        Task { await beginOAuthFlow() }
    }

    func fetchUsage() async {
        guard loadCredentials() != nil else {
            lastError = "Not signed in"
            isAuthenticated = false
            return
        }

        do {
            guard let result = try await sendAuthorizedRequest(to: usageEndpoint) else {
                return
            }
            let (data, http) = result
            if http.statusCode == 429 {
                let retryAfter = http.value(forHTTPHeaderField: "Retry-After")
                    .flatMap(Double.init) ?? currentInterval
                currentInterval = Self.backoffInterval(
                    retryAfter: retryAfter,
                    currentInterval: currentInterval
                )
                lastError = "Rate limited — backing off to \(Int(currentInterval))s"
                scheduleTimer()
                return
            }
            guard http.statusCode == 200 else {
                let body = String(data: data, encoding: .utf8) ?? ""
                lastError = body.isEmpty ? "HTTP \(http.statusCode)" : "HTTP \(http.statusCode): \(body)"
                return
            }

            let decoded = try JSONDecoder().decode(CodexUsageResponse.self, from: data)
            usage = decoded
            lastError = nil
            lastUpdated = Date()
            historyService?.recordDataPoint(pct5h: pctPrimary ?? 0, pct7d: pctSecondary ?? 0)
            notificationService?.checkAndNotify(pct5h: pctPrimary ?? 0, pct7d: pctSecondary ?? 0, pctExtra: 0)
            if currentInterval != baseInterval {
                currentInterval = baseInterval
                scheduleTimer()
            }
        } catch {
            lastError = error.localizedDescription
        }
    }

    func signOut() {
        stopCallbackServer()
        deleteCredentials()
        isAuthenticated = false
        isAwaitingCode = false
        usage = nil
        lastUpdated = nil
        accountEmail = nil
        accountID = nil
        codeVerifier = nil
        oauthState = nil
        timer?.invalidate()
        timer = nil
        refreshTask?.cancel()
        refreshTask = nil
        lastError = nil
    }

    private func beginOAuthFlow() async {
        stopCallbackServer()
        lastError = nil
        isAwaitingCode = true

        let verifier = generateCodeVerifier()
        let challenge = generateCodeChallenge(from: verifier)
        let state = generateCodeVerifier()

        codeVerifier = verifier
        oauthState = state

        guard let authorizationURL = authorizationURL(challenge: challenge, state: state) else {
            lastError = "Could not create authorization URL"
            isAwaitingCode = false
            return
        }

        do {
            let callback = try await waitForAuthorizationCode(using: authorizationURL)
            guard callback.state == oauthState else {
                lastError = "OAuth state mismatch — try again"
                isAwaitingCode = false
                codeVerifier = nil
                oauthState = nil
                return
            }

            try await exchangeAuthorizationCode(callback.code)
            isAuthenticated = true
            isAwaitingCode = false
            lastError = nil
            codeVerifier = nil
            oauthState = nil
            startPolling()
        } catch {
            isAwaitingCode = false
            codeVerifier = nil
            oauthState = nil
            if (error as? CancellationError) == nil {
                lastError = error.localizedDescription
            }
        }
    }

    private func authorizationURL(challenge: String, state: String) -> URL? {
        var components = URLComponents(url: Self.authorizeEndpoint, resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "client_id", value: clientId),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: redirectUri),
            URLQueryItem(name: "scope", value: Self.defaultScopes),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "codex_cli_simplified_flow", value: "true")
        ]
        return components?.url
    }

    private func waitForAuthorizationCode(using authorizationURL: URL) async throws -> (code: String, state: String?) {
        let listener = try NWListener(using: .tcp, on: NWEndpoint.Port(integerLiteral: 1455))
        callbackListener = listener

        return try await withCheckedThrowingContinuation { continuation in
            callbackContinuation = continuation

            listener.stateUpdateHandler = { [weak self] state in
                guard let self else { return }

                switch state {
                case .ready:
                    let opened = NSWorkspace.shared.open(authorizationURL)
                    if !opened {
                        Task { @MainActor in
                            self.finishCallback(with: .failure(CodexOAuthError.browserOpenFailed))
                        }
                    }
                case .failed(let error):
                    Task { @MainActor in
                        self.finishCallback(with: .failure(error))
                    }
                case .cancelled:
                    Task { @MainActor in
                        self.finishCallback(with: .failure(CodexOAuthError.callbackCancelled))
                    }
                default:
                    break
                }
            }

            listener.newConnectionHandler = { [weak self] connection in
                Task { @MainActor in
                    self?.handleCallbackConnection(connection)
                }
            }

            listener.start(queue: callbackQueue)
        }
    }

    private func handleCallbackConnection(_ connection: NWConnection) {
        connection.start(queue: callbackQueue)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] data, _, _, error in
            guard let self else {
                connection.cancel()
                return
            }

            if let error {
                Task { @MainActor in
                    self.finishCallback(with: .failure(error))
                }
                connection.cancel()
                return
            }

            guard let data,
                  let request = String(data: data, encoding: .utf8) else {
                Self.sendHTTPResponse(
                    to: connection,
                    status: "400 Bad Request",
                    body: "Invalid request."
                )
                Task { @MainActor in
                    self.finishCallback(with: .failure(CodexOAuthError.invalidCallbackRequest))
                }
                return
            }

            let result = Self.parseAuthorizationCallback(from: request)
            switch result {
            case .success(let callback):
                Self.sendHTTPResponse(
                    to: connection,
                    status: "200 OK",
                    body: "Codex sign-in complete. You can close this tab and return to UsageKit."
                )
                Task { @MainActor in
                    self.finishCallback(with: .success(callback))
                }
            case .failure(let error):
                Self.sendHTTPResponse(
                    to: connection,
                    status: "400 Bad Request",
                    body: error.localizedDescription
                )
                Task { @MainActor in
                    self.finishCallback(with: .failure(error))
                }
            }
        }
    }

    nonisolated private static func sendHTTPResponse(to connection: NWConnection, status: String, body: String) {
        let html = """
        <html><body style=\"font-family: -apple-system; padding: 24px;\"><p>\(body)</p></body></html>
        """
        let response = "HTTP/1.1 \(status)\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: \(html.utf8.count)\r\nConnection: close\r\n\r\n\(html)"
        connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    private func finishCallback(with result: Result<(code: String, state: String?), Error>) {
        guard callbackContinuation != nil else { return }
        callbackContinuation?.resume(with: result)
        callbackContinuation = nil
        stopCallbackServer()
    }

    private func stopCallbackServer() {
        callbackListener?.stateUpdateHandler = nil
        callbackListener?.newConnectionHandler = nil
        callbackListener?.cancel()
        callbackListener = nil
    }

    private func exchangeAuthorizationCode(_ code: String) async throws {
        guard let verifier = codeVerifier else {
            throw CodexOAuthError.missingVerifier
        }

        var request = URLRequest(url: tokenEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: String] = [
            "grant_type": "authorization_code",
            "code": code,
            "client_id": clientId,
            "redirect_uri": redirectUri,
            "code_verifier": verifier
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        guard http.statusCode == 200 else {
            let bodyString = String(data: data, encoding: .utf8) ?? ""
            throw CodexOAuthError.tokenExchangeFailed(http.statusCode, bodyString)
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let credentials = credentials(from: json) else {
            throw CodexOAuthError.invalidTokenPayload
        }

        try saveCredentials(credentials)
        isAuthenticated = true
        accountID = Self.extractAccountID(from: credentials.accessToken)
        accountEmail = Self.jwtClaim(named: "email", from: credentials.accessToken) as? String
    }

    private func scheduleTimer() {
        timer?.invalidate()
        let timer = Timer(timeInterval: currentInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.isAuthenticated else { return }
                Task { await self.fetchUsage() }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    nonisolated static func backoffInterval(
        retryAfter: TimeInterval?,
        currentInterval: TimeInterval
    ) -> TimeInterval {
        min(max(retryAfter ?? currentInterval, currentInterval * 2), maxBackoffInterval)
    }

    private func generateCodeVerifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64URLEncoded()
    }

    private func generateCodeChallenge(from verifier: String) -> String {
        let hash = SHA256.hash(data: Data(verifier.utf8))
        return Data(hash).base64URLEncoded()
    }

    private func saveCredentials(_ credentials: StoredCredentials) throws {
        try credentialsStore.save(credentials)
    }

    private func loadCredentials() -> StoredCredentials? {
        credentialsStore.load(defaultScopes: Self.defaultScopes.split(separator: " ").map(String.init))
    }

    private func deleteCredentials() {
        credentialsStore.delete()
    }

    private func sendAuthorizedRequest(
        to url: URL,
        expireSessionOnAuthFailure: Bool = true
    ) async throws -> (Data, HTTPURLResponse)? {
        guard let initialCredentials = loadCredentials() else {
            lastError = "Not signed in"
            isAuthenticated = false
            return nil
        }

        if initialCredentials.needsRefresh() {
            let refreshResult = await refreshCredentials(force: true)
            if refreshResult != .success, initialCredentials.isExpired() {
                switch refreshResult {
                case .permanentFailure:
                    if expireSessionOnAuthFailure {
                        expireSession()
                    }
                case .transientFailure:
                    lastError = "Token refresh failed — will retry"
                case .success:
                    break
                }
                return nil
            }
        }

        let activeCredentials = loadCredentials() ?? initialCredentials

        var result = try await performAuthorizedRequest(
            token: activeCredentials.accessToken,
            url: url
        )

        if result.1.statusCode != 401 {
            return result
        }

        let refreshResult = await refreshCredentials(force: true)
        switch refreshResult {
        case .success:
            guard let refreshedCredentials = loadCredentials() else {
                if expireSessionOnAuthFailure {
                    expireSession()
                }
                return nil
            }

            result = try await performAuthorizedRequest(
                token: refreshedCredentials.accessToken,
                url: url
            )

            if result.1.statusCode == 401 {
                if expireSessionOnAuthFailure {
                    expireSession()
                }
                return nil
            }

            return result

        case .permanentFailure:
            if expireSessionOnAuthFailure {
                expireSession()
            }
            return nil

        case .transientFailure:
            lastError = "Token refresh failed — will retry"
            return nil
        }
    }

    private func performAuthorizedRequest(
        token: String,
        url: URL
    ) async throws -> (Data, HTTPURLResponse) {
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let accountID, !accountID.isEmpty {
            request.setValue(accountID, forHTTPHeaderField: "ChatGPT-Account-Id")
        }

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        return (data, http)
    }

    private func refreshCredentials(force: Bool) async -> RefreshResult {
        if let refreshTask {
            return await refreshTask.value
        }

        let task = Task { [weak self] in
            guard let self else { return RefreshResult.permanentFailure }
            return await self.performRefresh(force: force)
        }
        refreshTask = task
        let result = await task.value
        refreshTask = nil
        return result
    }

    private func performRefresh(force: Bool) async -> RefreshResult {
        guard let currentCredentials = loadCredentials(),
              let refreshToken = currentCredentials.refreshToken,
              !refreshToken.isEmpty else {
            return .permanentFailure
        }

        if !force, !currentCredentials.needsRefresh() {
            return .success
        }

        var request = URLRequest(url: tokenEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        var body: [String: String] = [
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "client_id": clientId
        ]
        if !currentCredentials.scopes.isEmpty {
            body["scope"] = currentCredentials.scopes.joined(separator: " ")
        }
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        let data: Data
        let http: HTTPURLResponse
        do {
            let (responseData, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                return .transientFailure
            }
            data = responseData
            http = httpResponse
        } catch {
            return .transientFailure
        }

        guard http.statusCode == 200 else {
            if http.statusCode >= 400, http.statusCode < 500 {
                return .permanentFailure
            }
            return .transientFailure
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let updatedCredentials = credentials(from: json, fallback: currentCredentials) else {
            return .transientFailure
        }

        do {
            try saveCredentials(updatedCredentials)
        } catch {
            try? await Task.sleep(nanoseconds: 100_000_000)
            do {
                try saveCredentials(updatedCredentials)
            } catch {
                return .transientFailure
            }
        }

        isAuthenticated = true
        accountID = Self.extractAccountID(from: updatedCredentials.accessToken)
        accountEmail = Self.jwtClaim(named: "email", from: updatedCredentials.accessToken) as? String
        return .success
    }

    private func credentials(
        from json: [String: Any],
        fallback: StoredCredentials? = nil
    ) -> StoredCredentials? {
        guard let accessToken = json["access_token"] as? String, !accessToken.isEmpty else {
            return nil
        }

        let scopeString = json["scope"] as? String
        let scopes = scopeString?
            .split(whereSeparator: \.isWhitespace)
            .map(String.init) ?? fallback?.scopes ?? Self.defaultScopes.split(separator: " ").map(String.init)

        return StoredCredentials(
            accessToken: accessToken,
            refreshToken: (json["refresh_token"] as? String) ?? fallback?.refreshToken,
            expiresAt: Self.expirationDate(from: json["expires_in"]) ?? fallback?.expiresAt,
            scopes: scopes
        )
    }

    private static func expirationDate(from value: Any?) -> Date? {
        let seconds: TimeInterval?
        switch value {
        case let number as NSNumber:
            seconds = number.doubleValue
        case let number as Double:
            seconds = number
        case let number as Int:
            seconds = TimeInterval(number)
        case let string as String:
            seconds = TimeInterval(string)
        default:
            seconds = nil
        }

        guard let seconds else { return nil }
        return Date().addingTimeInterval(seconds)
    }

    private func expireSession() {
        deleteCredentials()
        isAuthenticated = false
        isAwaitingCode = false
        usage = nil
        lastUpdated = nil
        accountEmail = nil
        accountID = nil
        timer?.invalidate()
        timer = nil
        refreshTask?.cancel()
        refreshTask = nil
        lastError = "Session expired — please sign in again"
    }

    nonisolated private static func parseAuthorizationCallback(from request: String) -> Result<(code: String, state: String?), Error> {
        guard let requestLine = request.components(separatedBy: "\r\n").first,
              !requestLine.isEmpty else {
            return .failure(CodexOAuthError.invalidCallbackRequest)
        }

        let parts = requestLine.split(separator: " ")
        guard parts.count >= 2 else {
            return .failure(CodexOAuthError.invalidCallbackRequest)
        }

        let path = String(parts[1])
        guard let components = URLComponents(string: "http://localhost:1455\(path)") else {
            return .failure(CodexOAuthError.invalidCallbackRequest)
        }
        guard components.path == "/auth/callback" else {
            return .failure(CodexOAuthError.invalidCallbackRequest)
        }

        let items = components.queryItems ?? []
        if let error = items.first(where: { $0.name == "error" })?.value {
            return .failure(CodexOAuthError.authorizationDenied(error))
        }

        guard let code = items.first(where: { $0.name == "code" })?.value,
              !code.isEmpty else {
            return .failure(CodexOAuthError.missingAuthorizationCode)
        }

        let state = items.first(where: { $0.name == "state" })?.value
        return .success((code: code, state: state))
    }

    private static func extractAccountID(from accessToken: String) -> String? {
        guard let authClaim = jwtClaim(named: "https://api.openai.com/auth", from: accessToken) as? [String: Any] else {
            return nil
        }

        if let accountID = authClaim["chatgpt_account_id"] as? String, !accountID.isEmpty {
            return accountID
        }
        if let accountID = authClaim["account_id"] as? String, !accountID.isEmpty {
            return accountID
        }
        return nil
    }

    private static func jwtClaim(named name: String, from accessToken: String) -> Any? {
        let parts = accessToken.split(separator: ".")
        guard parts.count >= 2,
              let payload = decodeBase64URL(String(parts[1])),
              let json = try? JSONSerialization.jsonObject(with: payload) as? [String: Any] else {
            return nil
        }
        return json[name]
    }

    private static func decodeBase64URL(_ string: String) -> Data? {
        var base64 = string
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")

        let padding = 4 - base64.count % 4
        if padding < 4 {
            base64 += String(repeating: "=", count: padding)
        }

        return Data(base64Encoded: base64)
    }
}

private enum CodexOAuthError: LocalizedError {
    case browserOpenFailed
    case callbackCancelled
    case invalidCallbackRequest
    case missingAuthorizationCode
    case missingVerifier
    case invalidTokenPayload
    case authorizationDenied(String)
    case tokenExchangeFailed(Int, String)

    var errorDescription: String? {
        switch self {
        case .browserOpenFailed:
            return "Could not open the browser for Codex sign-in"
        case .callbackCancelled:
            return "Codex sign-in was cancelled"
        case .invalidCallbackRequest:
            return "Invalid OAuth callback"
        case .missingAuthorizationCode:
            return "OAuth callback was missing a code"
        case .missingVerifier:
            return "No pending OAuth verifier"
        case .invalidTokenPayload:
            return "Could not parse token response"
        case .authorizationDenied(let error):
            return "Authorization failed: \(error)"
        case .tokenExchangeFailed(let status, let body):
            if body.isEmpty {
                return "Token exchange failed: HTTP \(status)"
            }
            return "Token exchange failed: HTTP \(status) \(body)"
        }
    }
}
