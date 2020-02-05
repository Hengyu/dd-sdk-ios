import Foundation

/// Global SDK `Logger` using console output.
/// This logger is meant for debugging purposes during SDK development, hence **it should print useful information to SDK developer**.
/// It is only instantiated when `DD_SDK_DEVELOPMENT` compilation condition is set for `Datadog` target.
/// Some information posted with `developerLogger` may be also passed to `userLogger` with `.debug()` level to help SDK users
/// understand why the SDK is not operating.
internal let developerLogger = createSDKDeveloperLogger()

/// Global SDK `Logger` using console output.
/// This logger is meant for debugging purposes when using SDK, hence **it should print useful information to SDK user**.
/// It is only used when `Datadog.verbosityLevel` value is set.
/// Every information posted to user should be properly classified (most commonly `.debug()` or `.error()`) according to
/// its context: does the message pop up due to user error or user's app environment error? or is it SDK error?
internal let userLogger = createSDKUserLogger()

internal func createSDKDeveloperLogger(
    consolePrintFunction: @escaping (String) -> Void = { print($0) },
    dateProvider: DateProvider = SystemDateProvider(),
    timeFormatter: DateFormatter = LogConsoleOutput.shortTimeFormatter()
) -> Logger? {
    if CompilationConditions.isSDKCompiledForDevelopment == false {
        return nil
    }

    guard let appContext = Datadog.instance?.appContext else {
        return nil
    }

    let consoleOutput = LogConsoleOutput(
        logBuilder: LogBuilder(
            appContext: appContext,
            serviceName: "sdk-developer",
            loggerName: "sdk-developer",
            dateProvider: dateProvider
        ),
        format: .shortWith(prefix: "🐶 → "),
        printingFunction: consolePrintFunction,
        timeFormatter: timeFormatter
    )

    return Logger(logOutput: consoleOutput)
}

internal func createSDKUserLogger(
    consolePrintFunction: @escaping (String) -> Void = { print($0) },
    dateProvider: DateProvider = SystemDateProvider(),
    timeFormatter: DateFormatter = LogConsoleOutput.shortTimeFormatter()
) -> Logger {
    guard let appContext = Datadog.instance?.appContext else {
        return Logger(logOutput: NoOpLogOutput())
    }

    let consoleOutput = LogConsoleOutput(
        logBuilder: LogBuilder(
            appContext: appContext,
            serviceName: "sdk-user",
            loggerName: "sdk-user",
            dateProvider: dateProvider
        ),
        format: .shortWith(prefix: "[DATADOG SDK] 🐶 → "),
        printingFunction: consolePrintFunction,
        timeFormatter: timeFormatter
    )

    return Logger(
        logOutput: ConditionalLogOutput(conditionedOutput: consoleOutput) { logLevel in
            logLevel.rawValue >= (Datadog.verbosityLevel?.rawValue ?? .max)
        }
    )
}
