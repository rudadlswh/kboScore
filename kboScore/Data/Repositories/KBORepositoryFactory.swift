//
//  KBORepositoryFactory.swift
//  kboScore
//
//  Created by Codex on 5/14/26.
//

import Foundation

struct AppRepositoryBundle {
    let repository: any KBORepository
    let runtimeState: RepositoryRuntimeState?
}

struct AppRepositoryConfiguration: Sendable {
    let supabaseConfiguration: SupabaseConfiguration?

    nonisolated init(
        backendBaseURL: URL? = nil,
        supabaseConfiguration: SupabaseConfiguration?
    ) {
        _ = backendBaseURL
        self.supabaseConfiguration = supabaseConfiguration
    }

    nonisolated static func fromEnvironment(
        processInfo: ProcessInfo = .processInfo,
        bundle: Bundle = .main
    ) -> AppRepositoryConfiguration {
        let supabaseEnvironmentValue = processInfo.environment["SUPABASE_URL"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        let supabaseInfoDictionaryValue = (bundle.object(forInfoDictionaryKey: "SupabaseURL") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let supabaseKeyEnvironmentValue = processInfo.environment["SUPABASE_PUBLISHABLE_KEY"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        let supabaseKeyInfoDictionaryValue = (bundle.object(forInfoDictionaryKey: "SupabasePublishableKey") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let supabaseConfiguration = firstValidSupabaseConfiguration(
            candidates: [
                (url: supabaseEnvironmentValue, publishableKey: supabaseKeyEnvironmentValue),
                (url: supabaseInfoDictionaryValue, publishableKey: supabaseKeyInfoDictionaryValue)
            ]
        )
#if DEBUG
        print("[SupabaseConfig] environmentURLPresent=\(hasValue(supabaseEnvironmentValue))")
        print("[SupabaseConfig] plistURLPresent=\(hasValue(supabaseInfoDictionaryValue))")
        print("[SupabaseConfig] environmentKeyPresent=\(hasValue(supabaseKeyEnvironmentValue))")
        print("[SupabaseConfig] plistKeyPresent=\(hasValue(supabaseKeyInfoDictionaryValue))")
        print("[SupabaseConfig] finalRuntimeHost=\(debugHostValue(supabaseConfiguration))")
#endif
        return AppRepositoryConfiguration(
            supabaseConfiguration: supabaseConfiguration
        )
    }

    private nonisolated static func backendURL(from rawValue: String?) -> URL? {
        guard let rawValue,
              let url = URL(string: rawValue),
              let scheme = url.scheme?.lowercased(),
              let host = url.host?.lowercased(),
              host.isEmpty == false else {
            return nil
        }
#if DEBUG
        guard ["http", "https"].contains(scheme) else {
            return nil
        }
#else
        guard scheme == "https",
              releaseApprovedHosts.contains(host) else {
            return nil
        }
#endif
        return url
    }

    private nonisolated static func firstValidSupabaseConfiguration(
        candidates: [(url: String?, publishableKey: String?)]
    ) -> SupabaseConfiguration? {
        for candidate in candidates {
            if let configuration = supabaseConfiguration(
                urlRawValue: candidate.url,
                publishableKeyRawValue: candidate.publishableKey
            ) {
                return configuration
            }
        }
        return nil
    }

#if !DEBUG
    private nonisolated static let releaseApprovedHosts: Set<String> = [
        "pbfancqzynkialupleys.supabase.co"
    ]
#endif

    private nonisolated static func supabaseConfiguration(
        urlRawValue: String?,
        publishableKeyRawValue: String?
    ) -> SupabaseConfiguration? {
        guard let url = backendURL(from: urlRawValue),
              let publishableKey = publishableKeyRawValue?.trimmingCharacters(in: .whitespacesAndNewlines),
              publishableKey.isEmpty == false else {
            return nil
        }
        return SupabaseConfiguration(url: url, publishableKey: publishableKey)
    }

#if DEBUG
    private nonisolated static func hasValue(_ value: String?) -> Bool {
        guard let value else {
            return false
        }
        return value.isEmpty == false
    }

    private nonisolated static func debugHostValue(_ configuration: SupabaseConfiguration?) -> String {
        configuration?.url.host ?? "<none>"
    }
#endif
}

enum KBORepositoryFactory {
    static func makeAppRepository() -> any KBORepository {
        makeAppRepositoryBundle().repository
    }

    static func makeAppRepositoryBundle(
        configuration: AppRepositoryConfiguration = .fromEnvironment()
    ) -> AppRepositoryBundle {
        let runtimeState = RepositoryRuntimeState(
            activeSource: configuration.supabaseConfiguration == nil ? .mock : .supabase,
            baseURL: configuration.supabaseConfiguration?.url.absoluteString,
            deliverySource: configuration.supabaseConfiguration == nil ? .mock : .supabase,
            bootstrapRefreshSnapshot: BootstrapRefreshDebugSnapshot(
                isEnabled: false,
                etag: nil,
                lastFetchAt: nil,
                lastWriteAt: nil,
                lastResult: .disabled
            )
        )
        let repository = BundledJSONKBORepository(
            runtimeState: runtimeState,
            runtimeSource: configuration.supabaseConfiguration == nil ? .mock : .mockFallback,
            runtimeDelivery: configuration.supabaseConfiguration == nil ? .mock : .mockFallback
        )
        let wrappedRepository = makeSupabaseWrappedRepository(
            baseRepository: repository,
            configuration: configuration,
            runtimeState: runtimeState
        )
        let startupOptimizedRepository: any KBORepository
        if configuration.supabaseConfiguration != nil {
            let cached = CachedKBORepository(
                base: AnyKBORepository(wrappedRepository),
                configuration: .supabaseStartup,
                runtimeState: runtimeState
            )
            startupOptimizedRepository = AnyKBORepository(cached)
        } else {
            startupOptimizedRepository = wrappedRepository
        }

        return AppRepositoryBundle(
            repository: startupOptimizedRepository,
            runtimeState: runtimeState
        )
    }

    private static func makeSupabaseWrappedRepository<Base: KBORepository>(
        baseRepository: Base,
        configuration: AppRepositoryConfiguration,
        runtimeState: RepositoryRuntimeState?
    ) -> any KBORepository {
        guard let supabaseConfiguration = configuration.supabaseConfiguration else {
            return baseRepository
        }

        #if canImport(Supabase)
        #if DEBUG
        print("[SupabaseConfig] supabase-swift linked=true")
        print("[SupabaseKBO] enabled=true host=\(supabaseConfiguration.url.host ?? "<none>")")
        #endif
        let repository = SupabaseBackedKBORepository(
            base: baseRepository,
            source: SupabaseKBORepository(configuration: supabaseConfiguration),
            runtimeState: runtimeState
        )
        return AnyKBORepository(repository)
        #else
        #if DEBUG
        print("[SupabaseConfig] configuration present but supabase-swift is not linked. Falling back to local bundled repository.")
        #endif
        return baseRepository
        #endif
    }
}
