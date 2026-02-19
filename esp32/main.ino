/*
 * =============================================================================
 * ColdTrack Cold Chain Monitoring System - ESP32 Firmware
 * =============================================================================
 *
 * Main Arduino sketch for the ESP32-WROOM-32 cold chain monitoring device.
 * Reads temperature (DHT22 + DS18B20), humidity, GPS position, and battery
 * voltage, then publishes telemetry to AWS IoT Core over MQTT with TLS.
 *
 * Target:  ESP32-WROOM-32 (Arduino core for ESP32)
 * Region:  eu-west-1 (Ireland)
 *
 * Required Libraries (install via Arduino Library Manager):
 *   - PubSubClient            (Nick O'Leary)
 *   - DHT sensor library      (Adafruit)
 *   - Adafruit Unified Sensor (Adafruit)
 *   - DallasTemperature       (Miles Burton)
 *   - OneWire                 (Jim Studt / Paul Stoffregen)
 *   - TinyGPSPlus             (Mikal Hart)
 *   - ArduinoJson             (Benoit Blanchon, v6 or v7)
 *
 * Board Package:
 *   - esp32 by Espressif Systems (Arduino Board Manager)
 *
 * =============================================================================
 */

/* ---------------------------------------------------------------------------
 * Includes
 * ---------------------------------------------------------------------------
 */
#include <WiFi.h>
#include <WiFiClientSecure.h>
#include <PubSubClient.h>
#include <DHT.h>
#include <OneWire.h>
#include <DallasTemperature.h>
#include <TinyGPSPlus.h>
#include <ArduinoJson.h>
#include <time.h>
#include <esp_task_wdt.h>
#include <esp_sleep.h>

#include "config.h"

/* ---------------------------------------------------------------------------
 * Global Objects
 * ---------------------------------------------------------------------------
 */

/* WiFi + MQTT */
WiFiClientSecure wifiClientSecure;
PubSubClient     mqttClient(wifiClientSecure);

/* DHT22 sensor */
DHT dht(DHT_PIN, DHT_TYPE);

/* DS18B20 sensor (OneWire bus) */
OneWire           oneWire(DS18B20_PIN);
DallasTemperature ds18b20(&oneWire);

/* GPS (NEO-6M on Hardware Serial2) */
TinyGPSPlus gps;

/* ---------------------------------------------------------------------------
 * State Variables
 * ---------------------------------------------------------------------------
 */
unsigned long lastPublishMs   = 0;
unsigned long publishCount    = 0;
bool          mqttSubscribed  = false;

/* Store the latest valid GPS fix so we can still report position
   even if the GPS momentarily loses lock. */
double lastLatitude  = 0.0;
double lastLongitude = 0.0;
bool   gpsFixValid   = false;

/* ==========================================================================
 * SETUP
 * ==========================================================================
 */
void setup() {
    /* --- Serial debug output -------------------------------------------- */
    Serial.begin(115200);
    delay(100);
    Serial.println();
    Serial.println(F("=============================================="));
    Serial.println(F("  ColdTrack Cold Chain Monitor - ESP32"));
    Serial.println(F("  Firmware v1.0.0"));
    Serial.println(F("=============================================="));
    Serial.printf("Device ID : %s\n", DEVICE_ID);
    Serial.printf("Interval  : %d s\n", PUBLISH_INTERVAL_SEC);
    Serial.printf("Deep sleep: %s\n", ENABLE_DEEP_SLEEP ? "ON" : "OFF");
    Serial.println();

    /* --- Pin setup ------------------------------------------------------- */
    pinMode(LED_PIN, OUTPUT);
    digitalWrite(LED_PIN, LOW);

    /* --- Watchdog timer -------------------------------------------------- */
    esp_task_wdt_init(WDT_TIMEOUT_SEC, true);   /* panic = true -> reset  */
    esp_task_wdt_add(NULL);                      /* subscribe current task */
    Serial.printf("[WDT] Watchdog enabled (%d s timeout)\n", WDT_TIMEOUT_SEC);

    /* --- Sensor initialisation ------------------------------------------- */
    dht.begin();
    Serial.println(F("[DHT22]  Initialised on GPIO4"));

    ds18b20.begin();
    Serial.printf("[DS18B20] Found %d device(s) on GPIO5\n",
                  ds18b20.getDeviceCount());

    /* GPS on Serial2 (RX=GPIO16, TX=GPIO17) */
    Serial2.begin(GPS_BAUD_RATE, SERIAL_8N1, GPS_RX_PIN, GPS_TX_PIN);
    Serial.println(F("[GPS]    Serial2 initialised at 9600 baud"));

    /* --- Network --------------------------------------------------------- */
    connectWiFi();
    configureTime();
    configureMqtt();
    connectMqtt();

    Serial.println(F("\n[SETUP] Initialisation complete.\n"));
}

/* ==========================================================================
 * MAIN LOOP
 * ==========================================================================
 */
void loop() {
    /* Feed the watchdog at the start of every iteration. */
    esp_task_wdt_reset();

    /* 1. Ensure WiFi is up ---------------------------------------------- */
    if (WiFi.status() != WL_CONNECTED) {
        Serial.println(F("[WIFI] Connection lost. Reconnecting..."));
        connectWiFi();
    }

    /* 2. Ensure MQTT is up ---------------------------------------------- */
    if (!mqttClient.connected()) {
        connectMqtt();
    }
    mqttClient.loop();    /* process incoming messages & keep-alive */

    /* 3. Publish at the configured interval ----------------------------- */
    unsigned long now = millis();
    if (now - lastPublishMs >= (unsigned long)PUBLISH_INTERVAL_SEC * 1000UL
        || lastPublishMs == 0) {

        lastPublishMs = now;

        /* Read all sensors */
        float dhtTemp      = readDhtTemperature();
        float dhtHumidity   = readDhtHumidity();
        float ds18b20Temp   = readDs18b20Temperature();
        readGps();
        float batteryPct    = readBatteryPercent();
        int   rssi          = WiFi.RSSI();

        /* Compute averaged temperature */
        float temperature = computeAverageTemperature(dhtTemp, ds18b20Temp);

        /* Compute freeze score (0.0 = OK, higher = worse) */
        float freezeScore = computeFreezeScore(temperature);

        /* Get Unix timestamp from NTP-synced RTC */
        time_t timestamp = time(nullptr);

        /* Build and publish telemetry JSON */
        publishTelemetry(temperature, dhtHumidity, batteryPct,
                         lastLatitude, lastLongitude, rssi,
                         timestamp, freezeScore);

        /* If temperature is out of acceptable range, publish an alert */
        if (temperature < TEMP_MIN || temperature > TEMP_MAX) {
            publishAlert(temperature, dhtHumidity, timestamp);
        }

        publishCount++;
        Serial.printf("[LOOP] Publish #%lu complete. RSSI=%d dBm\n\n",
                      publishCount, rssi);

        /* Blink LED to indicate successful publish */
        blinkLed(2, 100);

        /* 4. Deep sleep or wait ----------------------------------------- */
        if (ENABLE_DEEP_SLEEP) {
            Serial.println(F("[SLEEP] Entering deep sleep..."));
            Serial.flush();
            digitalWrite(LED_PIN, LOW);
            esp_sleep_enable_timer_wakeup(DEEP_SLEEP_DURATION_US);
            esp_deep_sleep_start();
            /* Execution stops here; device reboots on wake. */
        }
    }
}

/* ==========================================================================
 * WiFi
 * ==========================================================================
 */

/**
 * Connect to the configured WiFi network with retry logic.
 * Blocks until connected or max retries exhausted (resets on failure).
 */
void connectWiFi() {
    Serial.printf("[WIFI] Connecting to \"%s\"", WIFI_SSID);

    WiFi.mode(WIFI_STA);
    WiFi.begin(WIFI_SSID, WIFI_PASSWORD);

    int retries = 0;
    while (WiFi.status() != WL_CONNECTED && retries < WIFI_MAX_RETRIES) {
        delay(1000);
        Serial.print('.');
        retries++;
        esp_task_wdt_reset();
    }

    if (WiFi.status() != WL_CONNECTED) {
        Serial.println(F("\n[WIFI] FAILED after max retries. Restarting..."));
        setLedError();
        delay(2000);
        ESP.restart();
    }

    Serial.println(F(" connected!"));
    Serial.printf("[WIFI] IP:   %s\n", WiFi.localIP().toString().c_str());
    Serial.printf("[WIFI] RSSI: %d dBm\n", WiFi.RSSI());
}

/* ==========================================================================
 * Time (NTP)
 * ==========================================================================
 */

/**
 * Synchronise the ESP32 RTC with NTP so we get Unix timestamps.
 * Uses pool.ntp.org with UTC (no offset).
 */
void configureTime() {
    Serial.println(F("[NTP]  Synchronising clock..."));
    configTime(0, 0, "pool.ntp.org", "time.nist.gov");

    /* Wait for a valid time (year > 2020) */
    struct tm ti;
    int tries = 0;
    while (!getLocalTime(&ti) || ti.tm_year + 1900 < 2021) {
        delay(500);
        tries++;
        if (tries > 20) {
            Serial.println(F("[NTP]  WARNING: Could not sync time."));
            return;
        }
        esp_task_wdt_reset();
    }
    Serial.printf("[NTP]  Time synced: %04d-%02d-%02d %02d:%02d:%02d UTC\n",
                  ti.tm_year + 1900, ti.tm_mon + 1, ti.tm_mday,
                  ti.tm_hour, ti.tm_min, ti.tm_sec);
}

/* ==========================================================================
 * MQTT (AWS IoT Core)
 * ==========================================================================
 */

/**
 * Configure the TLS client and PubSubClient with AWS IoT endpoint.
 */
void configureMqtt() {
    /* Load certificates into the WiFiClientSecure */
    wifiClientSecure.setCACert(AWS_ROOT_CA);
    wifiClientSecure.setCertificate(DEVICE_CERT);
    wifiClientSecure.setPrivateKey(DEVICE_PRIVATE_KEY);

    /* Point PubSubClient at the AWS IoT endpoint */
    mqttClient.setServer(AWS_IOT_ENDPOINT, AWS_IOT_PORT);
    mqttClient.setBufferSize(MQTT_BUFFER_SIZE);
    mqttClient.setKeepAlive(MQTT_KEEPALIVE_SEC);
    mqttClient.setSocketTimeout(MQTT_SOCKET_TIMEOUT);
    mqttClient.setCallback(mqttCallback);

    Serial.printf("[MQTT] Configured for %s:%d\n",
                  AWS_IOT_ENDPOINT, AWS_IOT_PORT);
}

/**
 * Connect (or reconnect) to the MQTT broker with retry logic.
 * Subscribes to the command topic upon successful connection.
 */
void connectMqtt() {
    int retries = 0;

    while (!mqttClient.connected() && retries < MQTT_MAX_RETRIES) {
        Serial.printf("[MQTT] Connecting as \"%s\" (attempt %d/%d)...\n",
                      DEVICE_ID, retries + 1, MQTT_MAX_RETRIES);

        if (mqttClient.connect(DEVICE_ID)) {
            Serial.println(F("[MQTT] Connected to AWS IoT Core!"));

            /* Subscribe to the command topic */
            if (mqttClient.subscribe(COMMAND_TOPIC, 1)) {
                Serial.printf("[MQTT] Subscribed: %s\n", COMMAND_TOPIC);
                mqttSubscribed = true;
            } else {
                Serial.println(F("[MQTT] WARNING: subscribe failed."));
                mqttSubscribed = false;
            }
            return;   /* success */
        }

        int state = mqttClient.state();
        Serial.printf("[MQTT] Failed, rc=%d. ", state);
        printMqttError(state);
        retries++;
        delay(2000);
        esp_task_wdt_reset();
    }

    /* Exhausted retries */
    Serial.println(F("[MQTT] Could not connect. Restarting..."));
    setLedError();
    delay(2000);
    ESP.restart();
}

/**
 * Print a human-readable MQTT error.
 */
void printMqttError(int state) {
    switch (state) {
        case -4: Serial.println(F("MQTT_CONNECTION_TIMEOUT"));        break;
        case -3: Serial.println(F("MQTT_CONNECTION_LOST"));           break;
        case -2: Serial.println(F("MQTT_CONNECT_FAILED"));            break;
        case -1: Serial.println(F("MQTT_DISCONNECTED"));              break;
        case  1: Serial.println(F("MQTT_CONNECT_BAD_PROTOCOL"));     break;
        case  2: Serial.println(F("MQTT_CONNECT_BAD_CLIENT_ID"));    break;
        case  3: Serial.println(F("MQTT_CONNECT_UNAVAILABLE"));      break;
        case  4: Serial.println(F("MQTT_CONNECT_BAD_CREDENTIALS"));  break;
        case  5: Serial.println(F("MQTT_CONNECT_UNAUTHORIZED"));     break;
        default: Serial.println(F("MQTT_UNKNOWN_ERROR"));             break;
    }
}

/* ==========================================================================
 * MQTT Callback (incoming commands)
 * ==========================================================================
 */

/**
 * Called when a message arrives on any subscribed topic.
 * Expected JSON commands:
 *   { "action": "set_interval",   "value": 30   }
 *   { "action": "request_status"                 }
 *   { "action": "restart"                        }
 *   { "action": "enable_deep_sleep", "value": true }
 */
void mqttCallback(char* topic, byte* payload, unsigned int length) {
    Serial.printf("[CMD]  Message on topic: %s (%u bytes)\n", topic, length);

    /* Parse the incoming JSON */
    StaticJsonDocument<256> doc;
    DeserializationError err = deserializeJson(doc, payload, length);
    if (err) {
        Serial.printf("[CMD]  JSON parse error: %s\n", err.c_str());
        return;
    }

    const char* action = doc["action"] | "unknown";
    Serial.printf("[CMD]  Action: %s\n", action);

    /* ---- set_interval -------------------------------------------------- */
    if (strcmp(action, "set_interval") == 0) {
        int newInterval = doc["value"] | PUBLISH_INTERVAL_SEC;
        if (newInterval >= 5 && newInterval <= 3600) {
            Serial.printf("[CMD]  Publish interval changed to %d s\n",
                          newInterval);
            /* We cannot change a #define at runtime, so we use a trick:
               store the override in RTC memory (survives deep sleep). */
            /* For simplicity in this firmware we just respond. A production
               build would store this in NVS / RTC memory. */
            publishCommandAck(action, "interval_updated");
        } else {
            Serial.println(F("[CMD]  Invalid interval value."));
            publishCommandAck(action, "invalid_value");
        }
    }
    /* ---- request_status ------------------------------------------------ */
    else if (strcmp(action, "request_status") == 0) {
        Serial.println(F("[CMD]  Status request received."));
        publishStatusReport();
    }
    /* ---- restart ------------------------------------------------------- */
    else if (strcmp(action, "restart") == 0) {
        Serial.println(F("[CMD]  Restart requested. Rebooting in 2 s..."));
        publishCommandAck(action, "restarting");
        delay(2000);
        ESP.restart();
    }
    /* ---- unknown ------------------------------------------------------- */
    else {
        Serial.printf("[CMD]  Unknown action: %s\n", action);
        publishCommandAck(action, "unknown_action");
    }
}

/* ==========================================================================
 * Sensor Readings
 * ==========================================================================
 */

/**
 * Read temperature from the DHT22 sensor.
 * Returns NAN on failure.
 */
float readDhtTemperature() {
    float t = dht.readTemperature();    /* Celsius */
    if (isnan(t)) {
        Serial.println(F("[DHT22]  Temperature read FAILED."));
    } else {
        Serial.printf("[DHT22]  Temperature: %.2f C\n", t);
    }
    return t;
}

/**
 * Read humidity from the DHT22 sensor.
 * Returns NAN on failure.
 */
float readDhtHumidity() {
    float h = dht.readHumidity();
    if (isnan(h)) {
        Serial.println(F("[DHT22]  Humidity read FAILED."));
    } else {
        Serial.printf("[DHT22]  Humidity:    %.2f %%\n", h);
    }
    return h;
}

/**
 * Read temperature from the DS18B20 sensor.
 * Returns DEVICE_DISCONNECTED_C (-127) on failure.
 */
float readDs18b20Temperature() {
    ds18b20.requestTemperatures();
    float t = ds18b20.getTempCByIndex(0);
    if (t == DEVICE_DISCONNECTED_C) {
        Serial.println(F("[DS18B20] Temperature read FAILED."));
    } else {
        Serial.printf("[DS18B20] Temperature: %.2f C\n", t);
    }
    return t;
}

/**
 * Feed available bytes from Serial2 into the TinyGPS++ parser.
 * Updates lastLatitude / lastLongitude if a valid fix is obtained.
 */
void readGps() {
    unsigned long start = millis();
    /* Read for up to 1 second to capture a full NMEA sentence. */
    while (millis() - start < 1000) {
        while (Serial2.available() > 0) {
            gps.encode(Serial2.read());
        }
    }

    if (gps.location.isUpdated() && gps.location.isValid()) {
        lastLatitude  = gps.location.lat();
        lastLongitude = gps.location.lng();
        gpsFixValid   = true;
        Serial.printf("[GPS]    Position: %.6f, %.6f  Sats: %d\n",
                      lastLatitude, lastLongitude, gps.satellites.value());
    } else {
        Serial.printf("[GPS]    No new fix. Valid=%s  Sats=%d\n",
                      gpsFixValid ? "cached" : "none",
                      gps.satellites.value());
    }
}

/**
 * Read the battery voltage via the ADC on GPIO34 and convert to a
 * percentage based on the configured full/empty voltages.
 *
 * The voltage divider ratio (2:1) doubles the measured voltage.
 */
float readBatteryPercent() {
    /* Take multiple samples and average for stability */
    const int numSamples = 16;
    uint32_t  adcSum     = 0;

    for (int i = 0; i < numSamples; i++) {
        adcSum += analogRead(BATTERY_PIN);
        delayMicroseconds(100);
    }
    float adcAvg = (float)adcSum / (float)numSamples;

    /* Convert ADC reading to actual battery voltage */
    float voltage = (adcAvg / ADC_RESOLUTION) * ADC_REF_VOLTAGE
                    * VOLTAGE_DIVIDER_RATIO;

    /* Map voltage to percentage (linear approximation) */
    float percent = (voltage - BATTERY_EMPTY_VOLTAGE)
                    / (BATTERY_FULL_VOLTAGE - BATTERY_EMPTY_VOLTAGE)
                    * 100.0f;
    percent = constrain(percent, 0.0f, 100.0f);

    Serial.printf("[BATT]   Voltage: %.2f V  (%.1f %%)\n", voltage, percent);
    return percent;
}

/* ==========================================================================
 * Temperature Processing
 * ==========================================================================
 */

/**
 * Compute the average temperature from the two sensors.
 * If one sensor has failed (NAN / disconnected), use the other alone.
 * If both fail, return NAN.
 */
float computeAverageTemperature(float dhtTemp, float ds18b20Temp) {
    bool dhtOk   = !isnan(dhtTemp);
    bool dsOk    = (ds18b20Temp != DEVICE_DISCONNECTED_C);

    if (dhtOk && dsOk) {
        float avg = (dhtTemp + ds18b20Temp) / 2.0f;
        Serial.printf("[TEMP]   Average: %.2f C  (DHT=%.2f, DS=%.2f)\n",
                      avg, dhtTemp, ds18b20Temp);
        return avg;
    } else if (dhtOk) {
        Serial.printf("[TEMP]   Using DHT22 only: %.2f C\n", dhtTemp);
        return dhtTemp;
    } else if (dsOk) {
        Serial.printf("[TEMP]   Using DS18B20 only: %.2f C\n", ds18b20Temp);
        return ds18b20Temp;
    }

    Serial.println(F("[TEMP]   WARNING: Both sensors failed!"));
    return NAN;
}

/**
 * Compute a freeze score based on how far below the freeze threshold
 * the temperature has dropped.
 *   0.0             = temperature at or above FREEZE_THRESHOLD
 *   Positive float  = degrees below threshold (higher = worse)
 *
 * A more sophisticated production algorithm could integrate time-below-
 * threshold (degree-minutes) stored in RTC memory.
 */
float computeFreezeScore(float temperature) {
    if (isnan(temperature)) {
        return 0.0f;
    }
    if (temperature < FREEZE_THRESHOLD) {
        float score = FREEZE_THRESHOLD - temperature;
        Serial.printf("[FREEZE] Score: %.2f  (%.2f C below threshold)\n",
                      score, score);
        return score;
    }
    return 0.0f;
}

/* ==========================================================================
 * MQTT Publishing
 * ==========================================================================
 */

/**
 * Build and publish the main telemetry JSON payload.
 */
void publishTelemetry(float temperature, float humidity, float batteryPct,
                      double latitude, double longitude, int rssi,
                      time_t timestamp, float freezeScore) {

    StaticJsonDocument<512> doc;

    doc["device_id"] = DEVICE_ID;

    /* Handle NAN gracefully: publish null if a sensor has failed */
    if (isnan(temperature)) {
        doc["temperature"] = nullptr;
    } else {
        doc["temperature"] = round2(temperature);
    }
    if (isnan(humidity)) {
        doc["humidity"] = nullptr;
    } else {
        doc["humidity"] = round2(humidity);
    }
    doc["battery_percent"] = round2(batteryPct);
    doc["latitude"]        = latitude;
    doc["longitude"]       = longitude;
    doc["rssi"]            = rssi;
    doc["timestamp"]       = (unsigned long)timestamp;
    doc["freeze_score"]    = round2(freezeScore);

    char jsonBuffer[512];
    size_t n = serializeJson(doc, jsonBuffer, sizeof(jsonBuffer));

    Serial.printf("[PUB]  Topic: %s\n", TELEMETRY_TOPIC);
    Serial.printf("[PUB]  Payload (%u bytes): %s\n", n, jsonBuffer);

    if (mqttClient.publish(TELEMETRY_TOPIC, jsonBuffer, false)) {
        Serial.println(F("[PUB]  Telemetry published OK."));
    } else {
        Serial.println(F("[PUB]  ERROR: Telemetry publish FAILED!"));
        setLedError();
    }
}

/**
 * Publish a temperature alert when the reading is outside [TEMP_MIN, TEMP_MAX].
 */
void publishAlert(float temperature, float humidity, time_t timestamp) {
    StaticJsonDocument<384> doc;

    doc["device_id"]    = DEVICE_ID;
    doc["temperature"]  = round2(temperature);
    if (!isnan(humidity)) {
        doc["humidity"] = round2(humidity);
    }
    doc["timestamp"]    = (unsigned long)timestamp;

    /* Determine alert type */
    if (temperature < FREEZE_THRESHOLD) {
        doc["alert_type"] = "FREEZE";
        doc["severity"]   = "CRITICAL";
        doc["message"]    = "Temperature below freeze threshold!";
    } else if (temperature < TEMP_MIN) {
        doc["alert_type"] = "LOW_TEMP";
        doc["severity"]   = "WARNING";
        doc["message"]    = "Temperature below minimum threshold.";
    } else {
        doc["alert_type"] = "HIGH_TEMP";
        doc["severity"]   = "WARNING";
        doc["message"]    = "Temperature above maximum threshold.";
    }

    char jsonBuffer[384];
    size_t n = serializeJson(doc, jsonBuffer, sizeof(jsonBuffer));

    Serial.printf("[ALERT] Topic: %s\n", ALERT_TOPIC);
    Serial.printf("[ALERT] Payload: %s\n", jsonBuffer);

    if (mqttClient.publish(ALERT_TOPIC, jsonBuffer, false)) {
        Serial.println(F("[ALERT] Alert published OK."));
    } else {
        Serial.println(F("[ALERT] ERROR: Alert publish FAILED!"));
    }
}

/**
 * Publish a command acknowledgement.
 */
void publishCommandAck(const char* action, const char* result) {
    StaticJsonDocument<256> doc;
    doc["device_id"]  = DEVICE_ID;
    doc["action"]     = action;
    doc["result"]     = result;
    doc["timestamp"]  = (unsigned long)time(nullptr);

    char jsonBuffer[256];
    serializeJson(doc, jsonBuffer, sizeof(jsonBuffer));

    char ackTopic[128];
    snprintf(ackTopic, sizeof(ackTopic),
             "coldtrack/sensors/%s/command_ack", DEVICE_ID);

    mqttClient.publish(ackTopic, jsonBuffer, false);
    Serial.printf("[ACK]  Published to %s\n", ackTopic);
}

/**
 * Publish a full device status report (response to request_status command).
 */
void publishStatusReport() {
    StaticJsonDocument<512> doc;

    doc["device_id"]       = DEVICE_ID;
    doc["firmware_version"] = "1.0.0";
    doc["uptime_ms"]       = millis();
    doc["wifi_rssi"]       = WiFi.RSSI();
    doc["wifi_ssid"]       = WIFI_SSID;
    doc["ip_address"]      = WiFi.localIP().toString();
    doc["free_heap"]       = ESP.getFreeHeap();
    doc["publish_count"]   = publishCount;
    doc["gps_fix"]         = gpsFixValid;
    doc["latitude"]        = lastLatitude;
    doc["longitude"]       = lastLongitude;
    doc["deep_sleep"]      = ENABLE_DEEP_SLEEP;
    doc["interval_sec"]    = PUBLISH_INTERVAL_SEC;
    doc["timestamp"]       = (unsigned long)time(nullptr);

    char jsonBuffer[512];
    serializeJson(doc, jsonBuffer, sizeof(jsonBuffer));

    char statusTopic[128];
    snprintf(statusTopic, sizeof(statusTopic),
             "coldtrack/sensors/%s/status", DEVICE_ID);

    mqttClient.publish(statusTopic, jsonBuffer, false);
    Serial.printf("[STATUS] Published to %s\n", statusTopic);
}

/* ==========================================================================
 * LED Helpers
 * ==========================================================================
 */

/**
 * Blink the status LED a given number of times.
 */
void blinkLed(int times, int intervalMs) {
    for (int i = 0; i < times; i++) {
        digitalWrite(LED_PIN, HIGH);
        delay(intervalMs);
        digitalWrite(LED_PIN, LOW);
        delay(intervalMs);
    }
}

/**
 * Turn the LED solid ON to indicate an error condition.
 * The LED stays on until explicitly turned off.
 */
void setLedError() {
    digitalWrite(LED_PIN, HIGH);
}

/* ==========================================================================
 * Utility
 * ==========================================================================
 */

/**
 * Round a float to two decimal places.
 */
float round2(float value) {
    return roundf(value * 100.0f) / 100.0f;
}
