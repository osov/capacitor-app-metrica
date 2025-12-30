```
import { registerPlugin, Capacitor } from '@capacitor/core';
import { METRIKA_ID } from './storeConfig';

interface AppMetricaPlugin {
  init(options: { apiKey: string }): Promise<void>;
  reportEvent(options: { name: string; params?: Record<string, string> }): Promise<void>;
}

const AppMetrica = registerPlugin<AppMetricaPlugin>('AppMetrica');

let initialized = false;

export async function initMetrica() {
  if (initialized) return;
  if (!Capacitor.isNativePlatform()) {
    console.log('[AppMetrica] Skipping - not a native platform');
    return;
  }

  try {
    await AppMetrica.init({ apiKey: METRIKA_ID });
    initialized = true;
    console.log('[AppMetrica] Initialized');
  } catch (error) {
    console.error('[AppMetrica] Init error:', error);
  }
}

export async function trackEvent(eventName: string, params: object = {}) {
  if (!Capacitor.isNativePlatform()) return;

  try {
    if (!initialized) {
      await initMetrica();
    }
    console.log(`[AppMetrica] Sending event: ${eventName}`, params);
    await AppMetrica.reportEvent({
      name: eventName,
      params: params as Record<string, string>
    });
  } catch (error) {
    console.error('[AppMetrica] Error:', error);
  }
}
```
