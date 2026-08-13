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
            return numberString(number)
        }

        if let string = value as? String { return string }

        // Вложенные объекты и массивы Android отдаёт как JSON-текст. Пишем его
        // сами, а не через JSONSerialization: та сортирует ключи своим
        // сравнением (без учёта регистра, с числовым порядком и по локали),
        // не экранирует «/» и печатает числа по-своему - то есть тот же
        // объект давал бы на двух платформах разный текст.
        var out = ""
        appendCanonicalJson(&out, value)
        return out
    }

    /// Пишет JSON так же, как Android-двойник (toCanonicalJson): ключи
    /// отсортированы, строки экранированы по правилам org.json, числа - по
    /// правилам Java.
    private static func appendCanonicalJson(_ out: inout String, _ value: Any) {
        if let dictionary = value as? [String: Any] {
            out += "{"
            var isFirst = true
            for key in dictionary.keys.sorted(by: { $0.utf16.lexicographicallyPrecedes($1.utf16) }) {
                if !isFirst { out += "," }
                isFirst = false
                appendQuoted(&out, key)
                out += ":"
                appendCanonicalJson(&out, dictionary[key] as Any)
            }
            out += "}"
            return
        }
        if let array = value as? [Any] {
            out += "["
            for (index, item) in array.enumerated() {
                if index > 0 { out += "," }
                appendCanonicalJson(&out, item)
            }
            out += "]"
            return
        }
        if value is NSNull {
            out += "null"
            return
        }
        if let string = value as? String {
            appendQuoted(&out, string)
            return
        }
        if let number = value as? NSNumber {
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                out += number.boolValue ? "true" : "false"
            } else if !number.doubleValue.isFinite {
                // JSON.stringify на Android превращает нечисло в null.
                out += "null"
            } else {
                out += numberString(number)
            }
            return
        }
        appendQuoted(&out, String(describing: value))
    }

    /// Экранирование строки для JSON. Правила заданы явно и повторены один в
    /// один в Android-версии (appendQuoted): кавычка, обратный и прямой слеш,
    /// управляющие символы и разделители строк U+2028/U+2029. Полагаться на
    /// JSONSerialization или org.json нельзя - они экранируют по-разному.
    private static func appendQuoted(_ out: inout String, _ text: String) {
        out += "\""
        for character in text.unicodeScalars {
            switch character {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "/": out += "\\/"
            case "\u{08}": out += "\\b"
            case "\u{0C}": out += "\\f"
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            default:
                if character.value < 0x20 || character.value == 0x2028 || character.value == 0x2029 {
                    out += String(format: "\\u%04x", character.value)
                } else {
                    out.unicodeScalars.append(character)
                }
            }
        }
        out += "\""
    }

    /// Печатает число так же, как это делает Android.
    ///
    /// Там значение приезжает десятичным текстом от JSON.stringify: целое до
    /// Long, дробное до double. Поэтому целые печатаются полностью, без
    /// экспоненты, и печатаются те цифры, что прислал JS, а не точное двоичное
    /// значение double - для чисел больше 2^53 это разные вещи.
    private static func numberString(_ number: NSNumber) -> String {
        let value = number.doubleValue
        // До 2^53 double и целое совпадают точно.
        if abs(value) < 9007199254740992, let intValue = Int64(exactly: number) {
            return String(intValue)
        }
        if let plain = plainIntegerString(value) { return plain }
        return javaDoubleString(value)
    }

    /// Целое значение в обычной записи, как его печатает Java для Long.
    /// Цифры берём из кратчайшей записи - ровно те, что прислал JS.
    private static func plainIntegerString(_ value: Double) -> String? {
        guard value.rounded() == value, abs(value) < 1e21 else { return nil }

        var text = String(value)
        var sign = ""
        if text.hasPrefix("-") {
            sign = "-"
            text.removeFirst()
        }

        var mantissa = text
        var exponent = 0
        if let markerIndex = text.firstIndex(where: { $0 == "e" || $0 == "E" }) {
            mantissa = String(text[text.startIndex..<markerIndex])
            let rawExponent = text[text.index(after: markerIndex)...].replacingOccurrences(of: "+", with: "")
            guard let parsed = Int(rawExponent) else { return nil }
            exponent = parsed
        }

        var digits = mantissa
        var pointOffset = mantissa.count
        if let dotIndex = mantissa.firstIndex(of: ".") {
            pointOffset = mantissa.distance(from: mantissa.startIndex, to: dotIndex)
            digits.remove(at: digits.index(digits.startIndex, offsetBy: pointOffset))
        }

        let integerLength = pointOffset + exponent
        if integerLength >= digits.count {
            return sign + digits + String(repeating: "0", count: integerLength - digits.count)
        }
        // Хвост после запятой у целого значения может быть только нулями.
        let tail = digits.suffix(digits.count - integerLength)
        guard tail.allSatisfy({ $0 == "0" }) else { return nil }
        return sign + digits.prefix(integerLength)
    }

    /// Повторяет формат Java `String.valueOf(double)`.
    private static func javaDoubleString(_ value: Double) -> String {
        // Нули и нечисла сюда не доходят: первые уходят в Int64(exactly:),
        // вторые отсекаются проверкой на конечность выше.
        let magnitude = abs(value)
        if magnitude >= 1e-3 && magnitude < 1e7 {
            // Обычная запись. Целые сюда не доходят - их забирает numberString,
            // поэтому дробная часть в результате есть всегда.
            return shortestRoundTrip(value) ?? String(format: "%.17g", value)
        }

        // Научная запись вида 1.23456785E7 - с большой E и без плюса.
        let text = shortestRoundTrip(value, scientific: true) ?? String(format: "%.17E", value)
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
