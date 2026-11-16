// What the meetings routes need from LiveKit: its address, and a signed
// join token for a participant and grant. livekit.ts is the real one
// (livekit-server-sdk, from the LIVEKIT_* environment); tests pass a fake.
// Tokens are credentials: never log them.

/** One participant's token, as the callables' AccessToken + addGrant. */
export interface LiveKitGrantRequest {
  identity: string;
  name: string;
  metadata: string;
  ttl: string;
  room: string;
  canPublish: boolean;
}

export interface LiveKitSigner {
  /** The wss:// address clients connect to. */
  readonly url: string;
  sign(req: LiveKitGrantRequest): Promise<string>;
}
