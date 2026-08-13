#import <Foundation/Foundation.h>
#import <Capacitor/Capacitor.h>

// Регистрация плагина в мосту Capacitor. Имена методов обязаны совпадать с
// @objc-методами в AppMetricaPlugin.swift, иначе вызов уйдёт в никуда.
CAP_PLUGIN(AppMetricaPlugin, "AppMetrica",
           CAP_PLUGIN_METHOD(init, CAPPluginReturnPromise);
           CAP_PLUGIN_METHOD(reportEvent, CAPPluginReturnPromise);
           CAP_PLUGIN_METHOD(setUserProfileID, CAPPluginReturnPromise);
           CAP_PLUGIN_METHOD(getDeviceId, CAPPluginReturnPromise);
)
