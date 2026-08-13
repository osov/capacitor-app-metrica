import Foundation
import Capacitor
import AppMetricaCore

/**
 * iOS-реализация плагина. Методы и имена параметров повторяют Android-версию
 * (AppMetricaPlugin.java), чтобы JS-код не различал платформы.
 */
@objc(AppMetricaPlugin)
public class AppMetricaPlugin: CAPPlugin {

    private var isInitialized = false

    @objc func `init`(_ call: CAPPluginCall) {
        guard let apiKey = call.getString("apiKey"), !apiKey.isEmpty else {
            call.reject("Missing required parameter: apiKey")
            return
        }

        if isInitialized {
            call.resolve()
            return
        }

        guard let configuration = AppMetricaConfiguration(apiKey: apiKey) else {
            call.reject("Invalid AppMetrica apiKey: \(apiKey)")
            return
        }

        AppMetrica.activate(with: configuration)
        isInitialized = true
        call.resolve()
    }

    @objc func reportEvent(_ call: CAPPluginCall) {
        guard isInitialized else {
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
        guard isInitialized else {
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
        guard isInitialized else {
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
            // Целые значения не должны превращаться в "1.0".
            if let intValue = Int64(exactly: number) { return String(intValue) }
            // String.valueOf(double) в Java уходит в научную запись при
            // |x| >= 1e7 или |x| < 1e-3. Повторяем, иначе одно и то же число
            // выглядит в отчётах по-разному на двух платформах.
            return javaDoubleString(number.doubleValue)
        }

        if let string = value as? String { return string }

        // Вложенные объекты и массивы Android отдаёт как JSON-текст. Ключи
        // сортируем: у Android порядок вставки стабилен, у Foundation - хеш,
        // и без сортировки одно событие меняло бы вид от запуска к запуску.
        if JSONSerialization.isValidJSONObject(value),
           let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]),
           let json = String(data: data, encoding: .utf8) {
            return json
        }

        return String(describing: value)
    }

    /// Повторяет формат Java `String.valueOf(double)`.
    private static func javaDoubleString(_ value: Double) -> String {
        if value == 0 { return value.sign == .minus ? "-0.0" : "0.0" }
        if value.isNaN { return "NaN" }
        if value.isInfinite { return value < 0 ? "-Infinity" : "Infinity" }

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
