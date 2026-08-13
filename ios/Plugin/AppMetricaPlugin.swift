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
            return number.stringValue
        }

        if let string = value as? String { return string }

        // Вложенные объекты и массивы Android отдаёт как JSON-текст.
        if JSONSerialization.isValidJSONObject(value),
           let data = try? JSONSerialization.data(withJSONObject: value),
           let json = String(data: data, encoding: .utf8) {
            return json
        }

        return String(describing: value)
    }
}
