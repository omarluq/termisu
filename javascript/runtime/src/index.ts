export type RuntimeOptions = {
  libraryPath?: string;
};

export const createRuntime = (options: RuntimeOptions = {}) => {
  return {
    kind: "termisu-runtime" as const,
    options,
  };
};
