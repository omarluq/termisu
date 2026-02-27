#include <stdint.h>
#include <stdio.h>
#include <string.h>

#include "termisu/ffi.h"

static void print_last_error(void) {
  uint64_t len = termisu_last_error_length();
  if (len == 0) {
    return;
  }

  char buffer[512];
  uint64_t copied = termisu_last_error_copy((uint8_t *)buffer, sizeof(buffer));
  if (copied >= sizeof(buffer)) {
    copied = sizeof(buffer) - 1;
  }
  buffer[copied] = '\0';
  fprintf(stderr, "Termisu error: %s\n", buffer);
}

static int32_t check_status(int32_t status) {
  if (status == TERMISU_STATUS_OK || status == TERMISU_STATUS_TIMEOUT) {
    return status;
  }

  print_last_error();
  return status;
}

int main(void) {
  printf("Termisu C ABI version: %u\n", termisu_abi_version());

  termisu_handle_t handle = termisu_create(1);
  if (handle == 0) {
    print_last_error();
    return 1;
  }

  termisu_cell_style_t title_style = {
    .fg = {.mode = TERMISU_COLOR_ANSI8, .index = 2},
    .bg = {.mode = TERMISU_COLOR_DEFAULT, .index = -1},
    .attr = 1 /* Bold */,
  };

  if (check_status(termisu_clear(handle)) != TERMISU_STATUS_OK) {
    termisu_destroy(handle);
    return 1;
  }
  if (check_status(termisu_set_cell(handle, 2, 1, 'T', &title_style)) != TERMISU_STATUS_OK ||
      check_status(termisu_set_cell(handle, 3, 1, 'e', &title_style)) != TERMISU_STATUS_OK ||
      check_status(termisu_set_cell(handle, 4, 1, 'r', &title_style)) != TERMISU_STATUS_OK ||
      check_status(termisu_set_cell(handle, 5, 1, 'm', &title_style)) != TERMISU_STATUS_OK ||
      check_status(termisu_set_cell(handle, 6, 1, 'i', &title_style)) != TERMISU_STATUS_OK ||
      check_status(termisu_set_cell(handle, 7, 1, 's', &title_style)) != TERMISU_STATUS_OK ||
      check_status(termisu_set_cell(handle, 8, 1, 'u', &title_style)) != TERMISU_STATUS_OK) {
    termisu_destroy(handle);
    return 1;
  }

  termisu_cell_style_t prompt_style = {
    .fg = {.mode = TERMISU_COLOR_ANSI8, .index = 7},
    .bg = {.mode = TERMISU_COLOR_DEFAULT, .index = -1},
    .attr = 0,
  };

  const char *prompt = "Press q to quit";
  for (size_t i = 0; i < strlen(prompt); i++) {
    if (check_status(termisu_set_cell(handle, 2 + (int32_t)i, 3, (uint32_t)prompt[i],
                                      &prompt_style)) != TERMISU_STATUS_OK) {
      termisu_destroy(handle);
      return 1;
    }
  }

  if (check_status(termisu_render(handle)) != TERMISU_STATUS_OK) {
    termisu_destroy(handle);
    return 1;
  }

  while (1) {
    termisu_event_t event = {0};
    int32_t status = termisu_poll_event(handle, 100, &event);
    if (status == TERMISU_STATUS_TIMEOUT) {
      continue;
    }
    if (check_status(status) != TERMISU_STATUS_OK) {
      break;
    }

    if (event.event_type == TERMISU_EVENT_KEY && (event.key_char == 'q' || event.key_char == 'Q')) {
      break;
    }
  }

  check_status(termisu_destroy(handle));
  return 0;
}
