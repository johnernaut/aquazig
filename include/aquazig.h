/*
 * AquaZig - ScreenLogic Pool Controller Library
 *
 * C-compatible API for Swift/Objective-C interop.
 * This header declares all exported functions from the AquaZig library.
 */

#ifndef AQUAZIG_H
#define AQUAZIG_H

#include <stdint.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

/* ============================================================================
 * Error Codes
 * ============================================================================ */

#define AQUAZIG_OK                    0
#define AQUAZIG_ERR_NOT_CONNECTED    -1
#define AQUAZIG_ERR_LOGIN_FAILED     -2
#define AQUAZIG_ERR_INVALID_RESPONSE -3
#define AQUAZIG_ERR_UNEXPECTED_MSG   -4
#define AQUAZIG_ERR_TIMEOUT          -5
#define AQUAZIG_ERR_CONNECTION_CLOSED -6
#define AQUAZIG_ERR_BUFFER_TOO_SMALL -7
#define AQUAZIG_ERR_OUT_OF_MEMORY    -8
#define AQUAZIG_ERR_CONNECTION_FAILED -9
#define AQUAZIG_ERR_ALREADY_CONNECTED -10
#define AQUAZIG_ERR_UNKNOWN          -99

/* ============================================================================
 * Heat Modes
 * ============================================================================ */

#define AQUAZIG_HEAT_OFF              0
#define AQUAZIG_HEAT_SOLAR            1
#define AQUAZIG_HEAT_SOLAR_PREFERRED  2
#define AQUAZIG_HEAT_HEATER           3

/* ============================================================================
 * Connection States
 * ============================================================================ */

#define AQUAZIG_STATE_DISCONNECTED    0
#define AQUAZIG_STATE_CONNECTING      1
#define AQUAZIG_STATE_HANDSHAKING     2
#define AQUAZIG_STATE_AUTHENTICATING  3
#define AQUAZIG_STATE_READY           4
#define AQUAZIG_STATE_RECONNECTING    5
#define AQUAZIG_STATE_FAILED          6

/* ============================================================================
 * Body Types
 * ============================================================================ */

#define AQUAZIG_BODY_POOL             0
#define AQUAZIG_BODY_SPA              1

/* ============================================================================
 * Pump Types
 * ============================================================================ */

#define AQUAZIG_PUMP_UNKNOWN          0
#define AQUAZIG_PUMP_VF               1  /* Variable Flow */
#define AQUAZIG_PUMP_VS               2  /* Variable Speed */
#define AQUAZIG_PUMP_VSF              3  /* Variable Speed/Flow */

/* ============================================================================
 * Opaque Types
 * ============================================================================ */

/**
 * Opaque client handle
 *
 * Represents an AquaZig client instance. Create with aquazig_client_create(),
 * free with aquazig_client_free().
 */
typedef struct aquazig_client aquazig_client_t;

/* ============================================================================
 * Data Structures
 * ============================================================================ */

/**
 * Body (pool/spa) status
 */
typedef struct {
    int32_t current_temp;    /* Current water temperature */
    int32_t heat_setpoint;   /* Target temperature when heating */
    int32_t cool_setpoint;   /* Target temperature for cooling */
    uint32_t heat_mode;      /* AQUAZIG_HEAT_* constant */
    bool heat_status;        /* true if heater is actively running */
    bool is_valid;           /* true if this body exists */
} aquazig_body_status_t;

/**
 * Pool/spa overall status
 */
typedef struct {
    bool ok;                 /* System OK flag */
    bool freeze_mode;        /* Freeze protection active */
    int32_t air_temp;        /* Ambient air temperature */

    aquazig_body_status_t pool;  /* Pool body status */
    aquazig_body_status_t spa;   /* Spa body status */

    /* Chemistry data (0 if not available) */
    float ph;                /* pH level (e.g., 7.4) */
    int32_t orp;             /* ORP in mV */
    int32_t salt_ppm;        /* Salt level in ppm */
    float saturation;        /* Saturation index */
} aquazig_pool_status_t;

/**
 * Pump circuit configuration
 */
typedef struct {
    uint32_t circuit_id;     /* Controller circuit ID */
    uint32_t speed;          /* Configured speed */
    bool is_rpm;             /* true=RPM, false=GPM */
} aquazig_pump_circuit_t;

/**
 * Pump status
 */
typedef struct {
    uint32_t pump_type;      /* AQUAZIG_PUMP_* constant */
    bool is_running;         /* true if pump is running */
    uint32_t watts;          /* Current power consumption */
    uint32_t rpm;            /* Current RPM */
    uint32_t gpm;            /* Current GPM (flow rate) */
    aquazig_pump_circuit_t circuits[8];  /* Circuit configurations */
} aquazig_pump_status_t;

/**
 * Circuit info
 */
typedef struct {
    uint32_t id;             /* Circuit ID */
    bool state;              /* true=on, false=off */
} aquazig_circuit_t;

/**
 * Controller info (basic)
 */
typedef struct {
    uint32_t controller_id;      /* Controller ID */
    uint8_t controller_type;     /* Controller type */
    uint8_t hardware_type;       /* Hardware type (EasyTouch, IntelliTouch, etc.) */
    uint8_t controller_data;     /* Controller data byte */
    uint8_t equipment_flags;     /* Equipment flags */
    bool is_celsius;             /* true if using Celsius */
    uint8_t min_setpoint_pool;   /* Min pool setpoint */
    uint8_t max_setpoint_pool;   /* Max pool setpoint */
    uint8_t min_setpoint_spa;    /* Min spa setpoint */
    uint8_t max_setpoint_spa;    /* Max spa setpoint */
} aquazig_controller_info_t;

/**
 * Circuit info with name
 */
typedef struct {
    uint32_t id;                 /* Circuit ID */
    char name[32];               /* Circuit name (null-terminated) */
    uint8_t name_index;          /* Name index */
    uint8_t function;            /* Circuit function type */
    uint8_t interface;           /* Interface type */
    uint8_t freeze;              /* Freeze protection enabled */
    uint8_t device_id;           /* Device ID */
    uint8_t _padding[3];         /* Padding for alignment */
} aquazig_circuit_info_t;

/**
 * Full controller configuration with circuits
 */
typedef struct {
    uint32_t controller_id;      /* Controller ID */
    uint8_t controller_type;     /* Controller type */
    uint8_t hardware_type;       /* Hardware type */
    uint8_t controller_data;     /* Controller data byte */
    uint8_t equipment_flags;     /* Equipment flags */
    bool is_celsius;             /* true if using Celsius */
    uint8_t min_setpoint_pool;   /* Min pool setpoint */
    uint8_t max_setpoint_pool;   /* Max pool setpoint */
    uint8_t min_setpoint_spa;    /* Min spa setpoint */
    uint8_t max_setpoint_spa;    /* Max spa setpoint */
    uint8_t _padding[3];         /* Padding for alignment */
    uint32_t circuit_count;      /* Number of circuits */
    aquazig_circuit_info_t circuits[20];  /* Circuit array */
} aquazig_controller_config_t;

/**
 * Scheduled event
 */
typedef struct {
    uint32_t schedule_id;        /* Schedule ID */
    uint32_t circuit_id;         /* Circuit ID */
    uint32_t start_time;         /* Start time (minutes from midnight) */
    uint32_t stop_time;          /* Stop time (minutes from midnight) */
    uint8_t day_mask;            /* Day mask (Sun=1, Mon=2, Tue=4, etc.) */
    uint8_t flags;               /* Flags (bit 1 = enabled) */
    uint8_t heat_cmd;            /* Heat command */
    uint8_t heat_setpoint;       /* Heat setpoint */
} aquazig_scheduled_event_t;

/**
 * Schedule (collection of events)
 */
typedef struct {
    uint32_t event_count;                    /* Number of events */
    aquazig_scheduled_event_t events[16];    /* Events array */
} aquazig_schedule_t;

/* ============================================================================
 * Callback Types
 * ============================================================================ */

/**
 * Status change callback
 *
 * Called when the controller pushes a status update after subscribing.
 *
 * @param userdata  User-provided context pointer
 * @param status    Pointer to the new status (valid only during callback)
 */
typedef void (*aquazig_status_callback_t)(
    void* userdata,
    const aquazig_pool_status_t* status
);

/**
 * Disconnect callback
 *
 * Called when the connection is lost or fails.
 *
 * @param userdata  User-provided context pointer
 * @param reason    Disconnect reason:
 *                  0 = normal disconnect
 *                  1 = connection lost
 *                  2 = timeout
 *                  3 = max reconnection retries exceeded
 */
typedef void (*aquazig_disconnect_callback_t)(
    void* userdata,
    int reason
);

/* ============================================================================
 * Client Lifecycle
 * ============================================================================ */

/**
 * Create a new AquaZig client with default configuration
 *
 * @return  Opaque client handle, or NULL on failure
 */
aquazig_client_t* aquazig_client_create(void);

/**
 * Create a new AquaZig client with custom configuration
 *
 * @param timeout_ms            Connection/operation timeout in milliseconds
 * @param ping_interval_ms      Keepalive ping interval (0 to disable)
 * @param auto_reconnect        Enable automatic reconnection
 * @param max_reconnect_attempts Maximum reconnection attempts (0 for unlimited)
 * @return  Opaque client handle, or NULL on failure
 */
aquazig_client_t* aquazig_client_create_with_config(
    uint32_t timeout_ms,
    uint32_t ping_interval_ms,
    bool auto_reconnect,
    uint32_t max_reconnect_attempts
);

/**
 * Free an AquaZig client
 *
 * Disconnects if connected and releases all resources.
 *
 * @param client  Client handle (may be NULL)
 */
void aquazig_client_free(aquazig_client_t* client);

/* ============================================================================
 * Connection
 * ============================================================================ */

/**
 * Discover and connect to a ScreenLogic device on the local network
 *
 * Sends a UDP broadcast to find devices and connects to the first one found.
 *
 * @param client  Client handle
 * @return  AQUAZIG_OK on success, error code on failure
 */
int aquazig_discover_and_connect(aquazig_client_t* client);

/**
 * Connect to a ScreenLogic device at a specific IP and port
 *
 * @param client  Client handle
 * @param host    Null-terminated IP address string (e.g., "192.168.1.100")
 * @param port    Port number (typically 80)
 * @return  AQUAZIG_OK on success, error code on failure
 */
int aquazig_connect(aquazig_client_t* client, const char* host, uint16_t port);

/**
 * Disconnect from the device
 *
 * @param client  Client handle
 */
void aquazig_disconnect(aquazig_client_t* client);

/**
 * Check if connected and logged in
 *
 * @param client  Client handle
 * @return  true if connected, false otherwise
 */
bool aquazig_is_connected(aquazig_client_t* client);

/**
 * Get current connection state
 *
 * @param client  Client handle
 * @return  AQUAZIG_STATE_* constant
 */
int aquazig_get_state(aquazig_client_t* client);

/**
 * Attempt to reconnect to the last known address
 *
 * Uses exponential backoff between attempts.
 *
 * @param client  Client handle
 * @return  AQUAZIG_OK on success, error code on failure
 */
int aquazig_reconnect(aquazig_client_t* client);

/* ============================================================================
 * Status
 * ============================================================================ */

/**
 * Get pool/spa status
 *
 * @param client      Client handle
 * @param out_status  Pointer to status struct to fill
 * @return  AQUAZIG_OK on success, error code on failure
 */
int aquazig_get_status(aquazig_client_t* client, aquazig_pool_status_t* out_status);

/**
 * Send ping to keep connection alive
 *
 * @param client  Client handle
 * @return  AQUAZIG_OK on success, error code on failure
 */
int aquazig_ping(aquazig_client_t* client);

/* ============================================================================
 * Control
 * ============================================================================ */

/**
 * Set circuit state (turn on/off)
 *
 * @param client      Client handle
 * @param circuit_id  Circuit ID (e.g., 505 for Pool, 500 for Spa)
 * @param state       true = on, false = off
 * @return  AQUAZIG_OK on success, error code on failure
 */
int aquazig_set_circuit_state(aquazig_client_t* client, uint32_t circuit_id, bool state);

/**
 * Set heat mode for pool or spa
 *
 * @param client   Client handle
 * @param body_id  AQUAZIG_BODY_POOL or AQUAZIG_BODY_SPA
 * @param mode     AQUAZIG_HEAT_* constant
 * @return  AQUAZIG_OK on success, error code on failure
 */
int aquazig_set_heat_mode(aquazig_client_t* client, uint32_t body_id, uint32_t mode);

/**
 * Set temperature setpoint for pool or spa
 *
 * @param client      Client handle
 * @param body_id     AQUAZIG_BODY_POOL or AQUAZIG_BODY_SPA
 * @param temperature Target temperature in current units (F or C)
 * @return  AQUAZIG_OK on success, error code on failure
 */
int aquazig_set_heat_setpoint(aquazig_client_t* client, uint32_t body_id, uint32_t temperature);

/* ============================================================================
 * Pump
 * ============================================================================ */

/**
 * Get pump status
 *
 * @param client      Client handle
 * @param pump_id     0-indexed pump number
 * @param out_status  Pointer to pump status struct to fill
 * @return  AQUAZIG_OK on success, error code on failure
 */
int aquazig_get_pump_status(
    aquazig_client_t* client,
    uint32_t pump_id,
    aquazig_pump_status_t* out_status
);

/**
 * Set pump speed for a circuit
 *
 * @param client        Client handle
 * @param pump_id       0-indexed pump number
 * @param circuit_index Index into pump's circuit array (0-7)
 * @param speed         Speed value (RPM: 400-3450, GPM: 1-130)
 * @param is_rpm        true for RPM mode, false for GPM mode
 * @return  AQUAZIG_OK on success, error code on failure
 */
int aquazig_set_pump_speed(
    aquazig_client_t* client,
    uint32_t pump_id,
    uint32_t circuit_index,
    uint32_t speed,
    bool is_rpm
);

/* ============================================================================
 * Subscriptions
 * ============================================================================ */

/**
 * Subscribe to status change notifications
 *
 * After calling this, the controller will push status updates.
 * Note: Push notifications require processing the event loop,
 * which happens automatically during other operations.
 *
 * @param client  Client handle
 * @return  AQUAZIG_OK on success, error code on failure
 */
int aquazig_subscribe_status(aquazig_client_t* client);

/**
 * Unsubscribe from status change notifications
 *
 * @param client  Client handle
 * @return  AQUAZIG_OK on success, error code on failure
 */
int aquazig_unsubscribe_status(aquazig_client_t* client);

/**
 * Check if subscribed to status updates
 *
 * @param client  Client handle
 * @return  true if subscribed, false otherwise
 */
bool aquazig_is_subscribed(aquazig_client_t* client);

/* ============================================================================
 * Controller Info
 * ============================================================================ */

/**
 * Get controller info (basic)
 *
 * @param client    Client handle
 * @param out_info  Pointer to controller info struct to fill
 * @return  AQUAZIG_OK on success, error code on failure
 */
int aquazig_get_controller_info(
    aquazig_client_t* client,
    aquazig_controller_info_t* out_info
);

/**
 * Get full controller configuration including circuit names
 *
 * @param client      Client handle
 * @param out_config  Pointer to controller config struct to fill
 * @return  AQUAZIG_OK on success, error code on failure
 */
int aquazig_get_controller_config(
    aquazig_client_t* client,
    aquazig_controller_config_t* out_config
);

/* ============================================================================
 * Schedules
 * ============================================================================ */

/**
 * Get schedule
 *
 * @param client         Client handle
 * @param schedule_type  0 = recurring schedules, 1 = one-time (run-once) events
 * @param out_schedule   Pointer to schedule struct to fill
 * @return  AQUAZIG_OK on success, error code on failure
 */
int aquazig_get_schedule(
    aquazig_client_t* client,
    uint32_t schedule_type,
    aquazig_schedule_t* out_schedule
);

#ifdef __cplusplus
}
#endif

#endif /* AQUAZIG_H */
