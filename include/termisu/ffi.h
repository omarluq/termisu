#ifndef TERMISU_FFI_H
#define TERMISU_FFI_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#define TERMISU_FFI_VERSION 1u

#if defined(__cplusplus)
#define TERMISU_STATIC_ASSERT(expr, msg) static_assert((expr), msg)
#else
#define TERMISU_STATIC_ASSERT(expr, msg) _Static_assert((expr), msg)
#endif

typedef uint64_t termisu_handle_t;

typedef enum termisu_status {
  TERMISU_STATUS_OK = 0,
  TERMISU_STATUS_TIMEOUT = 1,
  TERMISU_STATUS_INVALID_ARGUMENT = 2,
  TERMISU_STATUS_INVALID_HANDLE = 3,
  TERMISU_STATUS_REJECTED = 4,
  TERMISU_STATUS_ERROR = 5,
} termisu_status_t;

typedef enum termisu_event_type {
  TERMISU_EVENT_NONE = 0,
  TERMISU_EVENT_KEY = 1,
  TERMISU_EVENT_MOUSE = 2,
  TERMISU_EVENT_RESIZE = 3,
  TERMISU_EVENT_TICK = 4,
  TERMISU_EVENT_MODE_CHANGE = 5,
} termisu_event_type_t;

typedef enum termisu_color_mode {
  TERMISU_COLOR_DEFAULT = 0,
  TERMISU_COLOR_ANSI8 = 1,
  TERMISU_COLOR_ANSI256 = 2,
  TERMISU_COLOR_RGB = 3,
} termisu_color_mode_t;

typedef struct termisu_color {
  uint8_t mode;
  uint8_t reserved[3];
  int32_t index;
  uint8_t r;
  uint8_t g;
  uint8_t b;
} termisu_color_t;

typedef struct termisu_cell_style {
  termisu_color_t fg;
  termisu_color_t bg;
  uint16_t attr;
} termisu_cell_style_t;

typedef struct termisu_size {
  int32_t width;
  int32_t height;
} termisu_size_t;

typedef struct termisu_event {
  uint8_t event_type;
  uint8_t modifiers;
  uint16_t reserved;

  int32_t key_code;
  int32_t key_char;

  int32_t mouse_x;
  int32_t mouse_y;
  int32_t mouse_button;
  uint8_t mouse_motion;

  int32_t resize_width;
  int32_t resize_height;
  int32_t resize_old_width;
  int32_t resize_old_height;
  uint8_t resize_has_old;

  uint64_t tick_frame;
  int64_t tick_elapsed_ns;
  int64_t tick_delta_ns;
  uint64_t tick_missed_ticks;

  uint32_t mode_current;
  uint32_t mode_previous;
  uint8_t mode_has_previous;
} termisu_event_t;

/* ABI layout guards (must match Crystal FFI structs and JS bindings) */
TERMISU_STATIC_ASSERT(sizeof(termisu_color_t) == 12, "termisu_color_t size mismatch");
TERMISU_STATIC_ASSERT(offsetof(termisu_color_t, mode) == 0, "termisu_color_t.mode offset mismatch");
TERMISU_STATIC_ASSERT(offsetof(termisu_color_t, reserved) == 1,
                      "termisu_color_t.reserved offset mismatch");
TERMISU_STATIC_ASSERT(offsetof(termisu_color_t, index) == 4,
                      "termisu_color_t.index offset mismatch");
TERMISU_STATIC_ASSERT(offsetof(termisu_color_t, r) == 8, "termisu_color_t.r offset mismatch");
TERMISU_STATIC_ASSERT(offsetof(termisu_color_t, g) == 9, "termisu_color_t.g offset mismatch");
TERMISU_STATIC_ASSERT(offsetof(termisu_color_t, b) == 10, "termisu_color_t.b offset mismatch");

TERMISU_STATIC_ASSERT(sizeof(termisu_cell_style_t) == 28, "termisu_cell_style_t size mismatch");
TERMISU_STATIC_ASSERT(offsetof(termisu_cell_style_t, fg) == 0,
                      "termisu_cell_style_t.fg offset mismatch");
TERMISU_STATIC_ASSERT(offsetof(termisu_cell_style_t, bg) == 12,
                      "termisu_cell_style_t.bg offset mismatch");
TERMISU_STATIC_ASSERT(offsetof(termisu_cell_style_t, attr) == 24,
                      "termisu_cell_style_t.attr offset mismatch");

TERMISU_STATIC_ASSERT(sizeof(termisu_size_t) == 8, "termisu_size_t size mismatch");
TERMISU_STATIC_ASSERT(offsetof(termisu_size_t, width) == 0, "termisu_size_t.width offset mismatch");
TERMISU_STATIC_ASSERT(offsetof(termisu_size_t, height) == 4,
                      "termisu_size_t.height offset mismatch");

TERMISU_STATIC_ASSERT(sizeof(termisu_event_t) == 96, "termisu_event_t size mismatch");
TERMISU_STATIC_ASSERT(offsetof(termisu_event_t, event_type) == 0,
                      "termisu_event_t.event_type offset mismatch");
TERMISU_STATIC_ASSERT(offsetof(termisu_event_t, modifiers) == 1,
                      "termisu_event_t.modifiers offset mismatch");
TERMISU_STATIC_ASSERT(offsetof(termisu_event_t, key_code) == 4,
                      "termisu_event_t.key_code offset mismatch");
TERMISU_STATIC_ASSERT(offsetof(termisu_event_t, key_char) == 8,
                      "termisu_event_t.key_char offset mismatch");
TERMISU_STATIC_ASSERT(offsetof(termisu_event_t, mouse_x) == 12,
                      "termisu_event_t.mouse_x offset mismatch");
TERMISU_STATIC_ASSERT(offsetof(termisu_event_t, mouse_y) == 16,
                      "termisu_event_t.mouse_y offset mismatch");
TERMISU_STATIC_ASSERT(offsetof(termisu_event_t, mouse_button) == 20,
                      "termisu_event_t.mouse_button offset mismatch");
TERMISU_STATIC_ASSERT(offsetof(termisu_event_t, mouse_motion) == 24,
                      "termisu_event_t.mouse_motion offset mismatch");
TERMISU_STATIC_ASSERT(offsetof(termisu_event_t, resize_width) == 28,
                      "termisu_event_t.resize_width offset mismatch");
TERMISU_STATIC_ASSERT(offsetof(termisu_event_t, resize_height) == 32,
                      "termisu_event_t.resize_height offset mismatch");
TERMISU_STATIC_ASSERT(offsetof(termisu_event_t, resize_old_width) == 36,
                      "termisu_event_t.resize_old_width offset mismatch");
TERMISU_STATIC_ASSERT(offsetof(termisu_event_t, resize_old_height) == 40,
                      "termisu_event_t.resize_old_height offset mismatch");
TERMISU_STATIC_ASSERT(offsetof(termisu_event_t, resize_has_old) == 44,
                      "termisu_event_t.resize_has_old offset mismatch");
TERMISU_STATIC_ASSERT(offsetof(termisu_event_t, tick_frame) == 48,
                      "termisu_event_t.tick_frame offset mismatch");
TERMISU_STATIC_ASSERT(offsetof(termisu_event_t, tick_elapsed_ns) == 56,
                      "termisu_event_t.tick_elapsed_ns offset mismatch");
TERMISU_STATIC_ASSERT(offsetof(termisu_event_t, tick_delta_ns) == 64,
                      "termisu_event_t.tick_delta_ns offset mismatch");
TERMISU_STATIC_ASSERT(offsetof(termisu_event_t, tick_missed_ticks) == 72,
                      "termisu_event_t.tick_missed_ticks offset mismatch");
TERMISU_STATIC_ASSERT(offsetof(termisu_event_t, mode_current) == 80,
                      "termisu_event_t.mode_current offset mismatch");
TERMISU_STATIC_ASSERT(offsetof(termisu_event_t, mode_previous) == 84,
                      "termisu_event_t.mode_previous offset mismatch");
TERMISU_STATIC_ASSERT(offsetof(termisu_event_t, mode_has_previous) == 88,
                      "termisu_event_t.mode_has_previous offset mismatch");

/* Version and lifecycle */
uint32_t termisu_abi_version(void);
uint64_t termisu_layout_signature(void);
termisu_handle_t termisu_create(uint8_t sync_updates);
int32_t termisu_destroy(termisu_handle_t handle);
int32_t termisu_close(termisu_handle_t handle);

/* Terminal state */
int32_t termisu_size(termisu_handle_t handle, termisu_size_t *out_size);
int32_t termisu_set_sync_updates(termisu_handle_t handle, uint8_t enabled);
uint8_t termisu_sync_updates(termisu_handle_t handle);

/* Rendering */
int32_t termisu_clear(termisu_handle_t handle);
int32_t termisu_render(termisu_handle_t handle);
int32_t termisu_sync(termisu_handle_t handle);
int32_t termisu_set_cursor(termisu_handle_t handle, int32_t x, int32_t y);
int32_t termisu_hide_cursor(termisu_handle_t handle);
int32_t termisu_show_cursor(termisu_handle_t handle);
int32_t termisu_set_cell(termisu_handle_t handle, int32_t x, int32_t y, uint32_t codepoint,
                         const termisu_cell_style_t *style);

/* Input and timer */
int32_t termisu_enable_timer_ms(termisu_handle_t handle, int32_t interval_ms);
int32_t termisu_enable_system_timer_ms(termisu_handle_t handle, int32_t interval_ms);
int32_t termisu_disable_timer(termisu_handle_t handle);
int32_t termisu_enable_mouse(termisu_handle_t handle);
int32_t termisu_disable_mouse(termisu_handle_t handle);
int32_t termisu_enable_enhanced_keyboard(termisu_handle_t handle);
int32_t termisu_disable_enhanced_keyboard(termisu_handle_t handle);
int32_t termisu_poll_event(termisu_handle_t handle, int32_t timeout_ms, termisu_event_t *out_event);

/* Error handling */
uint64_t termisu_last_error_length(void);
uint64_t termisu_last_error_copy(uint8_t *buffer, uint64_t buffer_len);
void termisu_clear_error(void);

#ifdef __cplusplus
}
#endif

#undef TERMISU_STATIC_ASSERT

#endif
