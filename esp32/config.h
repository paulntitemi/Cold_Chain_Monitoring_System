/*
 * =============================================================================
 * ColdTrack Cold Chain Monitoring System - ESP32 Configuration
 * =============================================================================
 *
 * Configuration header for the ESP32-WROOM-32 firmware.
 * This file contains WiFi credentials, AWS IoT Core settings, sensor pin
 * definitions, temperature thresholds, and TLS certificates.
 *
 * IMPORTANT: Replace all placeholder values before flashing.
 *            Never commit this file with real credentials to version control.
 *
 * Hardware:
 *   - ESP32-WROOM-32
 *   - DHT22 (temperature + humidity)   -> GPIO4
 *   - DS18B20 (precision temperature)  -> GPIO5
 *   - NEO-6M GPS (UART)               -> GPIO16 (RX), GPIO17 (TX)
 *   - Battery ADC (voltage divider)    -> GPIO34
 *   - Status LED                       -> GPIO2
 *
 * Region: eu-west-1 (Ireland)
 * =============================================================================
 */

#ifndef COLDTRACK_CONFIG_H
#define COLDTRACK_CONFIG_H

/* ---------------------------------------------------------------------------
 * WiFi Configuration
 * ---------------------------------------------------------------------------
 * Replace with your network credentials.
 */
#define WIFI_SSID          "YOUR_WIFI_SSID"
#define WIFI_PASSWORD      "YOUR_WIFI_PASSWORD"
#define WIFI_MAX_RETRIES   20

/* ---------------------------------------------------------------------------
 * AWS IoT Core Configuration
 * ---------------------------------------------------------------------------
 * Obtain your endpoint from the AWS IoT Core console:
 *   Settings -> Device data endpoint
 * Format: <prefix>-ats.iot.<region>.amazonaws.com
 */
#define AWS_IOT_ENDPOINT   "YOUR_ENDPOINT-ats.iot.eu-west-1.amazonaws.com"
#define AWS_IOT_PORT       8883

/* ---------------------------------------------------------------------------
 * Device Identity
 * ---------------------------------------------------------------------------
 * Each physical device must have a unique DEVICE_ID that matches the
 * Thing name registered in AWS IoT Core.
 */
#define DEVICE_ID          "ESP32_TEST_002"

/* ---------------------------------------------------------------------------
 * MQTT Topics
 * ---------------------------------------------------------------------------
 * Topic hierarchy follows the pattern: coldtrack/sensors/{device_id}/...
 * These macros build the full topic strings at compile time.
 */
#define TOPIC_PREFIX           "coldtrack/sensors/" DEVICE_ID
#define TELEMETRY_TOPIC        TOPIC_PREFIX "/telemetry"
#define ALERT_TOPIC            TOPIC_PREFIX "/alerts"
#define COMMAND_TOPIC          "coldtrack/commands/" DEVICE_ID

/* MQTT connection parameters */
#define MQTT_MAX_RETRIES       10
#define MQTT_KEEPALIVE_SEC     60
#define MQTT_SOCKET_TIMEOUT    10
#define MQTT_BUFFER_SIZE       1024

/* ---------------------------------------------------------------------------
 * Publish / Sleep Interval
 * ---------------------------------------------------------------------------
 */
#define PUBLISH_INTERVAL_SEC   60

/* ---------------------------------------------------------------------------
 * Deep Sleep Configuration
 * ---------------------------------------------------------------------------
 * When ENABLE_DEEP_SLEEP is true, the ESP32 enters deep sleep between
 * publish cycles to conserve battery. The device fully reboots on wake.
 * Set to false for continuous operation (USB-powered deployments).
 */
#define ENABLE_DEEP_SLEEP          false
#define DEEP_SLEEP_DURATION_US     (PUBLISH_INTERVAL_SEC * 1000000ULL)

/* ---------------------------------------------------------------------------
 * Temperature Thresholds (Celsius)
 * ---------------------------------------------------------------------------
 * WHO guidelines for RSV vaccine storage: 2-8 C.
 * Freeze threshold triggers a critical alert.
 */
#define TEMP_MIN               2.0f
#define TEMP_MAX               8.0f
#define FREEZE_THRESHOLD       0.0f

/* ---------------------------------------------------------------------------
 * GPIO Pin Definitions
 * ---------------------------------------------------------------------------
 */
#define DHT_PIN                4     /* DHT22 data pin                       */
#define DS18B20_PIN            5     /* DS18B20 OneWire data pin             */
#define GPS_RX_PIN             16    /* NEO-6M TX -> ESP32 RX2               */
#define GPS_TX_PIN             17    /* NEO-6M RX -> ESP32 TX2               */
#define BATTERY_PIN            34    /* Battery voltage divider (ADC1_CH6)   */
#define LED_PIN                2     /* On-board status LED                  */

/* ---------------------------------------------------------------------------
 * Battery ADC Calibration
 * ---------------------------------------------------------------------------
 * The battery voltage is read through a 2:1 resistor divider, so the
 * actual voltage is 2x the ADC reading.
 *
 * ESP32 ADC: 12-bit (0-4095), reference voltage ~3.3V (with attenuation).
 * Vbat = (ADC_RAW / 4095.0) * 3.3 * VOLTAGE_DIVIDER_RATIO
 *
 * Adjust BATTERY_FULL_VOLTAGE and BATTERY_EMPTY_VOLTAGE for your specific
 * battery chemistry (defaults are for single-cell 3.7V Li-Ion / LiPo).
 */
#define VOLTAGE_DIVIDER_RATIO  2.0f
#define ADC_RESOLUTION         4095.0f
#define ADC_REF_VOLTAGE        3.3f
#define BATTERY_FULL_VOLTAGE   4.2f   /* Fully charged Li-Ion cell           */
#define BATTERY_EMPTY_VOLTAGE  3.0f   /* Cutoff voltage                      */

/* ---------------------------------------------------------------------------
 * GPS Configuration
 * ---------------------------------------------------------------------------
 */
#define GPS_BAUD_RATE          9600

/* ---------------------------------------------------------------------------
 * Watchdog Timer
 * ---------------------------------------------------------------------------
 * Hardware watchdog timeout in seconds. If the main loop stalls for longer
 * than this, the ESP32 will reset automatically.
 */
#define WDT_TIMEOUT_SEC        30

/* ---------------------------------------------------------------------------
 * DHT22 Sensor Type
 * ---------------------------------------------------------------------------
 */
#define DHT_TYPE               DHT22

/* ---------------------------------------------------------------------------
 * TLS Certificates for AWS IoT Core
 * ---------------------------------------------------------------------------
 *
 * Three certificates are required for mutual TLS authentication:
 *
 * 1. AWS_ROOT_CA      - Amazon Root CA 1 (AmazonRootCA1.pem)
 *                       Download from: https://www.amazontrust.com/repository/AmazonRootCA1.pem
 *
 * 2. DEVICE_CERT      - Device certificate (.pem.crt)
 *                       Generated when you create a Thing in AWS IoT Core
 *
 * 3. DEVICE_PRIVATE_KEY - Device private key (.pem.key)
 *                         Generated when you create a Thing in AWS IoT Core
 *
 * HOW TO FORMAT:
 *   Paste the entire contents of each PEM file between the R"EOF( and )EOF"
 *   delimiters below. Include the -----BEGIN ... ----- and -----END ... -----
 *   lines exactly as they appear in the original files.
 *
 * SECURITY WARNING:
 *   These certificates grant access to your AWS IoT infrastructure.
 *   - NEVER commit this file with real certificates to version control.
 *   - Add config.h to your .gitignore.
 *   - Store certificates securely and rotate them periodically.
 */

/* Amazon Root CA 1 */
static const char AWS_ROOT_CA[] PROGMEM = R"EOF(
-----BEGIN CERTIFICATE-----
PASTE YOUR Amazon Root CA 1 CERTIFICATE HERE
Download from: https://www.amazontrust.com/repository/AmazonRootCA1.pem
-----END CERTIFICATE-----
)EOF";

/* Device Certificate */
static const char DEVICE_CERT[] PROGMEM = R"EOF(
-----BEGIN CERTIFICATE-----
PASTE YOUR DEVICE CERTIFICATE HERE
Obtain from AWS IoT Core console when creating/registering your Thing
File typically named: xxxxxxxxxx-certificate.pem.crt
-----END CERTIFICATE-----
)EOF";

/* Device Private Key */
static const char DEVICE_PRIVATE_KEY[] PROGMEM = R"EOF(
-----BEGIN RSA PRIVATE KEY-----
PASTE YOUR DEVICE PRIVATE KEY HERE
Obtain from AWS IoT Core console when creating/registering your Thing
File typically named: xxxxxxxxxx-private.pem.key
-----END RSA PRIVATE KEY-----
)EOF";

#endif /* COLDTRACK_CONFIG_H */
