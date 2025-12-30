import { WebPlugin } from '@capacitor/core';

import type {
  AppMetricaPlugin,
  InitOptions,
  ReportEventOptions,
  SetUserProfileIDOptions,
  DeviceIdResult,
} from './definitions';

export class AppMetricaWeb extends WebPlugin implements AppMetricaPlugin {
  async init(_options: InitOptions): Promise<void> {
    console.warn('AppMetrica: init() is not available on web platform');
  }

  async reportEvent(_options: ReportEventOptions): Promise<void> {
    console.warn('AppMetrica: reportEvent() is not available on web platform');
  }

  async setUserProfileID(_options: SetUserProfileIDOptions): Promise<void> {
    console.warn('AppMetrica: setUserProfileID() is not available on web platform');
  }

  async getDeviceId(): Promise<DeviceIdResult> {
    console.warn('AppMetrica: getDeviceId() is not available on web platform');
    return { deviceId: '' };
  }
}
