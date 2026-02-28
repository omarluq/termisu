import type { RuntimeOptions } from "@termisu/runtime";

export type ReconcilerOptions = {
  runtime?: RuntimeOptions;
};

export const createReconciler = (_options: ReconcilerOptions = {}) => {
  return {
    kind: "termisu-reconciler" as const,
  };
};
