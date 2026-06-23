//
//  KBORepositoryFactory.swift
//  kboScore
//  기능 설명: 환경 설정에 따라 로컬, 캐시, Supabase 저장소 조합을 생성합니다.
//  외부 KBO·Supabase 응답을 앱 도메인 모델로 안정적으로 변환해 화면 로직이 데이터 소스 변화에 덜 흔들리게 합니다.
//  네트워크 실패, 누락 필드, 캐시 만료, 원천 데이터 형식 변경을 허용 범위 안에서 처리해야 합니다.
//  TODO : 실제 응답 fixture를 계속 추가하고 데이터 소스별 오류 분류를 더 세분화합니다.
//
//  Created by Codex on 5/14/26.
//

import Foundation

// AppRepositoryBundle 구조체는 AppRepositoryBundle 타입의 역할과 값을 정의합니다.
struct AppRepositoryBundle {
    let repository: any KBORepository
    let runtimeState: RepositoryRuntimeState?
}

// AppRepositoryConfiguration 구조체는 AppRepositoryConfiguration 타입의 역할과 값을 정의합니다.
struct AppRepositoryConfiguration: Sendable {
    let supabaseConfiguration: SupabaseConfiguration?

    // 이 초기화 메서드는 인스턴스 생성에 필요한 값을 설정합니다.
    nonisolated init(
        backendBaseURL: URL? = nil,
        supabaseConfiguration: SupabaseConfiguration?
    ) {
        _ = backendBaseURL
        self.supabaseConfiguration = supabaseConfiguration
    }

    // fromEnvironment 메서드는 이 타입의 주요 동작을 수행합니다.
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

    // backendURL 메서드는 이 타입의 주요 동작을 수행합니다.
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

    // firstValidSupabaseConfiguration 메서드는 이 타입의 주요 동작을 수행합니다.
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

    // supabaseConfiguration 메서드는 이 타입의 주요 동작을 수행합니다.
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
    // hasValue 메서드는 조건을 평가해 참/거짓 결과를 반환합니다.
    private nonisolated static func hasValue(_ value: String?) -> Bool {
        guard let value else {
            return false
        }
        return value.isEmpty == false
    }

    // debugHostValue 메서드는 화면 표시와 디버그에 사용할 문구를 구성합니다.
    private nonisolated static func debugHostValue(_ configuration: SupabaseConfiguration?) -> String {
        configuration?.url.host ?? "<none>"
    }
#endif
}

// KBORepositoryFactory 열거형는 실행 환경에 맞는 구현체 생성을 담당합니다.
enum KBORepositoryFactory {
    // makeAppRepositoryBundle 메서드는 화면이나 도메인 모델에 필요한 값을 생성합니다.
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

    // makeSupabaseWrappedRepository 메서드는 화면이나 도메인 모델에 필요한 값을 생성합니다.
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
