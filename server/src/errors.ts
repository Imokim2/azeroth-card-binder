// Every error the API can return, in one place. The same list is documented in docs/API.md; a test keeps them equal.
// A client acts on `code`, never on `message`, which is for people.
export const ERRORS = {
  bad_request: { status: 400, message: "The request could not be understood." },
  bad_signature: { status: 401, message: "The signature does not match the key." },
  unknown_key: { status: 401, message: "This key is not registered." },
  unauthorized: { status: 401, message: "The admin token is missing or wrong." },
  bad_identity: { status: 401, message: "The sign-in could not be verified." },
  banned: { status: 403, message: "This player is not allowed to upload." },
  not_found: { status: 404, message: "There is nothing here." },
  method_not_allowed: { status: 405, message: "That method is not supported here." },
  duplicate_batch: { status: 409, message: "These events are already stored with different contents." },
  replay: { status: 409, message: "These events were already stored." },
  gap: { status: 409, message: "Events are missing before this batch." },
  conflict: { status: 409, message: "Another upload for this player was in progress. Try again." },
  too_soon: { status: 429, message: "A binder was started recently. Try again later." },
  too_large: { status: 413, message: "The upload is too large." },
  unsupported_media: { status: 415, message: "Send JSON." },
  bad_field: { status: 422, message: "An event field is not valid." },
  bad_prev: { status: 422, message: "An event does not follow the one before it." },
  bad_hash: { status: 422, message: "An event was changed after it was written." },
  rule_broken: { status: 422, message: "The events describe a binder that cannot exist." },
  tape_invalid: { status: 422, message: "A ranked drop does not match the roll tape." },
  client_too_old: { status: 426, message: "Update the companion app." },
  internal: { status: 500, message: "Something went wrong on our side." },
  registration_closed: { status: 503, message: "Registration is not open yet." },
  ranked_unavailable: { status: 503, message: "Ranked play is not open yet." },
  overloaded: { status: 503, message: "The server is busy. Try again soon." },
} as const;

export type ErrorCode = keyof typeof ERRORS;

export class ApiError extends Error {
  readonly code: ErrorCode;
  readonly detail: Record<string, unknown> | undefined;
  readonly retryAfter: number | undefined;
  constructor(code: ErrorCode, detail?: Record<string, unknown>, retryAfter?: number) {
    super(ERRORS[code].message);
    this.code = code;
    this.detail = detail;
    this.retryAfter = retryAfter;
  }
}
