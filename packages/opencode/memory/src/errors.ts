import { ZodError } from "zod";

/** Errors crossing either transport contain only these fixed, non-sensitive messages. */
export class MemoryError extends Error {
  constructor(
    public readonly code: string,
    public readonly status: number,
    message: string,
  ) {
    super(message);
    this.name = "MemoryError";
  }
}

export const invalid = (): MemoryError =>
  new MemoryError("invalid_request", 400, "Invalid request.");
export const collision = (): MemoryError =>
  new MemoryError("event_collision", 409, "Event ID has different immutable content.");
export const wrongEpoch = (): MemoryError =>
  new MemoryError("epoch_mismatch", 409, "Synchronization epoch changed.");

export function publicError(error: unknown): MemoryError {
  if (error instanceof MemoryError) return error;
  if (error instanceof ZodError || error instanceof SyntaxError) return invalid();
  return new MemoryError("internal_error", 500, "Operation failed.");
}

/** Serializes complete operations, including the read/derive/write mutation boundary. */
export class SerialQueue {
  private tail: Promise<void> = Promise.resolve();

  run<T>(operation: () => Promise<T>): Promise<T> {
    const result = this.tail.then(operation);
    this.tail = result.then(() => undefined, () => undefined);
    return result;
  }
}
