import type { AttributeMask } from "./attribute";
import type { ColorMode, EventType } from "./constants";

export type TermisuHandle = bigint;

export interface Size {
  width: number;
  height: number;
}

export interface TermisuColor {
  mode: ColorMode;
  index?: number;
  r?: number;
  g?: number;
  b?: number;
}

export interface CellStyle {
  fg?: TermisuColor;
  bg?: TermisuColor;
  attr?: AttributeMask;
}

interface BaseEvent {
  type: EventType;
  modifiers: number;
}

export interface KeyEvent extends BaseEvent {
  type: EventType.Key;
  keyCode: number;
  keyChar: number | null;
}

export interface MouseEvent extends BaseEvent {
  type: EventType.Mouse;
  x: number;
  y: number;
  button: number;
  motion: boolean;
}

export interface ResizeEvent extends BaseEvent {
  type: EventType.Resize;
  width: number;
  height: number;
  oldWidth: number | null;
  oldHeight: number | null;
}

export interface TickEvent extends BaseEvent {
  type: EventType.Tick;
  frame: bigint;
  elapsedNs: bigint;
  deltaNs: bigint;
  missedTicks: bigint;
}

export interface ModeChangeEvent extends BaseEvent {
  type: EventType.ModeChange;
  current: number;
  previous: number | null;
}

export interface UnknownEvent extends BaseEvent {
  type: EventType.None;
}

export type AnyEvent =
  | KeyEvent
  | MouseEvent
  | ResizeEvent
  | TickEvent
  | ModeChangeEvent
  | UnknownEvent;

export interface TermisuOptions {
  libraryPath?: string;
  syncUpdates?: boolean;
}
