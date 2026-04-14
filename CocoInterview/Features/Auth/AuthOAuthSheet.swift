import SwiftUI
import WebKit

struct AuthOAuthSheet: View {
    @Environment(AuthStore.self) private var authStore
    @Environment(\.dismiss) private var dismiss

    let session: AuthWebSession

    @State private var isCompleting = false
    @State private var localErrorMessage: String?

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                OAuthAuthorizationWebView(
                    session: session,
                    onCallbackPayload: handleCallbackPayload,
                    onFailure: handleWebFailure
                )

                if let message = visibleErrorMessage {
                    Text(message)
                        .font(AppTheme.bodyFont(size: 12, weight: .semibold))
                        .foregroundStyle(Color(red: 0.68, green: 0.16, blue: 0.14))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(AppTheme.surface)
                        .overlay(
                            Rectangle()
                                .stroke(AppTheme.selectedChromeBorder, lineWidth: AppTheme.subtleBorderWidth)
                        )
                        .padding(16)
                }

                if isCompleting {
                    VStack(spacing: 10) {
                        ProgressView()
                            .tint(AppTheme.brandInk)

                        Text(AppStrings.current.authOAuthLoading)
                            .font(AppTheme.bodyFont(size: 13, weight: .semibold))
                            .foregroundStyle(AppTheme.brandInk)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                    .background(AppTheme.surface)
                    .overlay(
                        Rectangle()
                            .stroke(AppTheme.selectedChromeBorder, lineWidth: AppTheme.subtleBorderWidth)
                    )
                }
            }
            .background(AppTheme.background.ignoresSafeArea())
            .navigationTitle(AppStrings.current.authOAuthSheetTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(AppStrings.current.authOAuthCancelAction) {
                        authStore.cancelOAuth()
                        dismiss()
                    }
                    .disabled(isCompleting)
                }
            }
        }
        .interactiveDismissDisabled(isCompleting)
    }

    private var visibleErrorMessage: String? {
        localErrorMessage?.nilIfBlank ?? authStore.lastErrorMessage?.nilIfBlank
    }

    private func handleCallbackPayload(_ payload: Data) {
        guard !isCompleting else { return }
        isCompleting = true
        localErrorMessage = nil

        Task {
            let didAuthenticate = await authStore.completeOAuthCallbackPayload(payload)
            if didAuthenticate {
                dismiss()
            } else {
                isCompleting = false
                localErrorMessage = authStore.lastErrorMessage?.nilIfBlank
                    ?? AppStrings.current.authOAuthReadFailed
            }
        }
    }

    private func handleWebFailure(_ message: String) {
        guard !isCompleting else { return }
        localErrorMessage = message.nilIfBlank ?? AppStrings.current.authOAuthReadFailed
    }
}

private struct OAuthAuthorizationWebView: UIViewRepresentable {
    let session: AuthWebSession
    let onCallbackPayload: (Data) -> Void
    let onFailure: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(session: session, onCallbackPayload: onCallbackPayload, onFailure: onFailure)
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        webView.backgroundColor = UIColor(AppTheme.background)
        webView.isOpaque = false
        webView.scrollView.backgroundColor = UIColor(AppTheme.background)

        context.coordinator.loadInitialRequest(in: webView)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKNavigationDelegate {
        private let session: AuthWebSession
        private let onCallbackPayload: (Data) -> Void
        private let onFailure: (String) -> Void
        private var hasDeliveredPayload = false

        init(
            session: AuthWebSession,
            onCallbackPayload: @escaping (Data) -> Void,
            onFailure: @escaping (String) -> Void
        ) {
            self.session = session
            self.onCallbackPayload = onCallbackPayload
            self.onFailure = onFailure
        }

        func loadInitialRequest(in webView: WKWebView) {
            webView.load(URLRequest(url: session.authorizationURL))
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            guard shouldReadCallbackPayload(from: webView.url), !hasDeliveredPayload else {
                return
            }

            let script = "document.body ? document.body.innerText : document.documentElement.innerText"
            webView.evaluateJavaScript(script) { [weak self] result, error in
                guard let self else { return }

                if let error {
                    self.onFailure(error.localizedDescription)
                    return
                }

                guard let text = (result as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                      !text.isEmpty,
                      let payload = text.data(using: .utf8) else {
                    self.onFailure(AppStrings.current.authOAuthReadFailed)
                    return
                }

                self.hasDeliveredPayload = true
                self.onCallbackPayload(payload)
            }
        }

        func webView(
            _ webView: WKWebView,
            didFail navigation: WKNavigation!,
            withError error: Error
        ) {
            guard !hasDeliveredPayload else { return }
            onFailure(error.localizedDescription)
        }

        func webView(
            _ webView: WKWebView,
            didFailProvisionalNavigation navigation: WKNavigation!,
            withError error: Error
        ) {
            guard !hasDeliveredPayload else { return }
            onFailure(error.localizedDescription)
        }

        private func shouldReadCallbackPayload(from url: URL?) -> Bool {
            guard let url else { return false }

            let normalizedPath = url.path.lowercased()
            return normalizedPath.hasSuffix("/api/v1/auth/\(session.provider.rawValue)/callback")
        }
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
