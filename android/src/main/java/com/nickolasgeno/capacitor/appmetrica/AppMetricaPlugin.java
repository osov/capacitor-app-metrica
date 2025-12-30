package com.nickolasgeno.capacitor.appmetrica;

import android.util.Log;

import com.getcapacitor.JSObject;
import com.getcapacitor.Plugin;
import com.getcapacitor.PluginCall;
import com.getcapacitor.PluginMethod;
import com.getcapacitor.annotation.CapacitorPlugin;

import io.appmetrica.analytics.AppMetrica;
import io.appmetrica.analytics.AppMetricaConfig;
import io.appmetrica.analytics.StartupParamsCallback;

import java.util.Arrays;
import java.util.HashMap;
import java.util.Iterator;
import java.util.Map;

@CapacitorPlugin(name = "AppMetrica")
public class AppMetricaPlugin extends Plugin {
    private static final String TAG = "AppMetrica";

    private boolean isInitialized = false;

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

        if (isInitialized) {
            call.resolve();
            return;
        }

        try {
            AppMetricaConfig config = AppMetricaConfig.newConfigBuilder(apiKey).build();
            AppMetrica.activate(getContext(), config);
            isInitialized = true;
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
        if (!isInitialized) {
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
                    paramsMap.put(key, params.getString(key));
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
     * Set user profile ID
     */
    @PluginMethod
    public void setUserProfileID(PluginCall call) {
        if (!isInitialized) {
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
        if (!isInitialized) {
            call.reject("AppMetrica not initialized. Call init() first.");
            return;
        }

        try {
            AppMetrica.requestStartupParams(
                getContext(),
                new StartupParamsCallback() {
                    @Override
                    public void onReceive(Result result) {
                        if (result != null) {
                            String deviceId = result.deviceId;
                            JSObject ret = new JSObject();
                            ret.put("deviceId", deviceId != null ? deviceId : "");
                            call.resolve(ret);
                        } else {
                            call.reject("Failed to get device ID");
                        }
                    }

                    @Override
                    public void onRequestError(Reason reason, Result result) {
                        Log.e(TAG, "Error getting device ID: " + reason.toString());
                        call.reject("Error getting device ID: " + reason.toString());
                    }
                },
                Arrays.asList(StartupParamsCallback.APPMETRICA_DEVICE_ID)
            );
        } catch (Exception e) {
            Log.e(TAG, "Error getting device ID: " + e.getMessage());
            call.reject("Error getting device ID: " + e.getMessage());
        }
    }
}
