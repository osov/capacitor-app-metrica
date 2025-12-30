export interface InitOptions {
  /**
   * AppMetrica API key from the web interface
   */
  apiKey: string;
}

export interface ReportEventOptions {
  /**
   * Event name
   */
  name: string;
  /**
   * Optional event parameters
   */
  params?: Record<string, string>;
}

export interface SetUserProfileIDOptions {
  /**
   * User profile ID
   */
  userProfileID: string;
}

export interface DeviceIdResult {
  /**
   * AppMetrica device ID
   */
  deviceId: string;
}

export interface AppMetricaPlugin {
  /**
   * Initialize AppMetrica SDK with API key
   * @param options - Initialization options with API key
   */
  init(options: InitOptions): Promise<void>;

  /**
   * Report a custom event
   * @param options - Event name and optional parameters
   */
  reportEvent(options: ReportEventOptions): Promise<void>;

  /**
   * Set user profile ID for analytics
   * @param options - User profile ID
   */
  setUserProfileID(options: SetUserProfileIDOptions): Promise<void>;

  /**
   * Get AppMetrica device ID
   * @returns Promise with device ID
   */
  getDeviceId(): Promise<DeviceIdResult>;
}
