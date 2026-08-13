import Foundation
import Capacitor
import AppMetricaCore

/**
 * iOS-реализация плагина. Методы и имена параметров повторяют Android-версию
 * (AppMetricaPlugin.java), чтобы JS-код не различал платформы.
 */
@objc(AppMetricaPlugin)
public class AppMetricaPlugin: CAPPlugin {

    // AppMetrica.activate поднимает SDK на весь процесс, поэтому и признак -
    // статический. Поле экземпляра после пересоздания плагина (сброс моста,
    // восстановление процесса) сбрасывалось бы в false, и все события молча
    // отклонялись бы как «не инициализировано», хотя SDK работает.
    private static var activatedApiKey: String?
    private static var isInitialized: Bool { activatedApiKey != nil }

    @objc func `init`(_ call: CAPPluginCall) {
        guard let apiKey = call.getString("apiKey"), !apiKey.isEmpty else {
            call.reject("Missing required parameter: apiKey")
            return
        }

        if let activated = Self.activatedApiKey {
            // Повторная активация другим ключом невозможна: SDK поднимается один
            // раз за процесс. Молча отвечать успехом нельзя - вызывающий думал
            // бы, что события уходят в другое приложение.
            if activated != apiKey {
                call.reject("AppMetrica is already activated with a different apiKey")
                return
            }
            call.resolve()
            return
        }

        guard let configuration = AppMetricaConfiguration(apiKey: apiKey) else {
            call.reject("Invalid AppMetrica apiKey")
            return
        }

        AppMetrica.activate(with: configuration)
        Self.activatedApiKey = apiKey
        call.resolve()
    }

    @objc func reportEvent(_ call: CAPPluginCall) {
        guard Self.isInitialized else {
            call.reject("AppMetrica not initialized. Call init() first.")
            return
        }

        guard let name = call.getString("name"), !name.isEmpty else {
            call.reject("Missing required parameter: name")
            return
        }

        // Android приводит значения к строкам через String.valueOf поверх
        // JSONObject. String(describing:) поверх Foundation-типов даёт другое:
        // булево становится "1"/"0", NSNull - "<null>", целое Double - "1.0".
        // Приводим вручную, иначе одно событие выглядит в отчётах по-разному.
        var parameters: [AnyHashable: Any]?
        if let params = call.getObject("params") {
            var stringified: [AnyHashable: Any] = [:]
            for (key, value) in params {
                stringified[key] = Self.stringifyLikeAndroid(value)
            }
            parameters = stringified
        }

        AppMetrica.reportEvent(name: name, parameters: parameters) { error in
            print("[AppMetrica] reportEvent failed: \(error.localizedDescription)")
        }
        call.resolve()
    }

    @objc func setUserProfileID(_ call: CAPPluginCall) {
        guard Self.isInitialized else {
            call.reject("AppMetrica not initialized. Call init() first.")
            return
        }

        guard let userProfileID = call.getString("userProfileID"), !userProfileID.isEmpty else {
            call.reject("Missing required parameter: userProfileID")
            return
        }

        AppMetrica.userProfileID = userProfileID
        call.resolve()
    }

    @objc func getDeviceId(_ call: CAPPluginCall) {
        guard Self.isInitialized else {
            call.reject("AppMetrica not initialized. Call init() first.")
            return
        }

        // Синхронное свойство вместо requestStartupIdentifiers(on:completion:):
        // до первой синхронизации со стартапом оно nil, и это нормальный ответ.
        call.resolve(["deviceId": AppMetrica.deviceID ?? ""])
    }

    /// Повторяет формат Android: String.valueOf поверх значения из JSON.
    private static func stringifyLikeAndroid(_ value: Any) -> String {
        if value is NSNull { return "null" }

        if let number = value as? NSNumber {
            // Булево в JSON приходит как NSNumber с типом Bool.
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                return number.boolValue ? "true" : "false"
            }
            // NaN и бесконечности до Android не доезжают вовсе: JSON.stringify
            // на мосту превращает их в null, и String.valueOf даёт "null".
            // iOS получает живое число, поэтому приводим сами.
            if !number.doubleValue.isFinite { return "null" }
            // Целые значения не должны превращаться в "1.0".
            if let intValue = Int64(exactly: number) { return String(intValue) }
            // String.valueOf(double) в Java уходит в научную запись при
            // |x| >= 1e7 или |x| < 1e-3. Повторяем, иначе одно и то же число
            // выглядит в отчётах по-разному на двух платформах.
            return javaDoubleString(number.doubleValue)
        }

        if let string = value as? String { return string }

        // Вложенные объекты и массивы Android отдаёт как JSON-текст. Ключи
        // сортируем с обеих сторон: у Foundation порядок словаря определяется
        // хешем, воспроизвести порядок вставки из JS невозможно, поэтому
        // единый детерминированный порядок задаёт сортировка (Android делает то
        // же самое в toCanonicalJson).
        let sanitized = sanitizeForJson(value)
        if JSONSerialization.isValidJSONObject(sanitized),
           let data = try? JSONSerialization.data(withJSONObject: sanitized, options: [.sortedKeys]),
           let json = String(data: data, encoding: .utf8) {
            return json
        }

        return String(describing: value)
    }

    /// Приводит содержимое вложенных структур к тому, что переживёт
    /// JSONSerialization.
    ///
    /// На Android мост прогоняет данные через JSON.stringify, поэтому туда
    /// доезжают только строки, числа, булевы, null и контейнеры. На iOS мост
    /// отдаёт объекты как есть, и внутри могут оказаться NaN, бесконечности и
    /// Date. Любой из них проваливает isValidJSONObject для ВСЕГО контейнера, и
    /// в отчёт ушло бы Swift-описание вида `["a": nan]` вместо JSON.
    private static func sanitizeForJson(_ value: Any) -> Any {
        if let dictionary = value as? [String: Any] {
            var result: [String: Any] = [:]
            for (key, nested) in dictionary { result[key] = sanitizeForJson(nested) }
            return result
        }
        if let array = value as? [Any] {
            return array.map { sanitizeForJson($0) }
        }
        if value is NSNull { return value }
        if let string = value as? String { return string }
        if let number = value as? NSNumber {
            // Булево - это тоже NSNumber, но конечное: проверять его не нужно.
            if CFGetTypeID(number) == CFBooleanGetTypeID() { return number }
            // JSON.stringify отдаёт нечисло как null - повторяем.
            return number.doubleValue.isFinite ? number : NSNull()
        }
        if let date = value as? Date { return isoFormatter.string(from: date) }
        // Всё остальное JSON не переживёт - отдаём текстом, как Date.prototype.toJSON.
        return String(describing: value)
    }

    /// Тот же формат, что даёт Date.prototype.toJSON на Android: с миллисекундами.
    private static let isoFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'"
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    /// Повторяет формат Java `String.valueOf(double)`.
    private static func javaDoubleString(_ value: Double) -> String {
        // Нули и нечисла сюда не доходят: первые уходят в Int64(exactly:),
        // вторые отсекаются проверкой на конечность выше.
        let magnitude = abs(value)
        if magnitude >= 1e-3 && magnitude < 1e7 {
            // Обычная запись; целые значения Java пишет с ".0".
            let text = String(format: "%.17g", value)
            let shortest = shortestRoundTrip(value) ?? text
            return shortest.contains(".") || shortest.contains("e") ? shortest : shortest + ".0"
        }

        // Научная запись вида 1.23456785E7 - с большой E и без плюса.
        var text = String(format: "%.17E", value)
        if let shortest = shortestRoundTrip(value, scientific: true) { text = shortest }
        return normalizeExponent(text)
    }

    /// C печатает экспоненту минимум двумя цифрами и со знаком (`E+07`, `E-04`),
    /// Java - без плюса и без ведущих нулей (`E7`, `E-4`). Приводим к Java.
    private static func normalizeExponent(_ text: String) -> String {
        guard let range = text.range(of: "E") else { return text }
        let mantissa = String(text[text.startIndex..<range.lowerBound])
        var exponent = String(text[range.upperBound...])

        var sign = ""
        if exponent.hasPrefix("+") {
            exponent.removeFirst()
        } else if exponent.hasPrefix("-") {
            sign = "-"
            exponent.removeFirst()
        }

        while exponent.count > 1 && exponent.hasPrefix("0") {
            exponent.removeFirst()
        }
        return mantissa + "E" + sign + exponent
    }

    /// Кратчайшая запись, которая читается обратно без потери точности.
    private static func shortestRoundTrip(_ value: Double, scientific: Bool = false) -> String? {
        for precision in 1...17 {
            let text = String(format: scientific ? "%.\(precision)E" : "%.\(precision)g", value)
            if Double(text) == value { return text }
        }
        return nil
    }
}
