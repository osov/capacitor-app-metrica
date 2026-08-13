package com.nickolasgeno.capacitor.appmetrica;

import android.app.Application;
import android.content.Context;
import android.util.Log;

import com.getcapacitor.JSObject;
import com.getcapacitor.Plugin;
import com.getcapacitor.PluginCall;
import com.getcapacitor.PluginMethod;
import com.getcapacitor.annotation.CapacitorPlugin;

import io.appmetrica.analytics.AppMetrica;
import io.appmetrica.analytics.AppMetricaConfig;

import org.json.JSONArray;
import org.json.JSONObject;

import java.util.ArrayList;
import java.util.Collections;
import java.util.HashMap;
import java.util.Iterator;
import java.util.List;
import java.util.Map;

@CapacitorPlugin(name = "AppMetrica")
public class AppMetricaPlugin extends Plugin {
    private static final String TAG = "AppMetrica";

    // AppMetrica.activate поднимает SDK на весь процесс, поэтому признак -
    // статический. Поле экземпляра после пересоздания плагина (сброс моста,
    // восстановление процесса, «Не сохранять активности») сбрасывалось бы в
    // false, и события молча отклонялись бы, хотя SDK работает.
    private static volatile String activatedApiKey = null;

    private static boolean isInitialized() {
        return activatedApiKey != null;
    }

    /**
     * Initialize AppMetrica SDK with API key
     */
    @PluginMethod
    public void init(PluginCall call) {
        String apiKey = call.getString("apiKey");
        if (apiKey == null || apiKey.isEmpty()) {
            call.reject("Missing required parameter: apiKey");
            return;
        }

        String activated = activatedApiKey;
        if (activated != null) {
            // Повторно поднять SDK с другим ключом нельзя. Отвечать успехом
            // молча тоже нельзя: вызывающий думал бы, что события уходят в
            // другое приложение.
            if (!activated.equals(apiKey)) {
                call.reject("AppMetrica is already activated with a different apiKey");
                return;
            }
            call.resolve();
            return;
        }

        AppMetricaConfig config;
        try {
            config = AppMetricaConfig.newConfigBuilder(apiKey).build();
        } catch (Exception e) {
            // Ключ не той формы. Отдельная ошибка, как на iOS: там негодный
            // ключ отсекает сам инициализатор конфигурации.
            Log.e(TAG, "Invalid AppMetrica apiKey");
            call.reject("Invalid AppMetrica apiKey");
            return;
        }

        try {
            // Поднимаем на Application, а не на Activity: от контекста зависит,
            // будет ли SDK считать сессии сам.
            Context appContext = getContext().getApplicationContext();
            AppMetrica.activate(appContext, config);
            // На iOS автоматический учёт сессий включается сам, на Android его
            // надо попросить явно - иначе длительность и количество сессий в
            // отчётах расходятся между платформами.
            if (appContext instanceof Application) {
                AppMetrica.enableActivityAutoTracking((Application) appContext);
            }
            activatedApiKey = apiKey;
            Log.d(TAG, "AppMetrica initialized successfully");
            call.resolve();
        } catch (Exception e) {
            Log.e(TAG, "Error initializing AppMetrica: " + e.getMessage());
            call.reject("Error initializing AppMetrica: " + e.getMessage());
        }
    }

    /**
     * Report a custom event with optional parameters
     */
    @PluginMethod
    public void reportEvent(PluginCall call) {
        if (!isInitialized()) {
            call.reject("AppMetrica not initialized. Call init() first.");
            return;
        }

        String eventName = call.getString("name");
        if (eventName == null || eventName.isEmpty()) {
            call.reject("Missing required parameter: name");
            return;
        }

        try {
            JSObject params = call.getObject("params");
            if (params != null) {
                Map<String, Object> paramsMap = new HashMap<>();
                Iterator<String> keys = params.keys();
                while (keys.hasNext()) {
                    String key = keys.next();
                    // getString() отдаёт null для чисел, булевых и вложенных
                    // объектов - такие параметры молча терялись.
                    Object value = params.opt(key);
                    paramsMap.put(key, stringifyValue(value));
                }
                AppMetrica.reportEvent(eventName, paramsMap);
            } else {
                AppMetrica.reportEvent(eventName);
            }
            Log.d(TAG, "Event reported: " + eventName);
            call.resolve();
        } catch (Exception e) {
            Log.e(TAG, "Error reporting event: " + e.getMessage());
            call.reject("Error reporting event: " + e.getMessage());
        }
    }

    /**
     * Приводит значение параметра к строке так же, как это делает iOS-версия.
     *
     * Вложенные объекты и массивы отдаём JSON-текстом с отсортированными
     * ключами. Порядок вставки тут не годится: на iOS словарь Foundation
     * упорядочен хешем, и воспроизвести порядок из JS там невозможно. Общий
     * детерминированный порядок даёт только сортировка - иначе одно и то же
     * событие выглядит в отчётах по-разному на двух платформах.
     */
    private static String stringifyValue(Object value) {
        if (value == null) return "";
        if (value instanceof JSONObject || value instanceof JSONArray) {
            return toCanonicalJson(value);
        }
        return String.valueOf(value);
    }

    private static String toCanonicalJson(Object value) {
        StringBuilder out = new StringBuilder();
        appendCanonicalJson(out, value);
        return out.toString();
    }

    private static void appendCanonicalJson(StringBuilder out, Object value) {
        if (value instanceof JSONObject) {
            JSONObject object = (JSONObject) value;
            List<String> keys = new ArrayList<>();
            for (Iterator<String> it = object.keys(); it.hasNext(); ) keys.add(it.next());
            Collections.sort(keys);
            out.append('{');
            for (int i = 0; i < keys.size(); i++) {
                if (i > 0) out.append(',');
                appendQuoted(out, keys.get(i));
                out.append(':');
                appendCanonicalJson(out, object.opt(keys.get(i)));
            }
            out.append('}');
            return;
        }
        if (value instanceof JSONArray) {
            JSONArray array = (JSONArray) value;
            out.append('[');
            for (int i = 0; i < array.length(); i++) {
                if (i > 0) out.append(',');
                appendCanonicalJson(out, array.opt(i));
            }
            out.append(']');
            return;
        }
        if (value == null || value == JSONObject.NULL) {
            out.append("null");
            return;
        }
        if (value instanceof String) {
            appendQuoted(out, (String) value);
            return;
        }
        // Числа и булевы печатаются как есть: org.json уже разобрал их из того
        // же JSON.stringify, что видит и iOS.
        out.append(String.valueOf(value));
    }

    /**
     * Экранирование строки для JSON. Правила заданы здесь явно и повторены
     * один в один в iOS-версии: кавычка, обратный и прямой слеш, управляющие
     * символы и разделители строк U+2028/U+2029.
     */
    private static void appendQuoted(StringBuilder out, String text) {
        out.append('"');
        for (int i = 0; i < text.length(); i++) {
            char c = text.charAt(i);
            switch (c) {
                case '"': out.append("\\\""); break;
                case '\\': out.append("\\\\"); break;
                case '/': out.append("\\/"); break;
                case '\b': out.append("\\b"); break;
                case '\f': out.append("\\f"); break;
                case '\n': out.append("\\n"); break;
                case '\r': out.append("\\r"); break;
                case '\t': out.append("\\t"); break;
                default:
                    if (c < 0x20 || c == 0x2028 || c == 0x2029) {
                        out.append(String.format("\\u%04x", (int) c));
                    } else {
                        out.append(c);
                    }
            }
        }
        out.append('"');
    }

    /**
     * Set user profile ID
     */
    @PluginMethod
    public void setUserProfileID(PluginCall call) {
        if (!isInitialized()) {
            call.reject("AppMetrica not initialized. Call init() first.");
            return;
        }

        String userProfileID = call.getString("userProfileID");
        if (userProfileID == null || userProfileID.isEmpty()) {
            call.reject("Missing required parameter: userProfileID");
            return;
        }

        try {
            AppMetrica.setUserProfileID(userProfileID);
            Log.d(TAG, "User profile ID set: " + userProfileID);
            call.resolve();
        } catch (Exception e) {
            Log.e(TAG, "Error setting user profile ID: " + e.getMessage());
            call.reject("Error setting user profile ID: " + e.getMessage());
        }
    }

    /**
     * Get AppMetrica device ID
     */
    @PluginMethod
    public void getDeviceId(PluginCall call) {
        if (!isInitialized()) {
            call.reject("AppMetrica not initialized. Call init() first.");
            return;
        }

        try {
            // Синхронный геттер вместо requestStartupParams: тот без сети не
            // отвечает вовсе, из-за чего вызов ждал таймаута, а отложенный
            // Runnable всё это время держал Activity. Здесь же ответ мгновенный,
            // а до синхронизации со стартапом идентификатора просто нет.
            resolveDeviceId(call, AppMetrica.getDeviceId(getContext()));
        } catch (Exception e) {
            Log.e(TAG, "Error getting device ID: " + e.getMessage());
            call.reject("Error getting device ID: " + e.getMessage());
        }
    }

    /**
     * Идентификатор до первой синхронизации со стартапом отсутствует - это
     * штатная ситуация, поэтому отвечаем пустой строкой, а не отклонением.
     */
    private void resolveDeviceId(PluginCall call, String deviceId) {
        JSObject ret = new JSObject();
        ret.put("deviceId", deviceId != null ? deviceId : "");
        call.resolve(ret);
    }
}
