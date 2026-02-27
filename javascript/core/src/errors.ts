import type { Status } from "./constants";

export class TermisuError extends Error {
  readonly status: Status;

  constructor(status: Status, message: string, action?: string) {
    super(action ? `${action}: ${message}` : message);
    this.name = "TermisuError";
    this.status = status;
  }
}
