#include <WiFi.h>
#include <WiFiClientSecure.h>
#include <PubSubClient.h>
#include <ArduinoJson.h>
#include <time.h>

#include <Wire.h>
#include <SPI.h>
#include <MFRC522.h>
#include <TinyGPSPlus.h>

/* ================= Wi-Fi ================= */
static const char* WIFI_SSID     = "REDMI K80";
static const char* WIFI_PASSWORD = "12345678";

/* ================= AWS IoT Core ================= */
static const char* AWS_IOT_ENDPOINT = "amfou4arkp5l-ats.iot.eu-west-1.amazonaws.com";
static const int   AWS_IOT_PORT     = 8883;

static const char* DEVICE_ID        = "ESP32_TMP102_GPS_RFID_01";
static const char* TELEMETRY_TOPIC  = "coldtrack/sensors/ESP32_TMP102_GPS_RFID_01/data";

/*
  Paste your own certificate below.
  IMPORTANT:
  - Do NOT keep using any private key that has been exposed.
  - Generate a fresh certificate/key pair in AWS IoT Core after testing.
*/

static const char AWS_ROOT_CA[] PROGMEM = R"EOF(
-----BEGIN CERTIFICATE-----
MIIDQTCCAimgAwIBAgITBmyfz5m/jAo54vB4ikPmljZbyjANBgkqhkiG9w0BAQsF
ADA5MQswCQYDVQQGEwJVUzEPMA0GA1UEChMGQW1hem9uMRkwFwYDVQQDExBBbWF6
b24gUm9vdCBDQSAxMB4XDTE1MDUyNjAwMDAwMFoXDTM4MDExNzAwMDAwMFowOTEL
MAkGA1UEBhMCVVMxDzANBgNVBAoTBkFtYXpvbjEZMBcGA1UEAxMQQW1hem9uIFJv
b3QgQ0EgMTCCASIwDQYJKoZIhvcNAQEBBQADggEPADCCAQoCggEBALJ4gHHKeNXj
ca9HgFB0fW7Y14h29Jlo91ghYPl0hAEvrAIthtOgQ3pOsqTQNroBvo3bSMgHFzZM
9O6II8c+6zf1tRn4SWiw3te5djgdYZ6k/oI2peVKVuRF4fn9tBb6dNqcmzU5L/qw
IFAGbHrQgLKm+a/sRxmPUDgH3KKHOVj4utWp+UhnMJbulHheb4mjUcAwhmahRWa6
VOujw5H5SNz/0egwLX0tdHA114gk957EWW67c4cX8jJGKLhD+rcdqsq08p8kDi1L
93FcXmn/6pUCyziKrlA4b9v7LWIbxcceVOF34GfID5yHI9Y/QCB/IIDEgEw+OyQm
jgSubJrIqg0CAwEAAaNCMEAwDwYDVR0TAQH/BAUwAwEB/zAOBgNVHQ8BAf8EBAMC
AYYwHQYDVR0OBBYEFIQYzIU07LwMlJQuCFmcx7IQTgoIMA0GCSqGSIb3DQEBCwUA
A4IBAQCY8jdaQZChGsV2USggNiMOruYou6r4lK5IpDB/G/wkjUu0yKGX9rbxenDI
U5PMCCjjmCXPI6T53iHTfIUJrU6adTrCC2qJeHZERxhlbI1Bjjt/msv0tadQ1wUs
N+gDS63pYaACbvXy8MWy7Vu33PqUXHeeE6V/Uq2V8viTO96LXFvKWlJbYK8U90vv
o/ufQJVtMVT8QtPHRh8jrdkPSHCa2XV4cdFyQzR1bldZwgJcJmApzyMZFo6IQ6XU
5MsI+yMRQ+hDKXJioaldXgjUkK642M4UwtBV8ob2xJNDd2ZhwLnoQdeXeGADbkpy
rqXRfboQnoZsG4q5WTP468SQvvG5
-----END CERTIFICATE-----
)EOF";

static const char DEVICE_CERT[] PROGMEM = R"EOF(
-----BEGIN CERTIFICATE-----
MIIDWTCCAkGgAwIBAgIUYyLRpkYUh04+WINeLxbD6cFefxMwDQYJKoZIhvcNAQEL
BQAwTTFLMEkGA1UECwxCQW1hem9uIFdlYiBTZXJ2aWNlcyBPPUFtYXpvbi5jb20g
SW5jLiBMPVNlYXR0bGUgU1Q9V2FzaGluZ3RvbiBDPVVTMB4XDTI2MDIyNjE0MDcx
MFoXDTQ5MTIzMTIzNTk1OVowHjEcMBoGA1UEAwwTQVdTIElvVCBDZXJ0aWZpY2F0
ZTCCASIwDQYJKoZIhvcNAQEBBQADggEPADCCAQoCggEBAN4p9xtU9d4FOhX+sjAc
Obkd42tHtyxG3do6WhfMoPmatEN9JwyCazyJbWnfDhYtiBxbbIPFchcZwZ33P5Q6
yx+SpCzHVU9GLglmMFvirW8Cykna8b3VX0wkMBJGnR7sxrfF12l2g6PZhF9ZffHr
8zpIA6WoL/b1X0N49jvaKVdzqCWfUncvqfYhcsmxkUJSG+BiGLS0R0r5zli3BIOJ
fHK1OWvUMrqsi3FH9TI0iPjpblJQnlSxJUNhuo6qk798qMk5pag3TiYNdzuRRMlT
N7bb0HXxIkGzS5zC5//7PTx2RD8AUfeyE2LFqkIGypqbPpsWmR67Bbua9ilp7V6Q
+6UCAwEAAaNgMF4wHwYDVR0jBBgwFoAUwSiLb1CFjX4ULWXf4ej9/KzdGb8wHQYD
VR0OBBYEFOKoI9q/F6EwmH4xc4VPhOPyUwK3MAwGA1UdEwEB/wQCMAAwDgYDVR0P
AQH/BAQDAgeAMA0GCSqGSIb3DQEBCwUAA4IBAQAw7oPdK/HwiUOhFfQPj2l3gZk5
Ts+At57ov4CGOLyokdtEwBj9RMJmKYPJMRq5gHJetguwX/GcUjtOeeXkrsd9jjJE
U67ZmoEP/HjKQOq6ChdMIkI9C+G2KVAHQxz+GGFmtP9+d9h1DcL7oGzrk2g2Jdhe
rcpZQrbFyCp5z7Y2+cH4sbU67/uYm6vs24lNxSP0ifKCpAWY6YpBpcTu06eJkbbo
Z+bY4v8hjD6Za6MQENfIJw8a4BCEk9ZODKA+MJkUUmxZv9PKk+dlsCTp2v2o68m8
ZNewhqVjSJAihlB9OCQxgTxhglDEPjkAkcZ8Lo80GNKCs9ywOH1q6uRs3b5O
-----END CERTIFICATE-----
)EOF";

static const char DEVICE_PRIVATE_KEY[] PROGMEM = R"EOF(
-----BEGIN RSA PRIVATE KEY-----
MIIEowIBAAKCAQEA3in3G1T13gU6Ff6yMBw5uR3ja0e3LEbd2jpaF8yg+Zq0Q30n
DIJrPIltad8OFi2IHFtsg8VyFxnBnfc/lDrLH5KkLMdVT0YuCWYwW+KtbwLKSdrx
vdVfTCQwEkadHuzGt8XXaXaDo9mEX1l98evzOkgDpagv9vVfQ3j2O9opV3OoJZ9S
dy+p9iFyybGRQlIb4GIYtLRHSvnOWLcEg4l8crU5a9QyuqyLcUf1MjSI+OluUlCe
VLElQ2G6jqqTv3yoyTmlqDdOJg13O5FEyVM3ttvQdfEiQbNLnMLn//s9PHZEPwBR
97ITYsWqQgbKmps+mxaZHrsFu5r2KWntXpD7pQIDAQABAoIBAGhLLxQHqHyX25Lj
xGbNeVOr8k00l4sToaaG6jBuAcvrkmB0alZ3CzyaD2E6M3S530HgsWqS0GKD1t7/
aTt+9khWIPhcg3H5sjb7YAxit6R7nNdbD01c06X8/ww1ViFkak1vdRavalELFhdk
/bkKWV6s2/lyoUHAIv6b1Ix4eBvy8YIdsjT13ZeEu1rZIyMDqOdaO71NltsuQTM9
e+uFJ54LpXONTUrTSghJ/NHEJZivw9avJOHJDCxXgnyOLiyCYTqGhMJVOXoVaSGq
IccsqcEqmO2fN5mxg0gZroLGX1Rbrl3b0bAHqVBfOySoNiMS2+WCom3AU5L3o8ni
pYIPFakCgYEA+ZNT08wRiOH2on18ykAS0XhFvQHQe6mD+K8bWbGOtiXQLPd3fZCf
rijt+Ulx3BwhKsNKpiUl/eb4Ig+MKvwEdX861RWgwlh1wdPytls0nUUMqlGi23Q8
2HMlCqhkz597tvqVitcNtMFlZszVqbBY+X9dgsni6Zj8uHSOk6ZNtz8CgYEA4+H/
tKHUvAkDu0hbmkqISDOYusKjdQVI7piYMjWJyMlhkP7/jomm+fn8P5wiQQzdmCDY
xitmfglKIsn3wtKs7HAGHBo37DbpLS7gi6ghBneyioGhqH+rfuGu2cssgKlznVBQ
fNcKgWlOMdGGk8yLiRY1zQ36MqQH6Ou0VKNfWBsCgYEAppWP/m7XxWYOGadpBBaA
eRCue9oaLnCXhgZbWyMI/st+iIUlXMqLytPHA/3h4elkugZgbUWedjsUpKd8B7Tv
xP2HZ3NoOlCRSS8PcmiuVcshCQ40hgawFknFD7gWkf8BtMDN0D57B4uPA271rq3m
taIt6H6Y1xMmnHgwMp1ugkECgYADvOpH2Tu3FeLEyKwP/Nb9cDM6JQUvXzXSDBi7
AhvPelYqXbRtbx6ZDRuxI2uAa6ia3TcRERcuTBK2PV/eBzyk6DWBcoCmVERA5Hr0
b36TL5VzJiszq1xxyVvn4KhLN/xYgT/AvHpEoyiQMqKle/5x8jZRtb/74qrqjCs6
FC/1LwKBgH3QccZcYWrKyY9f+IXkAxC5IGBoB3Ir/twSwXMElL8/iwM7JYjkLoBR
6Dt27zT43bdLNCit0CPgmyIgcNMvyFzmjGbUtpuKCG0Dtt7jwcYvCgZJuY7MZ9ZZ
cNZpBnYje5hw6GsOBzCp+lad3/e8rncymIYGV9EXlVVi3//pIhnV
-----END RSA PRIVATE KEY-----
)EOF";

/* ================= TMP102 (I2C) ================= */
#define TMP102_ADDR 0x48
#define SDA_PIN 21
#define SCL_PIN 22

bool readTMP102(float &tempC) {
  Wire.beginTransmission(TMP102_ADDR);
  Wire.write(0x00);
  if (Wire.endTransmission(false) != 0) return false;

  Wire.requestFrom(TMP102_ADDR, (uint8_t)2);
  if (Wire.available() != 2) return false;

  uint8_t msb = Wire.read();
  uint8_t lsb = Wire.read();

  int16_t raw = ((msb << 8) | lsb) >> 4;
  if (raw & 0x800) raw |= 0xF000;
  tempC = raw * 0.0625f;
  return true;
}

/* ================= GPS (GT-U7) ================= */
#define GPS_RX_PIN 16
#define GPS_TX_PIN 17
#define GPS_BAUD   9600

TinyGPSPlus gps;
double lastLat = 0.0, lastLon = 0.0;
bool   hasFix  = false;

void feedGPS(uint32_t ms) {
  uint32_t start = millis();
  while (millis() - start < ms) {
    while (Serial2.available() > 0) {
      gps.encode((char)Serial2.read());
    }
  }

  if (gps.location.isUpdated() && gps.location.isValid()) {
    lastLat = gps.location.lat();
    lastLon = gps.location.lng();
    hasFix  = true;
  }
}

/* ================= RFID (MFRC522) ================= */
#define RFID_SS_PIN  5
#define RFID_RST_PIN 27

MFRC522 rfid(RFID_SS_PIN, RFID_RST_PIN);
String currentUID = "";

/* ================= Vibration Sensor (HW-072) ================= */
#define VIBRATION_PIN 4

// 如果你的测试表明“振动=HIGH”，保持 true；
// 如果测试表明“振动=LOW”，改成 false
const bool VIBRATION_ACTIVE_HIGH = true;

// 10秒窗口
const uint32_t VIBRATION_WINDOW_MS = 10000;

// 最多记录的事件数（10秒内一般够用了）
const int MAX_VIB_EVENTS = 100;

uint32_t vibrationEventTimes[MAX_VIB_EVENTS];
int vibrationEventHead = 0;   // 指向最旧事件
int vibrationEventCount = 0;  // 当前窗口内事件数
bool lastVibrationRawState = false;

bool isVibrationActiveRaw(int state) {
  return VIBRATION_ACTIVE_HIGH ? (state == HIGH) : (state == LOW);
}

void pruneOldVibrationEvents(uint32_t nowMs) {
  while (vibrationEventCount > 0) {
    uint32_t oldest = vibrationEventTimes[vibrationEventHead];
    if (nowMs - oldest <= VIBRATION_WINDOW_MS) {
      break;
    }
    vibrationEventHead = (vibrationEventHead + 1) % MAX_VIB_EVENTS;
    vibrationEventCount--;
  }
}

void recordVibrationEvent(uint32_t nowMs) {
  if (vibrationEventCount < MAX_VIB_EVENTS) {
    int insertIndex = (vibrationEventHead + vibrationEventCount) % MAX_VIB_EVENTS;
    vibrationEventTimes[insertIndex] = nowMs;
    vibrationEventCount++;
  } else {
    // 满了就覆盖最旧的
    vibrationEventTimes[vibrationEventHead] = nowMs;
    vibrationEventHead = (vibrationEventHead + 1) % MAX_VIB_EVENTS;
  }
}

void updateVibrationWindow() {
  uint32_t nowMs = millis();
  int rawState = digitalRead(VIBRATION_PIN);
  bool isActive = isVibrationActiveRaw(rawState);

  // 只在“非激活 -> 激活”的边沿计数，避免一次振动算很多次
  if (!lastVibrationRawState && isActive) {
    recordVibrationEvent(nowMs);
    Serial.println("⚡ Vibration event detected");
  }

  lastVibrationRawState = isActive;
  pruneOldVibrationEvents(nowMs);
}

int getVibrationCountLast10s() {
  pruneOldVibrationEvents(millis());
  return vibrationEventCount;
}

/* ================= App Logic ================= */
bool     activeSampling = false;
uint32_t lastCardSeenMs = 0;
uint32_t lastSampleMs   = 0;

const uint32_t SAMPLE_INTERVAL_MS = 5000;
const uint32_t ACTIVE_TIMEOUT_MS  = 300000;

String uidToString(const MFRC522::Uid &uid) {
  String s;
  for (byte i = 0; i < uid.size; i++) {
    if (uid.uidByte[i] < 0x10) s += "0";
    s += String(uid.uidByte[i], HEX);
    if (i != uid.size - 1) s += ":";
  }
  s.toUpperCase();
  return s;
}

/* ================= MQTT / TLS ================= */
WiFiClientSecure net;
PubSubClient mqttClient(net);

void connectWiFi() {
  Serial.printf("[WIFI] Connecting to %s", WIFI_SSID);
  WiFi.mode(WIFI_STA);
  WiFi.begin(WIFI_SSID, WIFI_PASSWORD);

  int retries = 0;
  while (WiFi.status() != WL_CONNECTED && retries < 30) {
    delay(500);
    Serial.print(".");
    retries++;
  }

  if (WiFi.status() != WL_CONNECTED) {
    Serial.println("\n[WIFI] Failed. Restarting...");
    delay(2000);
    ESP.restart();
  }

  Serial.println("\n[WIFI] Connected");
  Serial.print("[WIFI] IP: ");
  Serial.println(WiFi.localIP());
  Serial.printf("[WIFI] RSSI: %d dBm\n", WiFi.RSSI());
}

void syncTime() {
  Serial.println("[NTP] Syncing time...");
  configTime(0, 0, "pool.ntp.org", "time.nist.gov");

  struct tm timeinfo;
  int retries = 0;
  while (!getLocalTime(&timeinfo) && retries < 20) {
    delay(500);
    Serial.print(".");
    retries++;
  }
  Serial.println();

  if (retries >= 20) {
    Serial.println("[NTP] Failed to sync time. TLS may fail.");
  } else {
    Serial.printf("[NTP] Time synced: %04d-%02d-%02d %02d:%02d:%02d UTC\n",
                  timeinfo.tm_year + 1900,
                  timeinfo.tm_mon + 1,
                  timeinfo.tm_mday,
                  timeinfo.tm_hour,
                  timeinfo.tm_min,
                  timeinfo.tm_sec);
  }
}

void setupMqtt() {
  net.setCACert(AWS_ROOT_CA);
  net.setCertificate(DEVICE_CERT);
  net.setPrivateKey(DEVICE_PRIVATE_KEY);

  mqttClient.setServer(AWS_IOT_ENDPOINT, AWS_IOT_PORT);
  mqttClient.setBufferSize(1024);
  mqttClient.setKeepAlive(60);
}

void connectMqtt() {
  while (!mqttClient.connected()) {
    Serial.printf("[MQTT] Connecting as %s ...\n", DEVICE_ID);
    if (mqttClient.connect(DEVICE_ID)) {
      Serial.println("[MQTT] Connected to AWS IoT Core");
    } else {
      Serial.printf("[MQTT] Failed, rc=%d. Retrying in 2s...\n", mqttClient.state());
      delay(2000);
    }
  }
}

/* ================= RSV Risk Scoring ================= */

const float RSV_TEMP_MIN_C = 2.0;
const float RSV_TEMP_MAX_C = 8.0;

bool excursionActive = false;
uint32_t excursionStartMs = 0;
uint32_t excursionSeconds = 0;

// Risk breakdown fields for dashboard/explainability
int temperatureRisk = 0;
int durationRisk = 0;
int vibrationRisk = 0;
int gpsRisk = 0;

void updateExcursionTracking(float tempC) {
  if (isnan(tempC)) {
    excursionActive = false;
    excursionSeconds = 0;
    return;
  }

  bool outOfRange = (tempC < RSV_TEMP_MIN_C || tempC > RSV_TEMP_MAX_C);

  if (outOfRange) {
    if (!excursionActive) {
      excursionActive = true;
      excursionStartMs = millis();
    }
    excursionSeconds = (millis() - excursionStartMs) / 1000;
  } else {
    excursionActive = false;
    excursionSeconds = 0;
  }
}

int calculateRiskScore(float tempC, int vibrationCount10s, bool gpsFix) {
  temperatureRisk = 0;
  durationRisk = 0;
  vibrationRisk = 0;
  gpsRisk = 0;

  // Temperature risk, capped at 70
  if (isnan(tempC)) {
    temperatureRisk = 45;
  } else if (tempC < RSV_TEMP_MIN_C) {
    temperatureRisk = min(70, (int)((RSV_TEMP_MIN_C - tempC) * 20.0));
  } else if (tempC > RSV_TEMP_MAX_C) {
    temperatureRisk = min(70, (int)((tempC - RSV_TEMP_MAX_C) * 8.0));
  }

  // Duration risk, capped at 20
  durationRisk = min(20, (int)(excursionSeconds * 0.15));

  // Vibration risk, capped at 10
  if (vibrationCount10s >= 5) {
    vibrationRisk = 10;
  } else if (vibrationCount10s >= 2) {
    vibrationRisk = 5;
  }

  // GPS risk, capped at 5
  if (!gpsFix) {
    gpsRisk = 5;
  }

  int total = temperatureRisk + durationRisk + vibrationRisk + gpsRisk;

  if (total > 100) total = 100;
  if (total < 0) total = 0;

  return total;
}

String getRiskStatus(int score) {
  if (score <= 25) return "SAFE";
  if (score <= 60) return "WARNING";
  return "CRITICAL";
}

void publishTelemetry(const String& uid, float tempC, int vibrationCount10s) {
  updateExcursionTracking(tempC);

  int riskScore = calculateRiskScore(tempC, vibrationCount10s, hasFix);
  String status = getRiskStatus(riskScore);
  bool alert = (status != "SAFE");

  StaticJsonDocument<1024> doc;

  doc["schema_version"] = "1.0";
  doc["device_id"] = DEVICE_ID;
  doc["shipment_active"] = activeSampling;
  doc["rfid_uid"] = uid;

  doc["threshold_profile"] = "RSV_2_8C";
  doc["safe_temp_min_c"] = RSV_TEMP_MIN_C;
  doc["safe_temp_max_c"] = RSV_TEMP_MAX_C;

  if (isnan(tempC)) {
    doc["temperature_c"] = nullptr;
  } else {
    doc["temperature_c"] = tempC;
  }

  doc["excursion_seconds"] = excursionSeconds;

  if (hasFix) {
    doc["latitude"]  = lastLat;
    doc["longitude"] = lastLon;
  } else {
    doc["latitude"]  = nullptr;
    doc["longitude"] = nullptr;
  }

  doc["gps_fix"] = hasFix;
  doc["satellites"] = gps.satellites.isValid() ? gps.satellites.value() : 0;
  doc["hdop"] = gps.hdop.isValid() ? gps.hdop.hdop() : 99.9;

  doc["vibration_count_10s"] = vibrationCount10s;

  doc["temperature_risk"] = temperatureRisk;
  doc["duration_risk"] = durationRisk;
  doc["vibration_risk"] = vibrationRisk;
  doc["gps_risk"] = gpsRisk;

  doc["risk_score"] = riskScore;
  doc["status"] = status;
  doc["alert"] = alert;

  doc["rssi"] = WiFi.RSSI();
  doc["timestamp"] = (unsigned long)time(nullptr);

  char payload[1024];
  serializeJson(doc, payload, sizeof(payload));

  Serial.printf("[MQTT] Publishing to %s\n", TELEMETRY_TOPIC);
  Serial.printf("[MQTT] Payload: %s\n", payload);

  bool ok = mqttClient.publish(TELEMETRY_TOPIC, payload);

  if (ok) {
    Serial.println("[MQTT] Publish OK");
  } else {
    Serial.println("[MQTT] Publish FAILED");
  }
}

void setup() {
  Serial.begin(115200);
  delay(500);
  Serial.println("\nColdTrack Demo: RFID -> TMP102 + GPS + VibrationCount(10s) -> AWS IoT");

  /* Sensors */
  Wire.begin(SDA_PIN, SCL_PIN);
  Serial2.begin(GPS_BAUD, SERIAL_8N1, GPS_RX_PIN, GPS_TX_PIN);

  SPI.begin();        // SCK=18 MISO=19 MOSI=23
  rfid.PCD_Init();

  pinMode(VIBRATION_PIN, INPUT);

  // 初始化当前振动状态
  lastVibrationRawState = isVibrationActiveRaw(digitalRead(VIBRATION_PIN));

  /* Network */
  connectWiFi();
  syncTime();
  setupMqtt();
  connectMqtt();

  Serial.println("Ready. Tap an RFID card to start sampling and publishing...");
}

void loop() {
  if (WiFi.status() != WL_CONNECTED) {
    connectWiFi();
  }

  if (!mqttClient.connected()) {
    connectMqtt();
  }
  mqttClient.loop();

  // 持续更新 vibration 10秒窗口
  updateVibrationWindow();

  // Keep GPS parser alive
  feedGPS(10);

  // 1) Check RFID
  if (rfid.PICC_IsNewCardPresent() && rfid.PICC_ReadCardSerial()) {
    currentUID = uidToString(rfid.uid);
    activeSampling = true;
    lastCardSeenMs = millis();

    Serial.print("\n✅ Card detected. UID = ");
    Serial.println(currentUID);
    Serial.println("→ Start TMP102 + GPS + vibration-count sampling + AWS publish");

    rfid.PICC_HaltA();
    rfid.PCD_StopCrypto1();
  }

  // 2) Exit sampling if timeout
  if (activeSampling && (millis() - lastCardSeenMs > ACTIVE_TIMEOUT_MS)) {
    activeSampling = false;
    Serial.println("\n⏹️ No card recently. Back to standby (RFID only).");
  }

  // 3) If active, sample + publish periodically
  if (activeSampling && (millis() - lastSampleMs >= SAMPLE_INTERVAL_MS)) {
    lastSampleMs = millis();

    float tempC = NAN;
    bool tempOk = readTMP102(tempC);

    // Give GPS a bit more time before publish
    feedGPS(300);

    int vibCount10s = getVibrationCountLast10s();

    Serial.println("--------------------------------------------------");
    Serial.print("UID: ");
    Serial.println(currentUID);

    if (tempOk) {
      Serial.print("TMP102 Temperature: ");
      Serial.print(tempC, 2);
      Serial.println(" °C");
    } else {
      Serial.println("❌ TMP102 read failed.");
    }

    Serial.print("GPS: ");
    if (hasFix) {
      Serial.print(lastLat, 6);
      Serial.print(", ");
      Serial.print(lastLon, 6);
    } else {
      Serial.print("NO FIX");
    }

    Serial.print(" | Sats: ");
    Serial.print(gps.satellites.isValid() ? gps.satellites.value() : 0);

    Serial.print(" | HDOP: ");
    Serial.println(gps.hdop.isValid() ? gps.hdop.hdop() : 99.9);

    Serial.print("Vibration count in last 10s: ");
    Serial.println(vibCount10s);

    publishTelemetry(currentUID, tempOk ? tempC : NAN, vibCount10s);
  }
}